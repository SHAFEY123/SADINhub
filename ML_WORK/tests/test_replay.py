"""Task 0A tests.

Pure-logic tests run anywhere. Database-backed tests need SADINHUB_PASSWORD and compare the
replay against gold.energy_consumption_validated — which is the comparison target only, and
is never fed into the replay.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

ML_WORK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ML_WORK / "src"))

from conftest import make_readings, requires_db  # noqa: E402
from labels.replay import (  # noqa: E402
    STARTUP_CUTOFFS, replay_full_history, replay_validated_kwh,
)
from meters import fetch_meter_readings  # noqa: E402
from saudi_time import saudi_date, saudi_day_close_utc  # noqa: E402

LABEL = "ZN.99-PB_child__1_ch3pm"


# --------------------------------------------------------------------- pure logic

def test_saudi_day_is_utc_plus_three_and_86400_seconds():
    assert saudi_date(pd.Timestamp("2026-06-27 20:59:59")) == pd.Timestamp("2026-06-27")
    assert saudi_date(pd.Timestamp("2026-06-27 21:00:00")) == pd.Timestamp("2026-06-28")
    close = saudi_day_close_utc(pd.Timestamp("2026-06-27"))
    assert close == pd.Timestamp("2026-06-27 21:00:00")


def test_isolated_low_point_is_ignored_and_delta_bridges_it():
    """1218.4 -> 30.5 -> 1218.8 : the dip is dropped and the interval spans it."""
    r = make_readings(
        ["2026-01-05 06:00", "2026-01-05 06:05", "2026-01-05 06:10"],
        [1218.4, 30.5, 1218.8],
    )
    out = replay_full_history(r, LABEL)
    assert list(out["consumption_cleaning_status"]) == ["KEEP", "ISOLATED_LOW_BAD", "KEEP"]
    assert list(out["interval_quality"]) == [
        "FIRST_VALID_READING", "IGNORED_READING", "NORMAL_INTERVAL"]
    assert out["validated_kwh_consumption"].iloc[2] == pytest.approx(0.4)
    assert pd.isna(out["validated_kwh_consumption"].iloc[1])


def test_isolated_high_spike_is_ignored_and_recovery_is_kept():
    """35272.4 -> 94894 -> 35272.8 : the real ZN.3-PB.1 event on 2026-06-27."""
    r = make_readings(
        ["2026-06-27 09:16", "2026-06-27 09:20", "2026-06-27 09:24"],
        [35272.4, 94894.0, 35272.8],
    )
    out = replay_full_history(r, LABEL)
    assert list(out["consumption_cleaning_status"]) == ["KEEP", "ISOLATED_HIGH_BAD", "KEEP"]
    assert out["validated_kwh_consumption"].iloc[2] == pytest.approx(0.4)


def test_long_gap_threshold_is_fifteen_minutes_inclusive():
    r = make_readings(
        ["2026-01-05 06:00", "2026-01-05 06:14", "2026-01-05 06:29"],
        [100.0, 101.0, 102.0],
    )
    out = replay_full_history(r, LABEL)
    assert out["interval_quality"].iloc[1] == "NORMAL_INTERVAL"   # 14 min
    assert out["interval_quality"].iloc[2] == "LONG_GAP"          # exactly 15 min


def test_unexplained_decrement_yields_null_not_negative():
    r = make_readings(
        ["2026-01-05 06:00", "2026-01-05 06:05", "2026-01-05 06:10"],
        [500.0, 400.0, 401.0],
    )
    out = replay_full_history(r, LABEL)
    # 400 does not recover (401 < 500), so it is not an isolated low point.
    assert out["consumption_cleaning_status"].iloc[1] == "KEEP"
    assert pd.isna(out["validated_kwh_consumption"].iloc[1])
    assert (out["validated_kwh_consumption"].dropna() >= 0).all()


def test_startup_cutoff_is_strict_so_the_baseline_reading_is_kept():
    cutoff = STARTUP_CUTOFFS["ZN.1-PB.1"]
    r = make_readings(
        [cutoff - pd.Timedelta(minutes=5), cutoff, cutoff + pd.Timedelta(minutes=5)],
        [9999.0, 46.5, 46.9],
    )
    out = replay_full_history(r, "ZN.1-PB.1_child__1_ch3pm")
    assert out["consumption_cleaning_status"].iloc[0] == "STARTUP_EXCLUDED"
    assert out["consumption_cleaning_status"].iloc[1] == "KEEP"
    assert out["interval_quality"].iloc[1] == "FIRST_VALID_READING"
    assert out["validated_kwh_consumption"].iloc[2] == pytest.approx(0.4)


# ------------------------------------------------- point-in-time / leakage behaviour

def test_replay_never_uses_future_rows():
    """Poison every row after the cut; the result must be byte-identical."""
    ts = pd.date_range("2026-03-01 06:00", periods=12, freq="5min")
    clean = make_readings(ts, np.arange(100.0, 112.0))
    as_of = ts[5]

    poisoned = clean.copy()
    poisoned.loc[6:, "active_energy_cumulative_kwh"] = -1e9

    a = replay_validated_kwh(clean, LABEL, as_of)
    b = replay_validated_kwh(poisoned, LABEL, as_of)

    assert a["reading_timestamp_utc"].max() <= as_of
    pd.testing.assert_frame_equal(a, b)


def test_spike_at_end_of_day_is_provisional_and_diverges():
    """The one case the replay genuinely cannot resolve in real time.

    A spike that is the last reading of its Saudi day has no same-day successor, so at the
    close of day D it is carried forward unflagged as KEEP. It is only recognised as an
    isolated high spike once the next day's reading arrives.
    """
    ts = [
        "2026-03-01 20:50",   # Saudi 23:50 on 03-01
        "2026-03-01 20:55",   # Saudi 23:55 on 03-01  <- spike, last of the day
        "2026-03-01 21:05",   # Saudi 00:05 on 03-02  <- recovery, next day
    ]
    r = make_readings(ts, [35272.4, 94894.0, 35272.8])
    out = replay_full_history(r, LABEL)

    spike = out.iloc[1]
    assert spike["consumption_cleaning_status"] == "ISOLATED_HIGH_BAD"  # settled
    assert spike["realtime_status"] == "KEEP"                            # at day close
    assert bool(spike["realtime_differs"]) is True
    assert bool(spike["provisional_at_own_day_close"]) is True
    assert spike["as_of_confirmed_utc"] == pd.Timestamp("2026-03-02 21:00:00")


def test_same_day_successor_resolves_immediately():
    """The counterpart: a spike with a same-day successor never diverges."""
    r = make_readings(
        ["2026-06-27 09:16", "2026-06-27 09:20", "2026-06-27 09:24"],
        [35272.4, 94894.0, 35272.8],
    )
    out = replay_full_history(r, LABEL)
    assert out["realtime_differs"].sum() == 0
    assert bool(out["provisional_at_own_day_close"].iloc[1]) is False


# ------------------------------------------------------------------ database-backed

@requires_db
def test_all_23_forward_looking_corrections_are_reproduced(conn, forward_looking_rows):
    """Every ISOLATED_* reading in Gold must be reproduced by the replay, individually."""
    assert len(forward_looking_rows) == 23, "expected 23 forward-looking corrections"

    misses = []
    for key, group in forward_looking_rows.groupby("energy_meter_key"):
        label = group["meter_label"].iloc[0]
        readings = fetch_meter_readings(conn, key)
        rep = replay_full_history(readings, label).set_index("reading_timestamp_utc")
        for row in group.itertuples(index=False):
            got = rep.loc[row.reading_timestamp_utc, "consumption_cleaning_status"]
            if got != row.consumption_cleaning_status:
                misses.append(
                    f"{label} @ {row.reading_timestamp_utc}: "
                    f"expected {row.consumption_cleaning_status}, got {got}"
                )
    assert not misses, "\n".join(misses)


@requires_db
def test_forward_looking_corrections_all_resolve_within_their_own_saudi_day(
    conn, forward_looking_rows
):
    """The finding Task 0A exists to prove: none of the 23 is a day's last reading."""
    provisional = []
    for key, group in forward_looking_rows.groupby("energy_meter_key"):
        label = group["meter_label"].iloc[0]
        rep = replay_full_history(fetch_meter_readings(conn, key), label)
        rep = rep.set_index("reading_timestamp_utc")
        for row in group.itertuples(index=False):
            r = rep.loc[row.reading_timestamp_utc]
            if bool(r["provisional_at_own_day_close"]) or bool(r["realtime_differs"]):
                provisional.append(f"{label} @ {row.reading_timestamp_utc}")
    assert not provisional, (
        "these corrections would not be resolvable at their own day close: "
        + ", ".join(provisional)
    )


