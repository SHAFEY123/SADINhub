"""Task 0B tests — the §11.2 daily profile and quality-screen reconstruction.

Unit tests build tiny synthetic meters so each rule can be checked in isolation.
Integration tests read the artifacts Task 0A and Task 0B actually produced.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

ML_WORK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ML_WORK / "src"))

from labels.daily_profile import (  # noqa: E402
    build_meter_daily_profile, long_gap_touched_days, normal_interval_seconds_by_day,
)
from labels.replay import replay_full_history  # noqa: E402
from saudi_time import SECONDS_PER_SAUDI_DAY  # noqa: E402

LABEL = "ZN.99-PB_child__1_ch3pm"


def _replay(timestamps, kwh, label=LABEL):
    r = pd.DataFrame({
        "reading_timestamp_utc": pd.to_datetime(list(timestamps)),
        "active_energy_cumulative_kwh": [float(v) for v in kwh],
    })
    return replay_full_history(r, label, energy_meter_key="synthetic")


def _dense_day(day: str, n=288, step_min=5, start_kwh=1000.0, per=0.4, label=LABEL):
    """One Saudi day of evenly spaced readings, Saudi 00:00 through 23:55 inclusive.

    Exactly n readings, so the last lands at 23:55 and none spills into the next day.
    """
    start_utc = pd.Timestamp(day) - pd.Timedelta(hours=3)   # Saudi 00:00 == UTC 21:00 prev
    ts = [start_utc + pd.Timedelta(minutes=step_min * i) for i in range(n)]
    kwh = [start_kwh + per * i for i in range(n)]
    return ts, kwh


# ------------------------------------------------------------- Saudi-midnight clipping

def test_interval_straddling_saudi_midnight_is_split_between_both_days():
    # Saudi midnight on 2026-03-02 is 2026-03-01 21:00 UTC.
    rows = _replay(
        ["2026-03-01 20:56", "2026-03-01 21:04"],   # 8 min, 4 before / 4 after midnight
        [100.0, 100.4],
    )
    seconds = normal_interval_seconds_by_day(rows)
    assert seconds[pd.Timestamp("2026-03-01")] == pytest.approx(4 * 60)
    assert seconds[pd.Timestamp("2026-03-02")] == pytest.approx(4 * 60)


def test_consumption_is_not_split_it_lands_on_the_ending_readings_saudi_date():
    """The §11.2 asymmetry: duration splits at midnight, consumption does not."""
    rows = _replay(["2026-03-01 20:56", "2026-03-01 21:04"], [100.0, 100.4])
    profile = build_meter_daily_profile(rows)
    by_day = profile.set_index("reading_date_saudi")["validated_kwh_consumption"]
    assert by_day[pd.Timestamp("2026-03-02")] == pytest.approx(0.4)
    assert pd.isna(by_day[pd.Timestamp("2026-03-01")])


def test_coverage_is_clipped_seconds_over_86400_and_never_exceeds_one():
    """A fully covered day reaches exactly 1.0 and never more.

    Day one's own intervals give 287 x 5 min; the interval straddling into day two
    contributes its final 5 min back to day one, totalling exactly 86,400 s.
    """
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-06", start_kwh=kwh[-1] + 0.4)
    profile = build_meter_daily_profile(_replay(ts + ts2, kwh + kwh2))
    profile = profile.set_index("reading_date_saudi")

    assert profile.loc[pd.Timestamp("2026-03-05"), "normal_interval_seconds"] == \
        pytest.approx(SECONDS_PER_SAUDI_DAY)
    assert profile.loc[pd.Timestamp("2026-03-05"), "normal_interval_coverage"] == \
        pytest.approx(1.0)
    assert profile["normal_interval_coverage"].max() <= 1.0


# ------------------------------------------------------------------- boundary days

def test_first_and_last_day_are_boundary_days_and_nothing_else_is():
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-06", start_kwh=kwh[-1] + 0.4)
    ts3, kwh3 = _dense_day("2026-03-07", start_kwh=kwh2[-1] + 0.4)
    rows = _replay(ts + ts2 + ts3, kwh + kwh2 + kwh3)
    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")
    assert bool(p.loc[pd.Timestamp("2026-03-05"), "is_boundary_day"]) is True
    assert bool(p.loc[pd.Timestamp("2026-03-07"), "is_boundary_day"]) is True
    assert int(p["is_boundary_day"].sum()) == 2


def test_boundary_uses_all_rows_not_the_first_valid_reading():
    """The ZN.1-PB.1 / ZN.4-PB.1 case, in miniature.

    Startup-excluded readings sit on an earlier Saudi date than the first valid reading. The
    boundary must be the earlier date, or a partial day is admitted into the training set.
    """
    cutoff = pd.Timestamp("2024-12-10 17:16:15.655")
    rows = _replay(
        [cutoff - pd.Timedelta(days=1), cutoff - pd.Timedelta(hours=1),
         cutoff, cutoff + pd.Timedelta(minutes=5)],
        [9000.0, 9500.0, 46.5, 46.9],
        label="ZN.1-PB.1_child__1_ch3pm",
    )
    excluded_day = rows.loc[
        rows["consumption_cleaning_status"] == "STARTUP_EXCLUDED", "reading_date_saudi"].min()
    first_valid_day = rows.loc[
        rows["interval_quality"] == "FIRST_VALID_READING", "reading_date_saudi"].iloc[0]
    assert excluded_day < first_valid_day, "fixture must exercise the ZN.1/ZN.4 case"

    p = build_meter_daily_profile(rows)
    boundary_first = p.loc[p["is_boundary_day"], "reading_date_saudi"].min()
    assert boundary_first == excluded_day
    assert boundary_first != first_valid_day


# -------------------------------------------------------------------- missing days

def test_missing_calendar_days_are_inserted_and_never_zero_filled():
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-09", start_kwh=kwh[-1] + 10)   # 03-06..03-08 absent
    rows = _replay(ts + ts2, kwh + kwh2)
    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")

    gap_days = [pd.Timestamp(f"2026-03-0{d}") for d in (6, 7, 8)]
    assert len(p) == 5, "the calendar must be complete between first and last day"
    for d in gap_days:
        assert bool(p.loc[d, "is_missing_day"]) is True
        assert pd.isna(p.loc[d, "validated_kwh_consumption"]), "must be null, not zero"
        assert p.loc[d, "n_readings"] == 0
        assert bool(p.loc[d, "passes_quality_screen"]) is False


def test_no_backfill_or_interpolation_across_a_missing_day():
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-07", start_kwh=kwh[-1] + 50)
    rows = _replay(ts + ts2, kwh + kwh2)
    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")
    # The jump in the register is carried on the resumption day, not spread backwards.
    assert pd.isna(p.loc[pd.Timestamp("2026-03-06"), "validated_kwh_consumption"])
    assert p.loc[pd.Timestamp("2026-03-07"), "validated_kwh_consumption"] > 50


# --------------------------------------------------------------------- long gaps

def test_long_gap_marks_every_saudi_date_it_spans_not_only_endpoints():
    rows = _replay(
        ["2026-03-01 06:00", "2026-03-06 06:00"],   # a 5-day gap
        [100.0, 500.0],
    )
    touched = long_gap_touched_days(rows)
    expected = set(pd.date_range("2026-03-01", "2026-03-06", freq="D"))
    assert touched == expected, "every spanned date must be marked, endpoints included"


def test_long_gap_touched_days_are_screened_out():
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-09", start_kwh=kwh[-1] + 10)
    rows = _replay(ts + ts2, kwh + kwh2)
    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")
    assert bool(p.loc[pd.Timestamp("2026-03-09"), "is_long_gap_touched"]) is True
    assert bool(p.loc[pd.Timestamp("2026-03-09"), "passes_quality_screen"]) is False


# ------------------------------------------------------------- screen conjunction

def test_screen_is_a_conjunction_every_condition_can_veto_alone():
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-06", start_kwh=kwh[-1] + 0.4)
    ts3, kwh3 = _dense_day("2026-03-07", start_kwh=kwh2[-1] + 0.4)
    rows = _replay(ts + ts2 + ts3, kwh + kwh2 + kwh3)
    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")

    middle = pd.Timestamp("2026-03-06")
    assert bool(p.loc[middle, "passes_quality_screen"]) is True

    vetoes = ["is_missing_day", "is_boundary_day", "is_long_gap_touched",
              "has_duplicate_timestamp", "has_negative_consumption",
              "has_unrecognised_quality", "has_overlapping_normal_interval"]
    for flag in vetoes:
        one = p.copy()
        one[flag] = one.index == middle
        recomputed = (
            ~one["is_missing_day"] & ~one["is_boundary_day"] & ~one["is_long_gap_touched"]
            & (one["normal_interval_coverage"] >= 0.95)
            & (one["normal_interval_coverage"] <= 1.00)
            & ~one["consumption_is_null"]
            & ~one["has_duplicate_timestamp"] & ~one["has_negative_consumption"]
            & ~one["has_unrecognised_quality"] & ~one["has_overlapping_normal_interval"]
        )
        assert not bool(recomputed.loc[middle]), f"{flag} alone must veto the day"


def test_low_coverage_day_fails_the_screen():
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-06", n=200, start_kwh=kwh[-1] + 0.4)  # ~69% coverage
    ts3, kwh3 = _dense_day("2026-03-07", start_kwh=kwh2[-1] + 0.4)
    rows = _replay(ts + ts2 + ts3, kwh + kwh2 + kwh3)
    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")
    middle = pd.Timestamp("2026-03-06")
    assert p.loc[middle, "normal_interval_coverage"] < 0.95
    assert bool(p.loc[middle, "passes_quality_screen"]) is False


def test_the_bridge_across_an_ignored_reading_is_not_an_overlap():
    """Regression: an ignored reading makes the next interval span it. That is the rule
    working, and must not be reported as an overlapping interval."""
    ts, kwh = _dense_day("2026-03-05")
    ts2, kwh2 = _dense_day("2026-03-06", start_kwh=kwh[-1] + 0.4)
    ts3, kwh3 = _dense_day("2026-03-07", start_kwh=kwh2[-1] + 0.4)
    t, k = ts + ts2 + ts3, kwh + kwh2 + kwh3
    k[len(ts) + 100] = 5.0   # an isolated low point inside 2026-03-06
    rows = _replay(t, k)
    assert (rows["consumption_cleaning_status"] == "ISOLATED_LOW_BAD").sum() == 1

    p = build_meter_daily_profile(rows).set_index("reading_date_saudi")
    assert bool(p.loc[pd.Timestamp("2026-03-06"), "has_overlapping_normal_interval"]) is False


# --------------------------------------------------------------------- integration

def _latest(pattern: str) -> Path | None:
    hits = sorted((ML_WORK / "outputs").glob(pattern))
    return hits[-1] if hits else None


PROFILE = _latest("task0b_*/daily_consumption_profile_v2.csv")
requires_profile = pytest.mark.skipif(
    PROFILE is None, reason="no Task 0B output; run src/labels/run_daily_profile.py")


@requires_profile
def test_published_reconciliation_counts_are_reproduced():
    d = pd.read_csv(PROFILE)
    assert len(d) == 16_704, "calendar meter-days"
    assert int((~d["is_missing_day"]).sum()) == 14_753, "meter-days with readings"
    assert int(d["is_missing_day"].sum()) == 1_951, "inserted missing meter-days"
    assert int(d["is_boundary_day"].sum()) == 58, "boundary meter-days"
    assert int(d["is_long_gap_touched"].sum()) == 2_421, "long-gap-touched meter-days"
    assert int(d["passes_quality_screen"].sum()) == 14_228, "meter-days passing the screen"
    assert d["meter_label"].nunique() == 29
    assert d["validated_kwh_consumption"].sum() == pytest.approx(2_020_697.5, abs=0.05)


@requires_profile
def test_boundary_days_are_exactly_two_per_meter():
    d = pd.read_csv(PROFILE)
    per_meter = d.groupby("meter_label")["is_boundary_day"].sum()
    assert (per_meter == 2).all(), "every meter must contribute exactly two boundary days"
    assert len(per_meter) == 29


@requires_profile
def test_missing_days_carry_no_consumption_and_no_readings():
    d = pd.read_csv(PROFILE)
    missing = d.loc[d["is_missing_day"]]
    assert missing["validated_kwh_consumption"].isna().all(), "never zero-filled"
    assert (missing["n_readings"] == 0).all()
    assert not missing["passes_quality_screen"].any()


@requires_profile
def test_exclusion_categories_overlap_so_the_screen_cannot_be_a_subtraction():
    d = pd.read_csv(PROFILE)
    excluded = len(d) - int(d["passes_quality_screen"].sum())
    category_sum = int(d["is_missing_day"].sum() + d["is_boundary_day"].sum()
                       + d["is_long_gap_touched"].sum())
    assert category_sum > excluded, "categories must overlap"
    assert category_sum - excluded == 1_954


@requires_profile
def test_every_passing_day_has_coverage_in_band_and_real_consumption():
    d = pd.read_csv(PROFILE)
    ok = d.loc[d["passes_quality_screen"]]
    assert (ok["normal_interval_coverage"] >= 0.95).all()
    assert (ok["normal_interval_coverage"] <= 1.00).all()
    assert ok["validated_kwh_consumption"].notna().all()
    assert (ok["validated_kwh_consumption"] >= 0).all()
    assert not ok["is_missing_day"].any()
    assert not ok["is_boundary_day"].any()
    assert not ok["is_long_gap_touched"].any()
