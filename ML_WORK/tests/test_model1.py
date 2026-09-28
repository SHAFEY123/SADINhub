"""Model 1 — detector tests, section 9 of the design specification.

Every family gets positive tests (must fire), negative tests (must not fire) and synthetic
tests that prove behaviour without the live database. The database-backed tests assert the
acceptance and reconciliation tables produced by the most recent run.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from conftest import requires_db  # noqa: F401
from model1_anomaly_raw import detectors, severity
from model1_anomaly_raw.config import SEVERITY_RANK, load_config
from model1_anomaly_raw.episodes import collapse, collapse_days
from model1_anomaly_raw.scope import PHASE_COLUMNS

ML_WORK = Path(__file__).resolve().parent.parent
CB = 100.0
METER = {"energy_meter_key": "k", "meter_label": "ZN.TEST-PB_child__1_ch3pm",
         "short_label": "ZN.TEST-PB", "zone_name": "Zone T", "cb_max_rating_a": CB}


@pytest.fixture(scope="module")
def cfg() -> dict:
    return load_config()


def make_readings(n=200, kw=10.0, amps=20.0, pf=0.95, kwh_step=0.5,
                  start="2025-03-01") -> pd.DataFrame:
    """A synthetic healthy meter: forward power, load well above the gate, good PF."""
    ts = pd.date_range(start, periods=n, freq="5min")
    d = {"reading_timestamp_utc": ts,
         "active_energy_cumulative_kwh": np.arange(n, dtype=float) * kwh_step,
         "active_power_total_kw": np.full(n, kw * 3)}
    for p, (kw_col, amp_col, pf_col, amp_st, pf_st) in PHASE_COLUMNS.items():
        d[kw_col] = np.full(n, float(kw))
        d[amp_col] = np.full(n, float(amps))
        d[pf_col] = np.full(n, float(pf))
        d[amp_st] = ["Acceptable"] * n
        d[pf_st] = ["Acceptable"] * n
    return pd.DataFrame(d)


def daily_frame(n=120, mean_kw=10.0, n_readings=300, advance=50.0, amps_sum=60.0,
                start="2025-01-01") -> pd.DataFrame:
    days = pd.date_range(start, periods=n, freq="D")
    d = {"day_saudi": days,
         "n_readings": np.full(n, n_readings, dtype="int64"),
         "day_advance_kwh": np.full(n, float(advance)),
         "mean_amps_sum": np.full(n, float(amps_sum))}
    for p in PHASE_COLUMNS:
        d[f"mean_kw_phase_{p}"] = np.full(n, float(mean_kw))
    return pd.DataFrame(d)


# ------------------------------------------------------------------ episodes

def test_episode_boundary_is_exactly_the_flip_row():
    """Design spec section 9, T1 synthetic: a known sign flip at row n gives a boundary at n."""
    ts = pd.date_range("2025-01-01", periods=100, freq="5min")
    flags = np.zeros(100, dtype=bool)
    flags[42:] = True
    eps = collapse(ts, flags, merge_gap_minutes=360)
    assert len(eps) == 1
    assert eps[0]["first_index"] == 42
    assert eps[0]["last_index"] == 99
    assert eps[0]["n_flagged"] == 58


def test_short_recovery_merges_but_a_long_gap_splits():
    ts = pd.date_range("2025-01-01", periods=300, freq="5min")
    flags = np.zeros(300, dtype=bool)
    flags[0:10] = True          # then a 50-minute quiet stretch
    flags[20:30] = True
    assert len(collapse(ts, flags, merge_gap_minutes=360)) == 1
    assert len(collapse(ts, flags, merge_gap_minutes=10)) == 2


def test_a_real_telemetry_gap_splits_index_adjacent_flags():
    """Two flagged readings adjacent in INDEX but 201 days apart are not one episode."""
    ts = pd.to_datetime(["2025-05-18 04:22", "2025-12-05 12:55"])
    eps = collapse(ts, np.array([True, True]), merge_gap_minutes=360)
    assert len(eps) == 2


# ------------------------------------------------------------------ T1 polarity

def test_t1_fires_on_reverse_power_with_current(cfg):
    df = make_readings()
    df.loc[50:, PHASE_COLUMNS[2][0]] = -8.0
    events = detectors.detect_polarity(df, METER, cfg)
    assert [e["phase"] for e in events] == [2]
    assert events[0]["detector"] == "reverse_power"
    assert events[0]["magnitude"] == pytest.approx(8.0)


def test_t1_silent_on_a_healthy_meter(cfg):
    assert detectors.detect_polarity(make_readings(), METER, cfg) == []


def test_t1_ignores_negative_power_with_no_current(cfg):
    """Reverse power WITHOUT current is a different condition, not a polarity fault."""
    df = make_readings()
    df.loc[50:, PHASE_COLUMNS[1][0]] = -8.0
    df.loc[50:, PHASE_COLUMNS[1][1]] = 0.0
    assert detectors.detect_polarity(df, METER, cfg) == []


def test_t1_treats_exact_zero_power_as_not_negative(cfg):
    df = make_readings()
    df.loc[50:, PHASE_COLUMNS[1][0]] = 0.0
    assert detectors.detect_polarity(df, METER, cfg) == []


# ------------------------------------------------------------------ T2 current/power

def test_t2_current_without_power_and_power_without_current(cfg):
    df = make_readings()
    df.loc[10:20, PHASE_COLUMNS[1][0]] = 0.0          # current flowing, no power
    df.loc[60:70, PHASE_COLUMNS[3][1]] = 0.0          # power without current
    found = {(e["detector"], e["phase"])
             for e in detectors.detect_current_power(df, METER, cfg)}
    assert ("current_without_power", 1) in found
    assert ("power_without_current", 3) in found


def test_t2_uses_literal_zero_with_no_epsilon(cfg):
    df = make_readings()
    df.loc[10:20, PHASE_COLUMNS[1][0]] = 1e-9         # tiny but NOT zero
    assert detectors.detect_current_power(df, METER, cfg) == []


def test_t2_null_power_is_not_an_inconsistency(cfg):
    df = make_readings()
    df.loc[10:20, PHASE_COLUMNS[1][0]] = np.nan
    df.loc[10:20, PHASE_COLUMNS[1][1]] = 0.0
    assert detectors.detect_current_power(df, METER, cfg) == []


def test_t2_records_whether_it_is_outside_the_existing_rule_reach(cfg):
    df = make_readings(amps=80.0)                     # 80% of a 100 A breaker
    df.loc[10:20, PHASE_COLUMNS[1][0]] = 0.0
    ev = [e for e in detectors.detect_current_power(df, METER, cfg)
          if e["detector"] == "current_without_power"][0]
    assert ev["outside_existing_rule_reach"] is True
    assert ev["mean_load_pct_cb"] == pytest.approx(80.0)


# ------------------------------------------------------------------ T3 power factor

def test_t3_raises_nothing_below_the_load_gate(cfg):
    """Design spec section 9: zero events from any reading below 5% of breaker rating."""
    df = make_readings(amps=4.0, pf=0.30)             # 4% CB, terrible PF
    assert detectors.detect_power_factor(df, METER, cfg) == []


def test_t3_fires_on_the_same_bad_pf_once_the_load_gate_opens(cfg):
    df = make_readings(amps=20.0, pf=0.30)            # 20% CB, same PF
    events = detectors.detect_power_factor(df, METER, cfg)
    band = [e for e in events if e["detector"] == "pf_below_acceptable"]
    assert band and band[0]["pf_band_worst"] == "Critical"
    assert band[0]["readings_excluded_low_load"] == 0


def test_t3_band_edges_match_the_production_classifier(cfg):
    bands = cfg["t3_power_factor"]["bands"]
    assert (bands["critical"], bands["problematic"], bands["review_required"]) == (
        0.6, 0.78, 0.8)
    df = make_readings(pf=0.80)                       # exactly acceptable
    assert [e for e in detectors.detect_power_factor(df, METER, cfg)
            if e["detector"] == "pf_below_acceptable"] == []


def test_t3_never_reports_a_reversed_phase_as_a_pf_fault(cfg):
    """A reversed CT gives PF about -0.8. That belongs to T1, not to T3."""
    df = make_readings(pf=-0.8)
    band = [e for e in detectors.detect_power_factor(df, METER, cfg)
            if e["detector"] == "pf_below_acceptable"]
    assert band == []


def test_t3_cusum_is_one_sided_and_ignores_healthy_drift_above_target(cfg):
    """PF sustained ABOVE 0.8 is good operation; flagging it reports healthy meters."""
    df = make_readings(n=400, pf=0.97)
    assert [e for e in detectors.detect_power_factor(df, METER, cfg)
            if e["detector"] == "pf_cusum_drift"] == []


def test_cusum_detects_sustained_downward_drift_not_single_point_noise():
    rng = np.random.default_rng(7)
    noise = 0.9 + rng.normal(0, 0.01, 400)
    assert not cusum_down(noise)
    drifting = noise.copy()
    drifting[200:] -= 0.25
    assert cusum_down(drifting)


def cusum_down(x, target=0.8, k=0.5, h=5.0) -> bool:
    r = detectors.cusum(np.asarray(x), target, k, h)
    return bool((r["flags"] & (r["direction"] < 0)).any())


# ------------------------------------------------------------------ T4 change / drift

def test_t4_detects_a_known_step_change(cfg):
    daily = daily_frame(n=120, mean_kw=10.0)
    daily.loc[80:, [f"mean_kw_phase_{p}" for p in PHASE_COLUMNS]] = 40.0
    events = detectors.detect_change(daily, METER, cfg, [])
    shifts = [e for e in events if e["detector"] == "ewma_level_shift"]
    assert shifts
    lag = (pd.Timestamp(min(e["event_start"] for e in shifts))
           - daily.loc[80, "day_saudi"]).days
    assert 0 <= lag <= 3, f"step detected {lag} days late"


def test_t4_does_not_flag_stationary_noise(cfg):
    rng = np.random.default_rng(11)
    daily = daily_frame(n=200)
    for p in PHASE_COLUMNS:
        daily[f"mean_kw_phase_{p}"] = 10.0 + rng.normal(0, 0.4, 200)
    shifts = [e for e in detectors.detect_change(daily, METER, cfg, [])
              if e["detector"] == "ewma_level_shift"]
    assert len(shifts) <= 2, f"{len(shifts)} false level shifts on stationary noise"


def test_t4_classifies_an_outage_as_data_availability_not_an_electrical_fault(cfg):
    """The Feb 2026 facility outage must never be reported as an electrical fault."""
    daily = daily_frame(n=120)
    daily.loc[40:55, "n_readings"] = 0
    events = detectors.detect_change(daily, METER, cfg, [])
    outage = [e for e in events if e["detector"] == "data_availability"]
    assert len(outage) == 1
    assert outage[0]["event_class"] == "DATA_AVAILABILITY"
    assert all(e["event_class"] != "DATA_AVAILABILITY" for e in events
               if e["detector"] != "data_availability")


def test_t4_reports_when_a_self_referential_baseline_is_unavailable(cfg):
    """A fault spanning the whole history leaves no clean baseline. Say so, do not hide it."""
    daily = daily_frame(n=60)
    daily.loc[20:, [f"mean_kw_phase_{p}" for p in PHASE_COLUMNS]] = 40.0
    windows = [(daily["day_saudi"].min(), daily["day_saudi"].max())]
    events = [e for e in detectors.detect_change(daily, METER, cfg, windows)
              if e["detector"] == "ewma_level_shift"]
    assert events and all(e["self_referential_baseline_unavailable"] for e in events)


def test_ewma_baseline_gap_keeps_a_step_from_hiding_in_its_own_reference():
    """Without the gap the control limit outruns the deviation and the step is missed."""
    x = np.concatenate([np.full(60, 10.0), np.full(20, 40.0)])
    x += np.random.default_rng(3).normal(0, 0.5, 80)
    no_gap = detectors.ewma_flags(x, 0.3, 3.0, 30, 14, baseline_gap=0)["flags"][60:].sum()
    gapped = detectors.ewma_flags(x, 0.3, 3.0, 30, 14, baseline_gap=7)["flags"][60:].sum()
    assert gapped > no_gap


# ------------------------------------------------------------------ T5 register

def test_t5_fires_on_a_frozen_register_under_load(cfg):
    daily = daily_frame(n=60)
    daily.loc[20:40, "day_advance_kwh"] = 0.0
    events = [e for e in detectors.detect_register(daily, METER, cfg)
              if e["detector"] == "stuck_register"]
    assert len(events) == 1
    assert events[0]["n_flagged"] == 21


def test_t5_records_both_absolute_and_breaker_normalised_load_evidence(cfg):
    daily = daily_frame(n=60, amps_sum=60.0)
    daily.loc[20:40, "day_advance_kwh"] = 0.0
    ev = [e for e in detectors.detect_register(daily, METER, cfg)
          if e["detector"] == "stuck_register"][0]
    assert ev["mean_current_a"] == pytest.approx(60.0)
    assert ev["mean_current_pct_cb"] == pytest.approx(20.0)   # 60/3 of a 100 A breaker
    assert ev["load_evidence_rules"] == "legacy_amps+normalized"


def test_t5_legacy_amps_rule_is_preserved_independently(cfg):
    """Below 5 A but above 1% CB: the normalised rule fires, the legacy rule does not."""
    daily = daily_frame(n=60, amps_sum=4.0)
    daily.loc[20:40, "day_advance_kwh"] = 0.0
    ev = [e for e in detectors.detect_register(daily, METER, cfg)
          if e["detector"] == "stuck_register"][0]
    assert ev["days_legacy_rule"] == 0
    assert ev["days_normalized_rule"] == 21
    assert ev["load_evidence_rules"] == "normalized"


def test_t5_ignores_a_frozen_register_with_no_load(cfg):
    daily = daily_frame(n=60, amps_sum=0.0)
    daily.loc[20:40, "day_advance_kwh"] = 0.0
    assert [e for e in detectors.detect_register(daily, METER, cfg)
            if e["detector"] == "stuck_register"] == []


def test_t5_ignores_partial_days(cfg):
    daily = daily_frame(n=60, n_readings=50)
    daily.loc[20:40, "day_advance_kwh"] = 0.0
    assert [e for e in detectors.detect_register(daily, METER, cfg)
            if e["detector"] == "stuck_register"] == []


def test_t5_must_not_run_at_reading_grain(cfg):
    """A healthy register ticks in coarse steps, so most consecutive readings show no
    advance. This is why the detector is day grain, and the test proves the failure mode."""
    df = make_readings(n=1000, kwh_step=0.0)
    kwh = (np.arange(1000) // 10) * 0.5           # ticks once every ten readings
    df["active_energy_cumulative_kwh"] = kwh
    no_advance = (np.diff(kwh) == 0).mean()
    assert no_advance >= 0.85, "fixture should look like a real coarse register"
    daily = daily_frame(n=5)                       # same meter, day grain, register advances
    assert [e for e in detectors.detect_register(daily, METER, cfg)
            if e["detector"] == "stuck_register"] == []


def test_t5_detects_a_register_that_goes_backwards(cfg):
    df = make_readings(n=100)
    df.loc[50, "active_energy_cumulative_kwh"] = 0.0
    events = [e for e in detectors.detect_register(daily_frame(n=5), METER, cfg, df)
              if e["detector"] == "register_decrease"]
    assert len(events) == 1 and events[0]["grain"] == "reading"


# ------------------------------------------------------------------ severity

def _events(**over) -> pd.DataFrame:
    base = {"short_label": "ZN.TEST-PB", "meter_label": "ZN.TEST-PB_child__1_ch3pm",
            "family": "T3", "detector": "pf_below_acceptable",
            "phase": 1, "duration_hours": 2.0, "magnitude": 0.1, "magnitude_unit": "u",
            "corroboration": "none", "event_class": "ELECTRICAL_FAULT",
            "event_end": pd.Timestamp("2025-06-01"), "n_flagged": 5}
    base.update(over)
    return pd.DataFrame([base])


def test_t5_physics_contradiction_is_critical_at_any_duration(cfg):
    """T5 keeps the unconditional rule; T1 reverse power is graded instead (see below)."""
    ev = severity.assign(_events(family="T5", detector="stuck_register",
                                 duration_hours=0.5), cfg)
    assert ev.loc[0, "severity"] == "Critical"
    assert bool(ev.loc[0, "physics_contradiction"]) is True


def test_t1_reverse_power_is_no_longer_an_unconditional_physics_contradiction(cfg):
    """The superseded policy made every kW < 0 episode Critical regardless of evidence."""
    ev = severity.assign(_t1(duration_hours=0.5), cfg)
    assert bool(ev.loc[0, "physics_contradiction"]) is False
    assert ev.loc[0, "severity"] != "Critical"


def test_chronic_low_magnitude_is_problematic_not_critical(cfg):
    ev = severity.assign(_events(duration_hours=24 * 40), cfg)
    assert ev.loc[0, "severity"] == "Problematic"


def test_commissioning_episodes_are_capped_and_labelled(cfg):
    ev = severity.assign(_events(family="T1", detector="reverse_power",
                                 event_end=pd.Timestamp("2024-12-27")), cfg)
    assert ev.loc[0, "severity"] == "Review Required"
    assert bool(ev.loc[0, "commissioning"]) is True
    assert ev.loc[0, "event_class"] == "COMMISSIONING"
    assert bool(ev.loc[0, "severity_capped_by_commissioning"]) is True


def test_monitor_only_phase_never_reaches_an_asserted_severity(cfg):
    ev = severity.assign(_events(short_label="ZN.5-PB",
                                 meter_label="ZN.5-PB_child__1_ch3pm",
                                 phase=3, family="T1", detector="reverse_power"), cfg)
    assert bool(ev.loc[0, "monitor_only"]) is True
    assert ev.loc[0, "severity"] not in {"Critical", "Problematic"}


def test_severity_ladder_uses_the_reserved_anomaly_rank():
    assert SEVERITY_RANK["Review Required"] < SEVERITY_RANK["Anomaly"]
    assert SEVERITY_RANK["Anomaly"] < SEVERITY_RANK["Problematic"]


# ------------------------------------------------------------------ configuration

def test_every_threshold_lives_in_the_config_file(cfg):
    for section in ("t1_polarity", "t2_current_power", "t3_power_factor",
                    "t4_change", "t5_register", "commissioning", "episodes"):
        assert cfg[section]


def test_pf_gate_equals_the_production_third_constant(cfg):
    """margin = 0.15 * CB and third = margin / 3 = 0.05 * CB, already in the classifier."""
    margin_pct = cfg["t2_current_power"]["existing_rule_gate_pct_cb"]
    assert cfg["t3_power_factor"]["min_load_pct_cb"] == pytest.approx(margin_pct / 3.0)


def test_commissioning_boundary_is_labelled_as_an_assumption(cfg):
    assert "assumed" in cfg["commissioning"]["status"]
    assert cfg["commissioning"]["assumed_boundary_date"] == "2024-12-31"


# ------------------------------------------------------------------ run artifacts

def _latest_run() -> Path:
    """The newest directory that is an actual detector run, not the design evidence pack."""
    runs = [p for p in sorted((ML_WORK / "outputs").glob("model1_*"))
            if (p / "acceptance_results.csv").exists()]
    if not runs:
        pytest.skip("no Model 1 detector run found")
    return runs[-1]


def test_known_findings_are_detected():
    """The section 9 gate: every acceptance criterion from the most recent run."""
    acceptance = pd.read_csv(_latest_run() / "acceptance_results.csv")
    failures = acceptance[acceptance["result"] != "PASS"]
    assert failures.empty, failures.to_string(index=False)


def test_run_reconciles_against_measured_reference_values():
    recon = pd.read_csv(_latest_run() / "reconciliation.csv")
    failures = recon[recon["result"] != "PASS"]
    assert failures.empty, failures.to_string(index=False)


def test_run_metadata_records_read_only_access_and_claims_no_precision():
    meta = json.loads((_latest_run() / "run_metadata.json").read_text(encoding="utf-8"))
    assert meta["connection"]["transaction_read_only"] == "on"
    assert meta["connection"]["transaction_isolation"] == "repeatable read"
    assert "NOT CLAIMED" in meta["precision_and_recall"]
    assert meta["writes_outside_ml_work"] == []


def test_every_event_is_an_episode_with_the_required_columns():
    events = pd.read_parquet(_latest_run() / "anomaly_events.parquet")
    required = {"meter_label", "phase", "family", "detector", "event_start", "event_end",
                "severity", "concurrent_status", "evidence_window_rows", "commissioning",
                "event_class", "description"}
    assert required <= set(events.columns)
    assert (events["event_end"] >= events["event_start"]).all()
    assert events["severity"].isin(SEVERITY_RANK).all()


def test_no_output_is_written_outside_ml_work():
    run = _latest_run()
    assert ML_WORK in run.parents
    for f in run.iterdir():
        assert ML_WORK in f.parents


# ------------------------------------------------------------------ T1 graded severity

def _t1(**over) -> pd.DataFrame:
    """A T1 reverse-power event with the evidence fields the graded rule reads."""
    base = {"short_label": "ZN.TEST-PB", "meter_label": "ZN.TEST-PB_child__1_ch3pm",
            "family": "T1", "detector": "reverse_power", "phase": 1,
            "duration_hours": 0.0, "n_flagged": 1, "magnitude": 0.002,
            "magnitude_unit": "mean_kW_while_reversed", "corroboration": "none",
            "event_class": "ELECTRICAL_FAULT", "event_end": pd.Timestamp("2025-06-01"),
            "mean_current_a": 0.2, "mean_current_pct_cb": 0.2,
            "mean_power_factor_while_reversed": 1.0,
            "negative_power_factor_readings": 0, "max_abs_kw_while_reversed": 0.002}
    base.update(over)
    return pd.DataFrame([base])


def test_sustained_reverse_power_remains_critical(cfg):
    ev = severity.assign(_t1(duration_hours=24 * 30, n_flagged=100_000,
                             magnitude=8.0, mean_current_pct_cb=40.0,
                             corroboration="full"), cfg)
    assert ev.loc[0, "severity"] == "Critical"
    assert not bool(ev.loc[0, "t1_isolated"])


def test_a_short_but_dense_reversal_is_not_treated_as_isolated(cfg):
    """Hundreds of readings inside one day is a reversal, not an isolated blip."""
    ev = severity.assign(_t1(duration_hours=20.0, n_flagged=280, magnitude=6.0,
                             mean_current_pct_cb=30.0, corroboration="full"), cfg)
    assert not bool(ev.loc[0, "t1_isolated"])
    assert ev.loc[0, "severity"] == "Critical"


def test_isolated_reverse_power_reaches_critical_on_magnitude_load_and_corroboration(cfg):
    ev = severity.assign(_t1(magnitude=0.6, mean_current_pct_cb=8.4,
                             mean_power_factor_while_reversed=-0.45,
                             negative_power_factor_readings=1,
                             corroboration="full"), cfg)
    assert bool(ev.loc[0, "t1_isolated"])
    assert ev.loc[0, "severity"] == "Critical"


def test_isolated_reverse_power_without_corroboration_is_not_critical(cfg):
    ev = severity.assign(_t1(magnitude=0.6, mean_current_pct_cb=8.4,
                             corroboration="none"), cfg)
    assert ev.loc[0, "severity"] != "Critical"


def test_isolated_reverse_power_at_trivial_load_is_not_critical(cfg):
    """Real magnitude but almost no current: it cannot be a meaningful reversal."""
    ev = severity.assign(_t1(magnitude=0.6, mean_current_pct_cb=0.2,
                             corroboration="full"), cfg)
    assert ev.loc[0, "severity"] != "Critical"


def test_isolated_tiny_uncorroborated_blip_is_capped_at_review_required(cfg):
    ev = severity.assign(_t1(), cfg)
    assert ev.loc[0, "severity"] == "Review Required"
    assert bool(ev.loc[0, "t1_isolated"])


def test_a_tiny_blip_is_still_emitted_not_suppressed(cfg):
    """Severity changed; the detector did not. The event must still exist."""
    assert len(severity.assign(_t1(), cfg)) == 1


def test_t1_evidence_fields_survive_severity_assignment(cfg):
    ev = severity.assign(_t1(), cfg)
    for col in ("mean_current_a", "mean_current_pct_cb",
                "mean_power_factor_while_reversed", "negative_power_factor_readings",
                "magnitude"):
        assert col in ev.columns and ev.loc[0, col] is not None


def test_t5_register_decrease_is_still_critical_for_a_single_reading(cfg):
    """status_kwh = 'Invalid' corroboration justifies Critical even for one reading."""
    ev = severity.assign(_events(family="T5", detector="register_decrease",
                                 duration_hours=0.0, n_flagged=1,
                                 corroboration="full",
                                 concurrent_status="Invalid"), cfg)
    assert ev.loc[0, "severity"] == "Critical"


def test_t5_stuck_register_is_still_critical_for_a_single_day(cfg):
    ev = severity.assign(_events(family="T5", detector="stuck_register",
                                 duration_hours=24.0, n_flagged=1), cfg)
    assert ev.loc[0, "severity"] == "Critical"


# ------------------------------------------------------------------ blip regressions

@pytest.mark.parametrize("meter, phase, date", [
    ("ZN.1-PB.2", 1, "2025-05-17"),
    ("ZN.5-PB", 1, "2026-07-05"),
])
def test_known_tiny_blips_are_visible_but_never_critical(meter, phase, date):
    """Regression: both are about two watts at 0.2 A with PF +1.0 and nothing
    corroborating them. They must stay in the review output and must not be Critical
    merely because kW < 0."""
    events = pd.read_parquet(_latest_run() / "anomaly_events.parquet")
    t1 = events[events["family"].eq("T1") & events["detector"].eq("reverse_power")]
    blip = t1[t1["short_label"].eq(meter) & t1["phase"].eq(phase)
              & (pd.to_datetime(t1["event_start"]).dt.normalize() == pd.Timestamp(date))]
    assert len(blip) == 1, f"{meter} P{phase} {date} vanished from the review output"
    assert blip.iloc[0]["severity"] != "Critical"
    assert bool(blip.iloc[0]["t1_isolated"])
    for col in ("mean_current_a", "mean_current_pct_cb",
                "mean_power_factor_while_reversed", "negative_power_factor_readings"):
        assert pd.notna(blip.iloc[0][col]), f"{col} missing as evidence"


def test_blips_appear_in_the_human_readable_review_csv():
    review = pd.read_csv(_latest_run() / "anomaly_review_raw.csv",
                         parse_dates=["event_start"])
    for meter, date in (("ZN.1-PB.2", "2025-05-17"), ("ZN.5-PB", "2026-07-05")):
        rows = review[review["short_label"].eq(meter)
                      & (review["event_start"].dt.normalize() == pd.Timestamp(date))]
        assert len(rows) >= 1
        assert (rows["severity"] != "Critical").all()


def test_zn16_repair_lag_matches_the_accepted_historical_result(cfg):
    """Detector parameters are frozen; lambda was not tuned to shorten this."""
    acceptance = pd.read_csv(_latest_run() / "acceptance_results.csv")
    row = acceptance[acceptance["criterion"].str.contains("historical result", na=False)]
    assert len(row) == 1
    assert row.iloc[0]["result"] == "PASS"
    assert int(row.iloc[0]["actual"]) == cfg["reconciliation"][
        "zn16_repair_observed_lag_days"] == 2