@requires_db
@pytest.mark.parametrize("n_meters", [5])
def test_replay_matches_gold_row_for_row(conn, scope_meters, n_meters):
    """Full equality on validated_kwh_consumption and interval_quality, per spec §7."""
    sql = """
        SELECT reading_timestamp_utc, validated_kwh_consumption, interval_quality
        FROM gold.energy_consumption_validated
        WHERE energy_meter_key = %s ORDER BY reading_timestamp_utc
    """
    for row in scope_meters.head(n_meters).itertuples(index=False):
        rep = replay_full_history(
            fetch_meter_readings(conn, row.energy_meter_key), row.meter_label)
        with conn.cursor() as cur:
            cur.execute(sql, (row.energy_meter_key,))
            gold = pd.DataFrame(
                cur.fetchall(),
                columns=["reading_timestamp_utc", "validated_kwh_consumption",
                         "interval_quality"])

        assert len(rep) == len(gold), f"{row.meter_label}: row count differs"
        merged = rep.merge(gold, on="reading_timestamp_utc",
                           suffixes=("_r", "_g"), how="outer", indicator=True)
        assert (merged["_merge"] == "both").all(), f"{row.meter_label}: timestamps differ"

        r = merged["validated_kwh_consumption_r"].to_numpy(dtype=float)
        g = merged["validated_kwh_consumption_g"].astype(float).to_numpy()
        assert np.allclose(r, g, rtol=0.0, atol=1e-9, equal_nan=True), \
            f"{row.meter_label}: consumption differs"
        assert (merged["interval_quality_r"] == merged["interval_quality_g"]).all(), \
            f"{row.meter_label}: interval_quality differs"


