"""Model 3 — tests, section 9 of the design specification v2.

Cadence normalisation, feature ranges, missing-day behaviour, Saudi-date grouping, warm-up
and the scored universe, ranking, and independence from Model 1 and Task 0A/0B.

The feature/range/cadence/date/independence tests are required to pass BEFORE any Isolation
Forest is fitted.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from model3_triage import scoring
from model3_triage.config import load_config
from model3_triage.features import (
    add_dev28, build_feature_table, mark_scorable, validate_ranges,
)

ML_WORK = Path(__file__).resolve().parent.parent
CB = 100.0

COUNT_COLUMNS = [
    "readings_reported", "n_major_issue", "n_major_problem",
    "gated_readings_phase_1", "gated_readings_phase_2", "gated_readings_phase_3",
    "n_pf_crit_gated_1", "n_pf_crit_gated_2", "n_pf_crit_gated_3",
    "n_pf_crit_ungated_1", "n_pf_crit_ungated_2", "n_pf_crit_ungated_3",
    "n_negative_total_kw", "n_negative_phase_kw",
    "n_current_without_power", "n_power_without_current",
    "n_voltage_not_acceptable", "n_frequency_not_acceptable",
]


@pytest.fixture(scope="module")
def cfg() -> dict:
    return load_config()


# Base counters at one unit of cadence. Integers, so multiplying every counter AND the
# denominator by the same integer reproduces a cadence change EXACTLY - which is what makes
# the invariance test meaningful rather than a rounding coincidence.
BASE = {
    "readings_reported": 288,
    "n_major_issue": 9, "n_major_problem": 18,
    "gated_readings_phase_1": 144, "gated_readings_phase_2": 144,
    "gated_readings_phase_3": 144,
    "n_pf_crit_gated_1": 15, "n_pf_crit_gated_2": 15, "n_pf_crit_gated_3": 15,
    "n_pf_crit_ungated_1": 87, "n_pf_crit_ungated_2": 87, "n_pf_crit_ungated_3": 87,
    "n_negative_total_kw": 12, "n_negative_phase_kw": 36,
    "n_current_without_power": 27, "n_power_without_current": 12,
    "n_voltage_not_acceptable": 0, "n_frequency_not_acceptable": 0,
}


def make_counts(n_days=40, mult=1, start="2025-03-01",
                meters=("ZN.A-PB", "ZN.B-PB")) -> pd.DataFrame:
    """Synthetic daily counters. `mult` scales every counter including the denominator,
    which is exactly what a change of reporting cadence does."""
    rows = []
    for m in meters:
        for day in pd.date_range(start, periods=n_days, freq="D"):
            row = {"energy_meter_key": f"key-{m}",
                   "meter_label": f"{m}_child__1_ch3pm",
                   "zone_name": "Zone T", "cb_max_rating_a": CB, "day_saudi": day,
                   "mean_phase_current_a": 20.0}
            row.update({k: v * int(mult) for k, v in BASE.items()})
            rows.append(row)
    return pd.DataFrame(rows)


# ------------------------------------------------------------------ cadence normalisation

def test_doubling_reporting_cadence_leaves_every_rate_identical(cfg):
    """The core contract: a rate must not move when the meter simply reports more often."""
    a = build_feature_table(make_counts(mult=1), cfg)
    b = build_feature_table(make_counts(mult=2), cfg)
    for col in cfg["features"]["bounded_rate_features"]:
        assert np.allclose(a[col], b[col], atol=1e-12), f"{col} moved with cadence"


def test_doubling_cadence_changes_only_the_reading_count(cfg):
    a = build_feature_table(make_counts(mult=1), cfg)
    b = build_feature_table(make_counts(mult=2), cfg)
    assert (b["readings_reported"] == 2 * a["readings_reported"]).all()
    # coverage_ratio divides by the facility median, which doubles too, so it is unchanged
    # when EVERY meter's cadence doubles. That is the intended behaviour.
    assert np.allclose(a["coverage_ratio"], b["coverage_ratio"], atol=1e-12)


def test_coverage_ratio_does_move_when_one_meter_diverges(cfg):
    """If only one meter changes cadence, coverage_ratio must notice."""
    counts = make_counts(mult=1)
    odd = counts["meter_label"].str.startswith("ZN.A")
    counts.loc[odd, COUNT_COLUMNS] = (counts.loc[odd, COUNT_COLUMNS] // 4).astype("int64")
    out = build_feature_table(counts, cfg)
    a = out.loc[out.meter_label.str.startswith("ZN.A"), "coverage_ratio"]
    b = out.loc[out.meter_label.str.startswith("ZN.B"), "coverage_ratio"]
    assert a.mean() < b.mean()


def test_a_raw_count_does_move_with_cadence(cfg):
    """Proves the cadence tests have teeth rather than passing vacuously."""
    a = build_feature_table(make_counts(mult=1), cfg)
    b = build_feature_table(make_counts(mult=2), cfg)
    assert not np.allclose(a["n_major_issue"], b["n_major_issue"])


# ------------------------------------------------------------------ feature ranges

def test_only_genuine_rates_are_constrained_to_the_unit_interval(cfg):
    table = add_dev28(build_feature_table(make_counts(), cfg), cfg)
    res = validate_ranges(table, cfg)
    assert res["all_bounded_rates_in_unit_interval"]
    assert res["all_fitted_values_finite"]


def test_coverage_ratio_above_one_is_allowed(cfg):
    counts = make_counts(meters=("ZN.A-PB", "ZN.B-PB", "ZN.C-PB"))
    big = counts["meter_label"].str.startswith("ZN.C")
    counts.loc[big, COUNT_COLUMNS] = (counts.loc[big, COUNT_COLUMNS] * 3).astype("int64")
    table = add_dev28(build_feature_table(counts, cfg), cfg)
    assert (table["coverage_ratio"] > 1).any()
    assert validate_ranges(table, cfg)["all_bounded_rates_in_unit_interval"]


def test_mean_load_pct_cb_above_100_is_not_clipped(cfg):
    """Clipping would erase exactly the overload condition most worth surfacing."""
    counts = make_counts()
    counts["mean_phase_current_a"] = 150.0          # 150% of a 100 A breaker
    table = add_dev28(build_feature_table(counts, cfg), cfg)
    assert np.allclose(table["mean_load_pct_cb"], 150.0)
    assert validate_ranges(table, cfg)["all_fitted_values_finite"]


def test_dev28_may_be_negative(cfg):
    counts = make_counts(n_days=60)
    late = counts["day_saudi"] >= counts["day_saudi"].min() + pd.Timedelta(days=40)
    counts.loc[late, "n_negative_total_kw"] = 0
    table = add_dev28(build_feature_table(counts, cfg), cfg)
    assert (table["negative_total_power_rate_dev28"] < 0).any()


def test_no_feature_is_winsorised_or_rescaled(cfg):
    counts = make_counts()
    counts["mean_phase_current_a"] = 250.0
    table = add_dev28(build_feature_table(counts, cfg), cfg)
    assert table["mean_load_pct_cb"].max() == pytest.approx(250.0)


def test_every_fitted_value_must_be_finite(cfg):
    table = add_dev28(build_feature_table(make_counts(), cfg), cfg)
    table.loc[0, "coverage_ratio"] = np.inf
    res = validate_ranges(table, cfg)
    assert not res["all_fitted_values_finite"]
    assert "coverage_ratio" in res["non_finite"]


# ------------------------------------------------------------------ missing days

def test_a_day_with_no_readings_produces_no_row(cfg):
    counts = make_counts(n_days=10)
    gap = counts["day_saudi"] == counts["day_saudi"].min() + pd.Timedelta(days=4)
    counts = counts.loc[~gap]
    table = build_feature_table(counts, cfg)
    assert len(table) == len(counts)
    assert (counts["day_saudi"].min() + pd.Timedelta(days=4)) not in set(table["day_saudi"])


def test_a_four_reading_day_is_retained_not_filtered(cfg):
    counts = make_counts(n_days=10)
    thin = counts.index[0]
    counts.loc[thin, COUNT_COLUMNS] = 0
    counts.loc[thin, "readings_reported"] = 4
    table = build_feature_table(counts, cfg)
    row = table.loc[table.index[0]]
    assert row["readings_reported"] == 4
    assert row["low_coverage_day"]


def test_gate_never_opening_gives_an_unambiguous_zero_pair(cfg):
    """(0.0, 0.0) means the gate never opened; (0.0, >0) means power factor was fine."""
    counts = make_counts(n_days=5)
    for k in (1, 2, 3):
        counts[f"gated_readings_phase_{k}"] = 0
        counts[f"n_pf_crit_gated_{k}"] = 0
    table = build_feature_table(counts, cfg)
    for k in (1, 2, 3):
        assert (table[f"pf_critical_rate_gated_{k}"] == 0).all()
        assert (table[f"pf_gate_open_rate_{k}"] == 0).all()
        assert table[f"pf_critical_rate_gated_{k}"].notna().all()


def test_zero_denominator_never_produces_nan(cfg):
    counts = make_counts(n_days=3)
    counts[COUNT_COLUMNS] = 0
    counts["mean_phase_current_a"] = 0.0
    table = add_dev28(build_feature_table(counts, cfg), cfg)
    fitted = cfg["features"]["tier1"] + cfg["features"]["tier2"]
    assert np.isfinite(table[fitted].to_numpy(dtype="float64")).all()


# ------------------------------------------------------------------ Saudi dates

def test_saudi_day_boundary_is_21_00_utc():
    off = pd.Timedelta(hours=3)
    assert (pd.Timestamp("2026-03-01 20:59:59") + off).date() == pd.Timestamp(
        "2026-03-01").date()
    assert (pd.Timestamp("2026-03-01 21:00:00") + off).date() == pd.Timestamp(
        "2026-03-02").date()


def test_every_saudi_day_spans_86400_seconds():
    days = pd.date_range("2024-12-09", "2026-07-11", freq="D")
    closes = days + pd.Timedelta(hours=21)
    assert set(np.diff(closes) / np.timedelta64(1, "s")) == {86_400.0}


def test_saudi_date_is_derived_from_utc_not_from_a_local_column(cfg):
    from model3_triage.features import DAILY_SQL
    assert "make_interval(hours => %(off)s)" in DAILY_SQL
    assert "reading_timestamp_saudi" not in DAILY_SQL
    assert cfg["saudi"]["utc_offset_hours"] == 3


# ------------------------------------------------------------------ warm-up

def test_min_train_dates_counts_distinct_dates_not_meter_day_rows(cfg):
    """62 rows across 2 calendar dates must NOT be scorable."""
    rows = []
    for day in pd.date_range("2025-01-01", periods=2, freq="D"):
        for i in range(31):
            rows.append({"meter_label": f"M{i}", "day_saudi": day})
    rows.append({"meter_label": "M0", "day_saudi": pd.Timestamp("2025-01-10")})
    d = pd.DataFrame(rows)
    out = mark_scorable(d, cfg)
    assert len(d) == 63
    assert not out["scorable"].any()


def test_a_date_becomes_scorable_only_after_enough_distinct_prior_dates(cfg):
    days = pd.date_range("2025-01-01", periods=100, freq="D")
    d = pd.DataFrame({"meter_label": "M0", "day_saudi": days})
    out = mark_scorable(d, cfg)
    n_min = int(cfg["isolation_forest"]["min_train_dates"])
    first = out.loc[out["scorable"], "day_saudi"].min()
    assert first == days[n_min]
    assert int((~out["scorable"]).sum()) == n_min


# ------------------------------------------------------------------ ranking

def _score_frame(n_days=6, n_meters=5, seed=0) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    rows = []
    for day in pd.date_range("2025-06-01", periods=n_days, freq="D"):
        raw = rng.normal(0.5, 0.05, n_meters)
        train = np.sort(rng.normal(0.5, 0.05, 500))
        for i, r in enumerate(raw):
            rows.append({
                "meter_label": f"M{i}", "day_saudi": day, "raw_score": float(r),
                "window_anomaly_pct": float(scoring.window_percentile(
                    np.array([r]), train)[0]),
                "window_anomaly_z": float((r - train.mean()) / train.std(ddof=1)),
            })
    d = pd.DataFrame(rows)
    d["daily_rank_pct"] = d.groupby("day_saudi")["raw_score"].rank(
        pct=True, method="max")
    return d


def test_exactly_one_meter_per_day_reaches_daily_rank_one():
    """Demonstrates why daily_rank_pct cannot rank globally."""
    d = _score_frame()
    per_day = d[d["daily_rank_pct"] == 1.0].groupby("day_saudi").size()
    assert (per_day == 1).all()
    assert len(per_day) == d["day_saudi"].nunique()


def test_global_top_n_is_not_the_set_of_daily_winners(cfg):
    """A global Top-N must be chosen on window_anomaly_pct, not on daily rank."""
    d = _score_frame(n_days=10, n_meters=6, seed=3)
    n = 10
    winners = set(map(tuple, d[d["daily_rank_pct"] == 1.0][
        ["meter_label", "day_saudi"]].to_numpy()))
    top = set(map(tuple, scoring.top_n(scoring.order(d, cfg), n)[
        ["meter_label", "day_saudi"]].to_numpy()))
    assert len(winners) == 10
    assert top != winners


def test_global_top_n_is_not_determined_by_daily_rank_ties(cfg):
    """With 50 days each having a rank-1.0 meter, ordering by daily rank alone is arbitrary;
    the real Top-50 must be ordered by score."""
    d = _score_frame(n_days=50, n_meters=4, seed=11)
    ordered = scoring.order(d, cfg)
    top = scoring.top_n(ordered, 50)
    assert top["daily_rank_pct"].nunique() > 1, "top-50 is not just the daily winners"
    pct = top["window_anomaly_pct"].to_numpy()
    assert (np.diff(pct) <= 1e-12).all(), "top-N is not sorted by the primary score"


def test_window_percentile_uses_a_less_than_or_equal_convention():
    train = np.array([0.1, 0.2, 0.3, 0.4])
    assert scoring.window_percentile(np.array([0.4]), train)[0] == pytest.approx(1.0)
    assert scoring.window_percentile(np.array([0.25]), train)[0] == pytest.approx(0.5)
    assert scoring.window_percentile(np.array([0.05]), train)[0] == pytest.approx(0.0)


def test_window_percentile_is_comparable_across_two_different_forests():
    """The same relative position in two different training distributions gives the same
    percentile. That is what makes the score cross-refit comparable."""
    a = np.sort(np.linspace(0.0, 1.0, 500))
    b = np.sort(np.linspace(10.0, 20.0, 500))
    assert scoring.window_percentile(np.array([0.5]), a)[0] == pytest.approx(
        scoring.window_percentile(np.array([15.0]), b)[0], abs=2e-3)


def test_window_anomaly_z_breaks_ceiling_ties(cfg):
    """Two meters saturated at percentile 1.0 must still order deterministically."""
    d = pd.DataFrame({
        "meter_label": ["M1", "M2"], "day_saudi": [pd.Timestamp("2025-06-01")] * 2,
        "raw_score": [0.9, 0.7], "window_anomaly_pct": [1.0, 1.0],
        "window_anomaly_z": [4.0, 2.0], "daily_rank_pct": [1.0, 0.5]})
    ordered = scoring.order(d, cfg)
    assert ordered["meter_label"].tolist() == ["M1", "M2"]


def test_ordering_is_deterministic_across_repeated_calls(cfg):
    d = _score_frame(n_days=12, n_meters=5, seed=5)
    first = scoring.order(d, cfg)
    second = scoring.order(d.sample(frac=1.0, random_state=9), cfg)
    pd.testing.assert_frame_equal(
        first.reset_index(drop=True), second.reset_index(drop=True))


def test_an_extreme_outlier_ranks_first_catching_the_sklearn_sign_convention():
    from sklearn.ensemble import IsolationForest
    rng = np.random.default_rng(1)
    X = rng.normal(0, 1, (300, 3))
    X = np.vstack([X, np.array([[50.0, 50.0, 50.0]])])
    f = IsolationForest(n_estimators=100, random_state=0).fit(X)
    raw = -f.score_samples(X)
    assert int(np.argmax(raw)) == len(X) - 1


def test_per_meter_top_gives_each_meter_its_own_entries(cfg):
    d = scoring.order(_score_frame(n_days=20, n_meters=4, seed=7), cfg)
    out = scoring.per_meter_top(d, 2)
    assert out.groupby("meter_label").size().eq(2).all()


# ------------------------------------------------------------------ independence

def _latest(pattern: str) -> Path:
    """Newest run directory matching a glob, passed through verbatim so a caller can
    exclude design directories (model3_2* matches runs, not model3_design_*)."""
    runs = sorted((ML_WORK / "outputs").glob(pattern if "*" in pattern
                                             else f"{pattern}_*"))
    if not runs:
        pytest.skip(f"no directory matching {pattern!r} under outputs/")
    return runs[-1]


def test_feature_table_contains_no_model1_column():
    table = pd.read_parquet(_latest("model3_features_*") / "model3_feature_table.parquet")
    leaked = [c for c in table.columns if c.lower().startswith(("m1_", "model1"))]
    assert leaked == []


def test_feature_module_never_reads_model1_or_task0():
    src = (ML_WORK / "src" / "model3_triage" / "features.py").read_text(encoding="utf-8")
    for forbidden in ("model1", "task0a", "task0b", "anomaly_events",
                      "daily_consumption_profile"):
        assert forbidden not in src.lower()


def test_scoring_module_never_reads_model1():
    src = (ML_WORK / "src" / "model3_triage" / "scoring.py").read_text(encoding="utf-8")
    assert "anomaly_events" not in src.lower()
    assert "read_parquet" not in src.lower()


def test_no_register_derived_column_is_used(cfg):
    from model3_triage.features import DAILY_SQL
    assert "active_energy_cumulative_kwh" not in DAILY_SQL
    assert not any("kwh" in c.lower() for c in cfg["features"]["tier1"])


def test_feature_table_reconciles_to_the_declared_scope(cfg):
    run = _latest("model3_features_*")
    table = pd.read_parquet(run / "model3_feature_table.parquet")
    s = cfg["scope"]
    assert len(table) == s["expected_meter_days"]
    assert int(table["scorable"].sum()) == s["expected_scored_meter_days"]
    assert table["meter_label"].nunique() == s["meters"]
    assert int(table["readings_reported"].sum()) == s["readings"]
    assert table["day_saudi"].nunique() == s["expected_distinct_dates"]
    assert str(table.loc[table["scorable"], "day_saudi"].min().date()) == \
        s["expected_first_scorable_date"]


def test_feature_run_metadata_records_read_only_and_claims_no_precision():
    meta = json.loads((_latest("model3_features_*") / "run_metadata.json").read_text(
        encoding="utf-8"))
    assert meta["connection"]["transaction_read_only"] == "on"
    assert meta["connection"]["transaction_isolation"] == "repeatable read"
    assert meta["reads_model1"] is False
    assert meta["reads_task0a_or_0b"] is False
    assert "NOT CLAIMED" in meta["precision_and_recall"]
    assert meta["models_fitted"] == []


def test_contamination_cannot_be_set_to_a_numeric_prevalence(cfg, tmp_path):
    """The config refuses a numeric contamination, so no number in it can be misread as a
    fault-prevalence estimate."""
    import yaml
    from model3_triage.config import load_config as _load
    bad = dict(cfg)
    bad["isolation_forest"] = dict(cfg["isolation_forest"], contamination=0.02)
    p = tmp_path / "bad.yaml"
    p.write_text(yaml.safe_dump(bad), encoding="utf-8")
    with pytest.raises(ValueError, match="contamination"):
        _load(str(p))


def test_crosscheck_contract_requires_same_meter_same_day(cfg, tmp_path):
    import yaml
    from model3_triage.config import load_config as _load
    bad = dict(cfg)
    bad["crosscheck"] = dict(cfg["crosscheck"],
                             explains_requires=dict(cfg["crosscheck"]["explains_requires"],
                                                    same_meter_same_day=False))
    p = tmp_path / "bad2.yaml"
    p.write_text(yaml.safe_dump(bad), encoding="utf-8")
    with pytest.raises(ValueError, match="per meter-day"):
        _load(str(p))


# ------------------------------------------------------------------ Model 1 cross-check

from model3_triage import crosscheck as cc_mod  # noqa: E402


def _events(**over) -> pd.DataFrame:
    base = {"meter_label": "ZN.A-PB_child__1_ch3pm", "family": "T1",
            "detector": "reverse_power", "severity": "Critical",
            "event_class": "ELECTRICAL_FAULT", "commissioning": False,
            "event_start": pd.Timestamp("2025-06-10 03:00"),
            "event_end": pd.Timestamp("2025-06-10 21:00")}
    base.update(over)
    return pd.DataFrame([base])


def _scores(meters=("ZN.A-PB", "ZN.B-PB"), day="2025-06-10") -> pd.DataFrame:
    return pd.DataFrame([{
        "meter_label": f"{m}_child__1_ch3pm", "short_label": m,
        "day_saudi": pd.Timestamp(day), "is_zone13": m.startswith("ZN.13"),
        "window_anomaly_pct": 0.99 - i * 0.01, "window_anomaly_z": 3.0 - i,
    } for i, m in enumerate(meters)])


def test_merge_flag_returns_a_real_bool_so_negation_is_logical(cfg):
    """Regression: fillna(False) alone leaves object dtype, and ~ on an object Series of
    Python bools does INTEGER bitwise negation (True -> -2), not logical NOT."""
    out = cc_mod.build_crosscheck(_scores(), _events(), cfg)
    assert out["m1_explains"].dtype == bool
    assert (~out["m1_explains"]).tolist() == [False, True]


def test_an_event_on_another_meter_does_not_explain_this_one(cfg):
    """'Explained' is judged per meter-day, never facility-wide."""
    out = cc_mod.build_crosscheck(_scores(), _events(), cfg)
    assert out.loc[out.short_label.eq("ZN.A-PB"), "m1_explains"].item() is np.True_ or \
        bool(out.loc[out.short_label.eq("ZN.A-PB"), "m1_explains"].item())
    assert not bool(out.loc[out.short_label.eq("ZN.B-PB"), "m1_explains"].item())


def test_an_event_on_another_day_does_not_explain_this_day(cfg):
    out = cc_mod.build_crosscheck(
        _scores(day="2025-06-11"), _events(), cfg)
    assert not out["m1_explains"].any()


def test_a_commissioning_event_never_counts_as_an_explanation(cfg):
    out = cc_mod.build_crosscheck(
        _scores(), _events(commissioning=True, event_class="COMMISSIONING"), cfg)
    assert not out["m1_explains"].any()
    assert out["m1_context_commissioning"].any(), "context must still be visible"


def test_a_data_availability_event_never_counts_as_an_explanation(cfg):
    """A telemetry outage says why data is thin, not why behaviour was unusual."""
    out = cc_mod.build_crosscheck(
        _scores(), _events(event_class="DATA_AVAILABILITY", family="T4",
                           detector="data_availability"), cfg)
    assert not out["m1_explains"].any()
    assert out["m1_context_data_availability"].any()


def test_an_electrical_fault_marked_commissioning_does_not_explain(cfg):
    out = cc_mod.build_crosscheck(_scores(), _events(commissioning=True), cfg)
    assert not out["m1_explains"].any()


def test_list_c_holds_exactly_the_unexplained_top_entries(cfg):
    out = cc_mod.build_crosscheck(_scores(), _events(), cfg)
    c = cc_mod.list_c(out, 2)
    assert len(c) == 1
    assert c.iloc[0]["short_label"] == "ZN.B-PB"


def test_base_rates_use_the_passed_universe_only(cfg):
    out = cc_mod.build_crosscheck(_scores(), _events(), cfg)
    rates = cc_mod.base_rates(out, cfg)
    assert (rates["scored_universe"] == 2).all()
    assert rates.loc[rates.population.eq("any_family"), "base_rate_pct"].item() == 50.0


def test_zone13_is_flagged_as_outside_the_register_family_scope(cfg):
    out = cc_mod.build_crosscheck(_scores(meters=("ZN.13-PB.1", "ZN.A-PB")), _events(), cfg)
    z = out.loc[out.short_label.eq("ZN.13-PB.1")]
    assert not bool(z["m1_register_family_in_scope"].item())


def test_crosscheck_artifacts_exist_and_reconcile(cfg):
    run = _latest("model3_2*")
    cc = pd.read_parquet(run / "model3_model1_crosscheck.parquet")
    rates = pd.read_csv(run / "model3_base_rates.csv")
    assert len(cc) == cfg["scope"]["expected_scored_meter_days"]
    assert (rates["scored_universe"] == len(cc)).all()
    # base rates must be computed on the scored universe, not on all meter-days
    assert rates.loc[rates.population.eq("any_family"), "base_rate_pct"].item() < 59.5


def test_scores_artifact_carries_no_model1_column():
    scores = pd.read_parquet(_latest("model3_2*") / "model3_scores.parquet")
    assert [c for c in scores.columns if c.lower().startswith(("m1_", "model1"))] == []


def test_scoring_run_metadata_records_determinism_and_no_model1_read():
    meta = json.loads((_latest("model3_2*") / "run_metadata.json").read_text(
        encoding="utf-8"))
    assert meta["reads_model1"] is False
    assert meta["deterministic_rerun_identical"] is True
    assert meta["deterministic_rerun_max_raw_score_delta"] == 0.0
    assert "NOT CLAIMED" in meta["precision_and_recall"]
    assert meta["canonical_feature_set"] == "tier1"


# ------------------------------------------------------------------ permutation nulls

def test_permutation_p_can_never_be_zero():
    """(exceedances + 1) / (B + 1): 10,000 draws cannot claim more certainty than they have."""
    assert cc_mod.permutation_p(0, 10_000) == pytest.approx(1 / 10_001)
    assert cc_mod.permutation_p(0, 10_000) > 0
    assert cc_mod.permutation_p(10_000, 10_000) == pytest.approx(1.0)
    assert cc_mod.permutation_p(500, 10_000) == pytest.approx(501 / 10_001)


def test_observed_run_lengths_counts_consecutive_dates_within_a_meter():
    top = pd.DataFrame({
        "meter_label": ["A"] * 4 + ["B"] * 2,
        "day_saudi": pd.to_datetime(
            ["2025-01-01", "2025-01-02", "2025-01-03", "2025-01-10",
             "2025-02-01", "2025-03-01"]),
    })
    runs = sorted(cc_mod.observed_run_lengths(top).tolist())
    assert runs == [1, 1, 1, 3]


def test_block_positions_are_contiguous_when_block_exceeds_one():
    rng = np.random.default_rng(0)
    idx = cc_mod._block_positions(100, 6, block=3, rng=rng)
    assert len(idx) == 6
    # two runs of three consecutive positions
    assert (np.diff(idx[:3]) == 1).all()
    assert (np.diff(idx[3:]) == 1).all()


def test_block_positions_with_block_one_draws_without_replacement():
    rng = np.random.default_rng(0)
    idx = cc_mod._block_positions(50, 10, block=1, rng=rng)
    assert len(idx) == 10 and len(set(idx.tolist())) == 10


def test_meter_preserving_null_keeps_the_meter_composition_fixed():
    """The whole point: re-draw the DAYS, never the meters."""
    rows = []
    for m in ("A", "B"):
        for d in pd.date_range("2025-01-01", periods=40, freq="D"):
            rows.append({"meter_label": m, "day_saudi": d,
                         "flag": (m == "A")})
    universe = pd.DataFrame(rows)
    top = universe[universe.meter_label.eq("A")].head(9)      # 9 from A, 0 from B
    draws = cc_mod.meter_preserving_null(
        universe, top, ["flag"], block=1, n_draws=50,
        rng=np.random.default_rng(0))
    # every draw comes from meter A, whose flag is always True
    assert np.allclose(draws, 1.0)


def test_meter_preserving_null_differs_from_the_global_null_when_meters_differ():
    """A facility where one meter is always flagged and another never is: the global null
    averages the two, the meter-preserving null does not."""
    rows = []
    for m, flag in (("A", True), ("B", False)):
        for d in pd.date_range("2025-01-01", periods=40, freq="D"):
            rows.append({"meter_label": m, "day_saudi": d, "flag": flag})
    universe = pd.DataFrame(rows)
    top = universe[universe.meter_label.eq("A")].head(10)
    g = cc_mod.global_null(universe, ["flag"], 10, 200, np.random.default_rng(1))
    mp = cc_mod.meter_preserving_null(universe, top, ["flag"], 1, 200,
                                      np.random.default_rng(1))
    assert abs(float(g.mean()) - 0.5) < 0.15
    assert float(mp.mean()) == pytest.approx(1.0)


def test_null_correction_left_the_frozen_scores_untouched():
    meta = json.loads((_latest("model3_2*") / "run_metadata_null_correction.json"
                       ).read_text(encoding="utf-8"))
    assert meta["frozen_artifacts_unchanged"] is True
    assert meta["scores_and_rankings_altered"] is False
    assert meta["p_value_formula"] == "(exceedances + 1) / (B + 1)"


def test_corrected_null_artifact_reports_all_three_nulls():
    t = pd.read_csv(_latest("model3_2*") / "model3_overlap_lift_corrected_null.csv")
    for col in ("global_p", "meter_preserving_iid_p", "meter_preserving_block_p"):
        assert col in t.columns
        assert (t[col] > 0).all(), "a permutation p-value of exactly 0 is not reportable"
    assert set(t["n"]) == {25, 50, 100}
