"""Task 0B — reconstruction of the §11.2 daily profile and quality screen.

Consumes the Task 0A interval output. It never re-derives consumption from Gold: the kWh
values here are the replayed ones, so the daily table has a single lineage.

The two behaviours §11.2 states as outcomes rather than algorithms are reconstructed per the
approved addendum:

  duration coverage  each interval is clipped to the Saudi day window and the NORMAL_INTERVAL
                     seconds are divided by 86,400. Consumption is NOT clipped — it is
                     assigned whole to the Saudi date of the interval's ending reading, which
                     is the asymmetry §11.2 states explicitly.

  boundary days      per meter, the first and last Saudi dates over ALL replay rows,
                     including IGNORED_READING/STARTUP_EXCLUDED rows. Using the
                     FIRST_VALID_READING date instead would place ZN.1-PB.1 and ZN.4-PB.1 a
                     day late, because both carry startup-excluded readings on earlier dates.

Nothing is estimated, zero-filled, interpolated or backfilled. Missing calendar days are
inserted explicitly with a null consumption, and the screen is evaluated as a conjunction of
conditions over each meter-day.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from saudi_time import SAUDI_OFFSET, SECONDS_PER_SAUDI_DAY  # noqa: E402

COVERAGE_MIN = 0.95
COVERAGE_MAX = 1.00
RECOGNISED_QUALITY = {
    "NORMAL_INTERVAL", "LONG_GAP", "FIRST_VALID_READING", "IGNORED_READING",
}

OUTPUT_COLUMNS = [
    "energy_meter_key", "meter_label", "reading_date_saudi",
    "validated_kwh_consumption", "consumption_is_null",
    "n_readings", "n_normal_interval", "n_long_gap", "n_ignored", "n_first_valid",
    "normal_interval_seconds", "normal_interval_coverage",
    "is_missing_day", "is_boundary_day", "is_long_gap_touched",
    "has_duplicate_timestamp", "has_negative_consumption",
    "has_unrecognised_quality", "has_overlapping_normal_interval",
    "passes_quality_screen", "label_source",
]


def _saudi(ts: pd.Series) -> pd.Series:
    return ts + SAUDI_OFFSET


def normal_interval_seconds_by_day(rows: pd.DataFrame) -> pd.Series:
    """Seconds of NORMAL_INTERVAL duration falling inside each Saudi day.

    An interval runs (previous_valid_timestamp, reading_timestamp_utc]. Converted to Saudi
    local time and clipped at midnight, so an interval straddling midnight contributes to
    both days. A NORMAL_INTERVAL is under 15 minutes by definition, so it can touch at most
    two days; that is asserted rather than assumed.
    """
    normal = rows.loc[rows["interval_quality"] == "NORMAL_INTERVAL"]
    if normal.empty:
        return pd.Series(dtype="float64")

    start = _saudi(normal["previous_valid_timestamp"])
    end = _saudi(normal["reading_timestamp_utc"])
    start_day = start.dt.normalize()
    end_day = end.dt.normalize()

    spans = (end_day - start_day).dt.days
    if (spans > 1).any():
        raise ValueError(
            f"{int((spans > 1).sum())} NORMAL_INTERVAL rows span more than two Saudi days; "
            "the <15 minute invariant does not hold"
        )

    same = start_day == end_day
    parts = []

    # Wholly inside one day.
    parts.append(pd.DataFrame({
        "day": start_day[same],
        "seconds": (end[same] - start[same]).dt.total_seconds(),
    }))

    # Straddles midnight: split at the boundary.
    if (~same).any():
        s, e, sd, ed = start[~same], end[~same], start_day[~same], end_day[~same]
        parts.append(pd.DataFrame({"day": sd, "seconds": (ed - s).dt.total_seconds()}))
        parts.append(pd.DataFrame({"day": ed, "seconds": (e - ed).dt.total_seconds()}))

    allparts = pd.concat(parts, ignore_index=True)
    return allparts.groupby("day")["seconds"].sum()


def long_gap_touched_days(rows: pd.DataFrame) -> set:
    """Every Saudi date a LONG_GAP interval spans, endpoints included.

    §11.2 describes long_gap_intervals.csv as marking "every touched local date", so a gap is
    not reduced to its endpoints: a 201-day gap marks all ~202 dates it covers.
    """
    gaps = rows.loc[rows["interval_quality"] == "LONG_GAP"]
    touched: set = set()
    for start, end in zip(
        _saudi(gaps["previous_valid_timestamp"]).dt.normalize(),
        _saudi(gaps["reading_timestamp_utc"]).dt.normalize(),
    ):
        if pd.isna(start) or pd.isna(end):
            continue
        touched.update(pd.date_range(start, end, freq="D"))
    return touched


def _evidence_flags(rows: pd.DataFrame) -> pd.DataFrame:
    """Per-day data-integrity evidence. All of these are expected to be zero."""
    day = rows["reading_date_saudi"]

    dup = rows["reading_timestamp_utc"].duplicated(keep=False)
    neg = rows["validated_kwh_consumption"] < 0
    unrec = ~rows["interval_quality"].isin(RECOGNISED_QUALITY)

    # An overlapping interval starts before the previous interval in the VALID sequence
    # ended. It must be compared against the previous *valid* reading, not the previous raw
    # one: where a reading is ignored, the next interval legitimately bridges across it, so
    # previous_valid_timestamp is deliberately earlier than the preceding raw reading. That
    # bridge is the rule working, not an overlap.
    valid = rows["consumption_cleaning_status"] == "KEEP"
    prev_valid_end = rows.loc[valid, "reading_timestamp_utc"].shift(1)
    overlap = pd.Series(False, index=rows.index)
    overlap.loc[valid] = (
        rows.loc[valid, "previous_valid_timestamp"].notna()
        & prev_valid_end.notna()
        & (rows.loc[valid, "previous_valid_timestamp"] < prev_valid_end)
    )

    return pd.DataFrame({
        "has_duplicate_timestamp": dup, "has_negative_consumption": neg,
        "has_unrecognised_quality": unrec, "has_overlapping_normal_interval": overlap,
    }).groupby(day).any()


def build_meter_daily_profile(rows: pd.DataFrame) -> pd.DataFrame:
    """One complete Saudi calendar row per day between this meter's first and last reading."""
    rows = rows.sort_values("reading_timestamp_utc", kind="stable")
    meter_label = rows["meter_label"].iloc[0]
    meter_key = rows["energy_meter_key"].iloc[0]
    day = rows["reading_date_saudi"]

    # Boundary days: first and last date over ALL rows, ignored rows included.
    first_day, last_day = day.min(), day.max()
    calendar = pd.date_range(first_day, last_day, freq="D")

    kwh = rows.groupby(day)["validated_kwh_consumption"].sum(min_count=1)
    counts = pd.DataFrame({
        "n_readings": rows.groupby(day).size(),
        "n_normal_interval": rows.loc[rows["interval_quality"] == "NORMAL_INTERVAL"]
            .groupby(day).size(),
        "n_long_gap": rows.loc[rows["interval_quality"] == "LONG_GAP"].groupby(day).size(),
        "n_ignored": rows.loc[rows["interval_quality"] == "IGNORED_READING"]
            .groupby(day).size(),
        "n_first_valid": rows.loc[rows["interval_quality"] == "FIRST_VALID_READING"]
            .groupby(day).size(),
    })

    seconds = normal_interval_seconds_by_day(rows)
    touched = long_gap_touched_days(rows)
    evidence = _evidence_flags(rows)

    out = pd.DataFrame(index=calendar)
    out.index.name = "reading_date_saudi"
    out["energy_meter_key"] = meter_key
    out["meter_label"] = meter_label
    out["validated_kwh_consumption"] = kwh.reindex(calendar)
    out[counts.columns] = counts.reindex(calendar).fillna(0).astype("int64")
    out["normal_interval_seconds"] = seconds.reindex(calendar).fillna(0.0)
    out["normal_interval_coverage"] = (
        out["normal_interval_seconds"] / SECONDS_PER_SAUDI_DAY)

    out["is_missing_day"] = out["n_readings"] == 0
    out["is_boundary_day"] = out.index.isin([first_day, last_day])
    out["is_long_gap_touched"] = out.index.isin(touched)
    for col in ("has_duplicate_timestamp", "has_negative_consumption",
                "has_unrecognised_quality", "has_overlapping_normal_interval"):
        out[col] = evidence[col].reindex(calendar).fillna(False).astype(bool) \
            if col in evidence else False

    out["consumption_is_null"] = out["validated_kwh_consumption"].isna()

    # The screen is a conjunction over each meter-day, never a subtraction of category
    # counts: the exclusion categories overlap heavily (a long gap also creates missing days).
    out["passes_quality_screen"] = (
        ~out["is_missing_day"]
        & ~out["is_boundary_day"]
        & ~out["is_long_gap_touched"]
        & (out["normal_interval_coverage"] >= COVERAGE_MIN)
        & (out["normal_interval_coverage"] <= COVERAGE_MAX)
        & ~out["consumption_is_null"]
        & (out["validated_kwh_consumption"].fillna(-1) >= 0)
        & ~out["has_duplicate_timestamp"]
        & ~out["has_negative_consumption"]
        & ~out["has_unrecognised_quality"]
        & ~out["has_overlapping_normal_interval"]
    )
    out["label_source"] = "replay"
    return out.reset_index()[OUTPUT_COLUMNS]