@requires_db
def test_strict_as_of_agrees_with_full_history(conn, scope_meters):
    """The strict definition and the linear implementation must agree.

    For sampled days, replaying with as_of = that day's close reproduces the settled
    classification for every reading of that day — which holds precisely because no
    correction in this history needs a next-day successor.
    """
    row = scope_meters.iloc[0]
    readings = fetch_meter_readings(conn, row.energy_meter_key)
    full = replay_full_history(readings, row.meter_label)

    days = pd.Series(full["reading_date_saudi"].unique()).sort_values()
    sample = list(days.iloc[[1, len(days) // 3, len(days) // 2, -2]])

    for day in sample:
        as_of = saudi_day_close_utc(pd.Timestamp(day))
        strict = replay_validated_kwh(readings, row.meter_label, as_of)
        strict_day = strict.loc[strict["reading_date_saudi"] == pd.Timestamp(day)]
        full_day = full.loc[full["reading_date_saudi"] == pd.Timestamp(day)]

        assert len(strict_day) == len(full_day), f"{day}: row count differs"
        merged = strict_day.merge(full_day, on="reading_timestamp_utc",
                                  suffixes=("_s", "_f"))
        # The day's final reading is provisional by construction; every other reading of
        # the day must already be settled.
        non_final = merged.iloc[:-1]
        assert (non_final["consumption_cleaning_status_s"]
                == non_final["consumption_cleaning_status_f"]).all(), \
            f"{day}: strict and full-history classifications disagree"
