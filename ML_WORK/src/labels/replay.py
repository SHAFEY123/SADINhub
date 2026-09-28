"""Task 0A — leakage-safe point-in-time replay of the §6.7 validated-consumption rule.

Input is the raw cumulative register only (gold.energy_raw + gold.meter). Nothing derived
by the production rule is ever read; every derived column here is recomputed.

See replay_spec.md for the rule order, the point-in-time semantics and the output schema.

Two entry points:

  replay_validated_kwh(readings, meter_label, as_of_timestamp)
      The strict definition. Slices to reading_timestamp_utc <= as_of_timestamp *first*, so
      it is structurally incapable of reading a later row. This is the contract the
      documentation specifies and the one the no-future-rows test exercises.

  replay_full_history(readings, meter_label)
      The linear implementation used by the batch driver. One pass per meter, and it also
      emits the point-in-time evidence columns. A test proves it agrees with the strict
      function day by day.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from meters import short_label  # noqa: E402
from saudi_time import saudi_date, saudi_day_close_utc, utc_to_saudi  # noqa: E402

# Rule 3/4 — installation cutoffs. Strict '<': the reading at exactly the cutoff is KEEP.
STARTUP_CUTOFFS = {
    "ZN.1-PB.1": pd.Timestamp("2024-12-10 17:16:15.655"),
    "ZN.4-PB.1": pd.Timestamp("2024-12-10 21:46:39.010"),
}

IGNORED_STATUSES = ("ISOLATED_LOW_BAD", "ISOLATED_HIGH_BAD", "STARTUP_EXCLUDED", "MISSING_KWH")
LONG_GAP_MINUTES = 15.0

OUTPUT_COLUMNS = [
    "energy_meter_key", "meter_label",
    "reading_timestamp_utc", "reading_timestamp_saudi", "reading_date_saudi",
    "active_energy_cumulative_kwh",
    "previous_valid_timestamp", "previous_valid_kwh",
    "validated_kwh_consumption", "gap_minutes",
    "consumption_cleaning_status", "interval_quality",
    "realtime_status", "realtime_differs",
    "provisional_at_own_day_close", "as_of_confirmed_utc",
    "label_source",
]


def _classify(ts: np.ndarray, kwh: np.ndarray, short: str, successor_usable: np.ndarray):
    """Rules 2-7 of replay_spec.md, applied in reverse priority so higher rules win.

    `successor_usable[i]` says whether reading i+1 may be consulted. Rules 5 and 6 are the
    only ones that need it; everything else is backward-looking or a constant.
    """
    n = len(ts)
    status = np.full(n, "KEEP", dtype=object)
    if n == 0:
        return status

    prev_kwh = np.full(n, np.nan)
    prev_kwh[1:] = kwh[:-1]
    next_kwh = np.full(n, np.nan)
    next_kwh[:-1] = kwh[1:]

    has_prev = np.zeros(n, dtype=bool)
    has_prev[1:] = True
    has_next = np.asarray(successor_usable, dtype=bool)

    # Rule 6 - isolated high spike: above both neighbours, and the next recovers to >= prev.
    iso_high = (
        has_prev & has_next
        & (kwh > prev_kwh) & (kwh > next_kwh) & (next_kwh >= prev_kwh)
    )
    # Rule 5 - isolated low point: dips below prev, and the next recovers to >= prev.
    iso_low = has_prev & has_next & (kwh < prev_kwh) & (next_kwh >= prev_kwh)

    status[iso_high] = "ISOLATED_HIGH_BAD"
    status[iso_low] = "ISOLATED_LOW_BAD"

    cutoff = STARTUP_CUTOFFS.get(short)
    if cutoff is not None:
        status[ts < np.datetime64(cutoff)] = "STARTUP_EXCLUDED"

    status[np.isnan(kwh)] = "MISSING_KWH"
    return status


def _deltas(ts: np.ndarray, kwh: np.ndarray, status: np.ndarray):
    """Valid sequence (KEEP only), then previous-valid lookups and the interval delta."""
    n = len(ts)
    prev_valid_ts = np.full(n, np.datetime64("NaT", "ns"), dtype="datetime64[ns]")
    prev_valid_kwh = np.full(n, np.nan)

    keep_idx = np.flatnonzero(status == "KEEP")
    if len(keep_idx) > 1:
        prev_valid_ts[keep_idx[1:]] = ts[keep_idx[:-1]]
        prev_valid_kwh[keep_idx[1:]] = kwh[keep_idx[:-1]]

    gap_seconds = (ts - prev_valid_ts) / np.timedelta64(1, "s")
    gap_minutes = np.round(gap_seconds / 60.0, 2)

    with np.errstate(invalid="ignore"):
        consumption = np.where(
            np.isnan(prev_valid_kwh), np.nan,
            np.where(kwh >= prev_valid_kwh, kwh - prev_valid_kwh, np.nan),
        )
    return prev_valid_ts, prev_valid_kwh, gap_minutes, consumption


def _interval_quality(status, prev_valid_ts, gap_minutes):
    return np.where(
        np.isin(status.astype(str), IGNORED_STATUSES), "IGNORED_READING",
        np.where(
            np.isnat(prev_valid_ts), "FIRST_VALID_READING",
            np.where(gap_minutes >= LONG_GAP_MINUTES, "LONG_GAP", "NORMAL_INTERVAL"),
        ),
    )


def _frame(ts, kwh, status, meter_label, energy_meter_key=None):
    prev_valid_ts, prev_valid_kwh, gap_minutes, consumption = _deltas(ts, kwh, status)
    iq = _interval_quality(status, prev_valid_ts, gap_minutes)
    ts_idx = pd.DatetimeIndex(ts)
    return pd.DataFrame({
        "energy_meter_key": energy_meter_key,
        "meter_label": meter_label,
        "reading_timestamp_utc": ts_idx,
        "reading_timestamp_saudi": utc_to_saudi(ts_idx),
        "reading_date_saudi": saudi_date(ts_idx),
        "active_energy_cumulative_kwh": kwh,
        "previous_valid_timestamp": pd.DatetimeIndex(prev_valid_ts),
        "previous_valid_kwh": prev_valid_kwh,
        "validated_kwh_consumption": consumption,
        "gap_minutes": gap_minutes,
        "consumption_cleaning_status": status.astype(str),
        "interval_quality": iq,
        "label_source": "replay",
    })


def replay_validated_kwh(
    readings: pd.DataFrame,
    meter_label: str,
    as_of_timestamp: pd.Timestamp,
    energy_meter_key=None,
) -> pd.DataFrame:
    """Strict point-in-time replay.

    Uses ONLY readings with reading_timestamp_utc <= as_of_timestamp. The slice happens
    before any classification, so no later row can influence the result: the most recent
    reading in the cut has no usable successor and is therefore carried forward unflagged
    as KEEP, to be re-resolved on a later pass.
    """
    cut = readings.loc[readings["reading_timestamp_utc"] <= pd.Timestamp(as_of_timestamp)]
    cut = cut.sort_values("reading_timestamp_utc", kind="stable")

    ts = cut["reading_timestamp_utc"].to_numpy(dtype="datetime64[ns]")
    kwh = cut["active_energy_cumulative_kwh"].to_numpy(dtype=float)

    successor_usable = np.zeros(len(ts), dtype=bool)
    if len(ts):
        successor_usable[:-1] = True  # the final row of the cut has no successor

    status = _classify(ts, kwh, short_label(meter_label), successor_usable)
    out = _frame(ts, kwh, status, meter_label, energy_meter_key)
    out["as_of_timestamp_utc"] = pd.Timestamp(as_of_timestamp)
    return out


def replay_full_history(
    readings: pd.DataFrame,
    meter_label: str,
    energy_meter_key=None,
) -> pd.DataFrame:
    """Linear replay over one meter, with the point-in-time evidence columns.

    Emits, per reading, both the settled classification and the classification that would
    have been produced at the close of the reading's own Saudi day. The difference between
    them is the leakage the task exists to measure.
    """
    df = readings.sort_values("reading_timestamp_utc", kind="stable")
    ts = df["reading_timestamp_utc"].to_numpy(dtype="datetime64[ns]")
    kwh = df["active_energy_cumulative_kwh"].to_numpy(dtype=float)
    n = len(ts)
    short = short_label(meter_label)

    has_successor = np.zeros(n, dtype=bool)
    if n:
        has_successor[:-1] = True

    sd = saudi_date(pd.DatetimeIndex(ts))
    sd_vals = sd.to_numpy(dtype="datetime64[ns]")
    successor_same_day = np.zeros(n, dtype=bool)
    if n > 1:
        successor_same_day[:-1] = sd_vals[1:] == sd_vals[:-1]

    settled = _classify(ts, kwh, short, has_successor)
    realtime = _classify(ts, kwh, short, successor_same_day)

    out = _frame(ts, kwh, settled, meter_label, energy_meter_key)
    out["realtime_status"] = realtime.astype(str)
    out["realtime_differs"] = out["realtime_status"] != out["consumption_cleaning_status"]
    out["provisional_at_own_day_close"] = ~successor_same_day

    as_of_conf = np.full(n, np.datetime64("NaT", "ns"), dtype="datetime64[ns]")
    if n > 1:
        as_of_conf[:-1] = saudi_day_close_utc(
            pd.DatetimeIndex(sd_vals[1:])
        ).to_numpy(dtype="datetime64[ns]")
    out["as_of_confirmed_utc"] = pd.DatetimeIndex(as_of_conf)

    return out[OUTPUT_COLUMNS]
