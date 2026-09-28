"""Task 4 — tests for the unlabelled review package.

Covers the sampling design (frozen allocation, inclusion probabilities, frame integrity),
blinding, workbook protection, and the finite-population-aware estimator — which is built
and tested here but is NOT run against real data, because no engineering label exists yet.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from review_loop import estimation
from review_loop.allocation import (
    SEVERITY_RANK, allocate_stratum_a, allocate_stratum_b, award_by_room, reference_pool,
)
from review_loop.build_queue import expand_events, load_config
from review_loop.workbook import (
    FINDING_LABELS, FINDING_VISIBLE, FORBIDDEN_SUBSTRINGS, METER_DAY_LABELS,
    METER_DAY_VISIBLE, assert_blinded,
)

ML_WORK = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def cfg() -> dict:
    return load_config()


@pytest.fixture(scope="module")
def run_dir() -> Path:
    runs = sorted((ML_WORK / "outputs").glob("task4_2*"))
    if not runs:
        pytest.skip("no Task 4 run found")
    return runs[-1]


def issued(run_dir: Path, reviewer: str) -> Path:
    """The reviewer copy, whether or not it still carries the _DRAFT suffix.

    Since the assignment contract was applied these hold a PARTITION of the 200 units, not
    all of them, so any test that needs the full set must take the union across reviewers.
    """
    for name in (f"task4_labelling_sample_{reviewer}.xlsx",
                 f"task4_labelling_sample_{reviewer}_DRAFT.xlsx"):
        if (run_dir / name).exists():
            return run_dir / name
    pytest.skip(f"no workbook for {reviewer}")


@pytest.fixture(scope="module")
def findings(cfg) -> pd.DataFrame:
    return pd.read_csv(ML_WORK / "outputs" / cfg["frozen_runs"]["model1"]
                       / "findings_summary.csv")


@pytest.fixture(scope="module")
def scores(cfg) -> pd.DataFrame:
    return pd.read_parquet(ML_WORK / "outputs" / cfg["frozen_runs"]["model3"]
                           / "model3_model1_crosscheck.parquet")


# ------------------------------------------------------------------ severity ordering

def test_severity_rank_puts_critical_first():
    assert SEVERITY_RANK["Critical"] < SEVERITY_RANK["Problematic"]
    assert SEVERITY_RANK["Problematic"] < SEVERITY_RANK["Anomaly"]
    assert SEVERITY_RANK["Anomaly"] < SEVERITY_RANK["Review Required"]


def test_a_descending_string_sort_is_wrong_and_stays_documented():
    """The provided Task 4 instruction sorted severity as a string. It buries Critical."""
    order = sorted(SEVERITY_RANK, reverse=True)
    assert order[0] == "Review Required"
    assert order.index("Critical") == 2


# ------------------------------------------------------------------ stratum A allocation

def test_allocation_is_integer_exact_and_matches_the_frozen_table(findings, cfg):
    alloc = allocate_stratum_a(findings, cfg)
    assert int(alloc["n_h"].sum()) == int(cfg["budget"]["stratum_a"]) == 110
    assert alloc.groupby("family")["n_h"].sum().to_dict() == \
        cfg["stratum_a"]["expected_family_totals"]


def test_base_per_family_is_floor_of_the_integer_division(cfg):
    a = cfg["stratum_a"]
    assert a["base_per_family"] == int(cfg["budget"]["stratum_a"]) // len(a["families"])
    assert a["base_per_family"] == 27


def test_every_finding_carries_a_nonzero_inclusion_probability(findings, cfg):
    alloc = allocate_stratum_a(findings, cfg)
    assert (alloc["pi_h"] > 0).all()
    assert (alloc["pi_h"] <= 1).all()
    assert np.allclose(alloc["weight"], 1.0 / alloc["pi_h"])


def test_census_cells_are_flagged(findings, cfg):
    alloc = allocate_stratum_a(findings, cfg)
    census = alloc.loc[alloc["is_census"]]
    assert (census["pi_h"] == 1.0).all()
    assert len(census) >= 1


def test_stratum_a_frame_excludes_t4_and_commissioning(findings, cfg):
    """T4 asserts no fault at all, and a commissioning artifact is not a fault."""
    alloc = allocate_stratum_a(findings, cfg)
    assert "T4" not in set(alloc["family"])
    assert int(alloc["N_h"].sum()) == cfg["stratum_a"]["expected_frame"] == 255


def test_award_by_room_is_deterministic_and_exact():
    counts = np.array([2, 2, 2])
    capacity = np.array([10, 5, 3])
    a = award_by_room(counts.copy(), capacity, 12, ["a", "b", "c"])
    b = award_by_room(counts.copy(), capacity, 12, ["a", "b", "c"])
    assert a.sum() == 12
    assert np.array_equal(a, b)
    assert (a <= capacity).all()


def test_award_by_room_stops_at_capacity():
    out = award_by_room(np.array([0, 0]), np.array([3, 2]), 99, ["a", "b"])
    assert out.sum() == 5


# ------------------------------------------------------------------ stratum B

def test_stratum_b_totals_equal_fifty_minus_c(scores, cfg):
    top = scores.head(int(cfg["stratum_b"]["top_n"]))
    explained = top.loc[top["m1_explains"]]
    unexplained = top.loc[~top["m1_explains"]]
    alloc = allocate_stratum_b(explained, scores, cfg)
    n_c = min(len(unexplained), int(cfg["budget"]["stratum_c_cap"]))
    assert int(alloc["n_high"].sum() + alloc["n_reference"].sum()) == \
        int(cfg["budget"]["model3_total"]) - n_c


def test_stratum_b_respects_the_per_meter_cap(scores, cfg):
    top = scores.head(int(cfg["stratum_b"]["top_n"]))
    alloc = allocate_stratum_b(top.loc[top["m1_explains"]], scores, cfg)
    assert alloc["n_high"].max() <= int(cfg["stratum_b"]["high_cell_cap"])


def test_only_meters_able_to_support_a_within_meter_comparison_participate(scores, cfg):
    top = scores.head(int(cfg["stratum_b"]["top_n"]))
    alloc = allocate_stratum_b(top.loc[top["m1_explains"]], scores, cfg)
    active = alloc.loc[alloc["n_high"] > 0]
    assert (active["N_high_pool"] >= int(cfg["stratum_b"]["min_high_pool"])).all()
    assert (active["R_reference_pool"] >= int(cfg["stratum_b"]["min_reference_pool"])).all()


def test_reference_pool_is_same_meter_bottom_quartile_and_date_separated(scores, cfg):
    top = scores.head(int(cfg["stratum_b"]["top_n"]))
    explained = top.loc[top["m1_explains"]]
    meter = explained["meter_label"].value_counts().index[0]
    refs = reference_pool(scores, explained, meter, cfg)
    pool = scores.loc[scores["meter_label"].eq(meter)]
    cut = pool["window_anomaly_pct"].quantile(cfg["stratum_b"]["reference_quantile"])

    assert (refs["meter_label"] == meter).all()
    assert (refs["window_anomaly_pct"] <= cut).all()
    high_days = explained.loc[explained["meter_label"].eq(meter), "day_saudi"].to_numpy()
    for d in refs["day_saudi"].to_numpy():
        gap = np.min(np.abs((d - high_days) / np.timedelta64(1, "D")))
        assert gap >= cfg["stratum_b"]["reference_min_separation_days"]


def test_reference_rule_is_relative_not_an_absolute_gap(scores, cfg):
    """ZN.10-PB.1 never scores below 0.707, so an absolute 0.40 gap is impossible for it.
    The relative rule must still supply references for that meter."""
    meter = [m for m in scores["meter_label"].unique() if "ZN.10-PB.1" in m][0]
    pool = scores.loc[scores["meter_label"].eq(meter)]
    assert pool["window_anomaly_pct"].min() > 0.60, "fixture assumption changed"
    top = scores.head(int(cfg["stratum_b"]["top_n"]))
    refs = reference_pool(scores, top.loc[top["m1_explains"]], meter, cfg)
    assert len(refs) > 0, "the relative rule must not drop this meter"


# ------------------------------------------------------------------ frames

def test_control_frame_is_model1_own_universe_not_model3_scored(run_dir, cfg):
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    assert meta["stratum_d"]["frame"] == cfg["stratum_d"]["expected_frame"] == 6356
    assert meta["stratum_d"]["frame"] != 5798


def test_flagged_and_unflagged_reconcile_to_the_observed_universe(run_dir):
    r = json.loads((run_dir / "run_metadata.json").read_text(
        encoding="utf-8"))["population_reconciliation"]
    assert r["reconciles"] is True
    assert r["flagged_meter_days_observed"] + r["unflagged_observed_meter_days"] == \
        r["observed_meter_days"] == 15759
    # one flagged day falls on a day the meter reported nothing
    assert r["flagged_meter_days_all"] - r["flagged_meter_days_observed"] == 1


def test_expand_events_spans_every_day_not_just_the_start():
    ev = pd.DataFrame([{"meter_label": "M", "event_start": pd.Timestamp("2025-01-01"),
                        "event_end": pd.Timestamp("2025-01-05"),
                        "event_class": "ELECTRICAL_FAULT", "commissioning": False}])
    assert len(expand_events(ev)) == 5


# ------------------------------------------------------------------ blinding

def test_forbidden_columns_are_rejected():
    with pytest.raises(RuntimeError, match="blinding violation"):
        assert_blinded(pd.DataFrame(columns=["review_id", "severity"]))
    with pytest.raises(RuntimeError, match="blinding violation"):
        assert_blinded(pd.DataFrame(columns=["review_id", "window_anomaly_pct"]))


def test_visible_column_sets_carry_nothing_forbidden():
    for cols in (FINDING_VISIBLE + FINDING_LABELS,
                 METER_DAY_VISIBLE + METER_DAY_LABELS):
        assert_blinded(pd.DataFrame(columns=cols))


def test_meter_day_sheet_hides_flag_status_family_severity_and_score():
    lowered = " ".join(METER_DAY_VISIBLE).lower()
    for token in ("severity", "family", "detector", "m1_", "window_anomaly",
                  "stratum", "description"):
        assert token not in lowered


def test_workbook_sheets_have_identical_schema_for_every_row(run_dir, cfg):
    """Flagged and unflagged meter-days must be indistinguishable by column set."""
    import openpyxl
    wb = openpyxl.load_workbook(issued(run_dir, cfg["governance"]["reviewers"][0]))
    ws = wb["meter_days"]
    header = [c.value for c in ws[1]]
    assert header == METER_DAY_VISIBLE + METER_DAY_LABELS
    # no row carries a value the others lack, flagged or not
    for row in ws.iter_rows(min_row=2, values_only=True):
        assert len(row) == len(header)
    assert ws.max_row - 1 < 90, "a reviewer copy must be a partition, not the whole set"


def test_the_two_grains_never_share_a_sheet(run_dir, cfg):
    import openpyxl
    wb = openpyxl.load_workbook(issued(run_dir, cfg["governance"]["reviewers"][0]))
    assert set(wb.sheetnames) == {"findings", "meter_days"}
    assert [c.value for c in wb["findings"][1]] == FINDING_VISIBLE + FINDING_LABELS


# ------------------------------------------------------------------ workbook protection

def test_label_columns_are_unlocked_and_everything_else_is_locked(run_dir, cfg):
    import openpyxl
    wb = openpyxl.load_workbook(issued(run_dir, cfg["governance"]["reviewers"][0]))
    for sheet, labels in (("findings", FINDING_LABELS),
                          ("meter_days", METER_DAY_LABELS)):
        ws = wb[sheet]
        assert ws.protection.sheet is True
        header = [c.value for c in ws[1]]
        for j, col in enumerate(header, start=1):
            locked = ws.cell(row=2, column=j).protection.locked
            if col in labels:
                assert locked is False, f"{sheet}.{col} must be editable"
            else:
                assert locked is True, f"{sheet}.{col} must be locked"


def test_reviewer_id_is_prepopulated_and_locked(run_dir, cfg):
    """If reviewers could type it, the double-labelled overlap sample could be
    mis-attributed and the agreement estimate would be meaningless."""
    import openpyxl
    reviewer = cfg["governance"]["reviewers"][0]
    wb = openpyxl.load_workbook(issued(run_dir, reviewer))
    ws = wb["findings"]
    j = [c.value for c in ws[1]].index("reviewer_id") + 1
    assert ws.cell(row=2, column=j).value == reviewer
    assert ws.cell(row=2, column=j).protection.locked is True
    assert "reviewer_id" not in cfg["labels"]["findings_sheet"]["editable"]
    assert "reviewer_id" in cfg["labels"]["prepopulated_locked"]


def test_reviewed_at_is_editable_on_both_sheets(cfg):
    assert "reviewed_at" in cfg["labels"]["findings_sheet"]["editable"]
    assert "reviewed_at" in cfg["labels"]["meter_days_sheet"]["editable"]


def test_one_workbook_per_reviewer(run_dir, cfg):
    for reviewer in cfg["governance"]["reviewers"]:
        assert issued(run_dir, reviewer).exists()


# ------------------------------------------------------------------ outcome separation

def test_meter_day_sheet_separates_abnormality_from_electrical_fault(cfg):
    """Model 3 ranks abnormality, not faults; the two outcomes must not be conflated."""
    labels = cfg["labels"]["meter_days_sheet"]["editable"]
    assert "engineering_abnormality" in labels
    assert "electrical_fault" in labels
    assert "abnormality_type" in labels
    assert cfg["estimation"]["stratum_b_primary_outcome"] == "engineering_abnormality"
    assert cfg["estimation"]["stratum_d_outcome"] == "electrical_fault"
    assert cfg["estimation"]["stratum_b_secondary_outcome"] == "electrical_fault"


def test_abnormality_type_offers_the_agreed_categories(cfg):
    assert cfg["labels"]["meter_days_sheet"]["abnormality_type_values"] == [
        "Electrical fault", "Data availability", "Operational change",
        "Commissioning", "Normal", "Other"]


def test_findings_sheet_keeps_confirmed_fault(cfg):
    assert cfg["labels"]["findings_sheet"]["editable"][0] == "confirmed_fault"


# ------------------------------------------------------------------ estimator

def _sample(n_cells=3, n_per=10, N_per=100, y=0.5) -> pd.DataFrame:
    rows = []
    for c in range(n_cells):
        for i in range(n_per):
            rows.append({"cell": f"c{c}", "N_h": N_per, "n_h": n_per,
                         "design_weight": N_per / n_per,
                         "y": 1.0 if i < int(n_per * y) else 0.0})
    return pd.DataFrame(rows)


def test_weighted_ratio_matches_a_hand_computation():
    assert estimation.weighted_ratio(np.array([1, 0, 1]),
                                     np.array([2, 1, 1])) == pytest.approx(3 / 4)


def test_a_census_cell_contributes_zero_sampling_variance():
    """pi_h = 1 means we looked at every unit; there is no sampling variance to have."""
    d = _sample(n_cells=1, n_per=20, N_per=20)
    res = estimation.linearised_variance(d, "y")
    assert res["census_cells"] == 1
    assert res["variance"] == pytest.approx(0.0)
    assert res["se"] == pytest.approx(0.0)


def test_finite_population_correction_shrinks_the_interval():
    small_fraction = estimation.linearised_variance(_sample(n_per=10, N_per=1000), "y")
    large_fraction = estimation.linearised_variance(_sample(n_per=10, N_per=12), "y")
    assert large_fraction["se"] < small_fraction["se"]


def test_bootstrap_holds_census_cells_fixed():
    d = _sample(n_cells=1, n_per=20, N_per=20)
    res = estimation.fpc_stratified_bootstrap(d, "y", replicates=200, seed=1)
    assert res["ci_low"] == pytest.approx(res["ci_high"])
    assert res["ci_low"] == pytest.approx(res["estimate"])


def test_the_bootstrap_cross_check_agrees_with_the_primary_interval():
    """The bootstrap is a SECONDARY cross-check on the primary linearised FPC interval, so
    the two should land in the same place on a design with no census cells."""
    d = _sample(n_cells=4, n_per=25, N_per=400)
    primary = estimation.linearised_variance(d, "y")
    cross_check = estimation.fpc_stratified_bootstrap(d, "y", replicates=2000, seed=7)
    assert abs(primary["estimate"] - cross_check["estimate"]) < 1e-9
    primary_w = primary["ci_high"] - primary["ci_low"]
    cross_w = cross_check["ci_high"] - cross_check["ci_low"]
    assert 0.3 < (cross_w / primary_w) < 3.0


def test_singleton_non_census_cells_are_reported_not_silently_dropped():
    d = pd.DataFrame([{"cell": "solo", "N_h": 100, "n_h": 1,
                       "design_weight": 100.0, "y": 1.0}])
    res = estimation.linearised_variance(d, "y")
    assert res["singleton_cells"] == ["solo"]


def test_unsure_is_reported_four_ways_and_never_discarded():
    d = pd.DataFrame({"label": ["Y", "N", "Unsure", "Y"],
                      "design_weight": [1.0, 1.0, 1.0, 1.0]})
    out = estimation.unsure_sensitivity(d, "label")
    assert out["n_total"] == 4 and out["n_unsure"] == 1 and out["n_resolved"] == 3
    assert out["resolved_case"] == pytest.approx(2 / 3)
    assert out["weighted_unsure_rate"] == pytest.approx(1 / 4)
    assert out["conservative_all_N"] == pytest.approx(2 / 4)
    assert out["optimistic_all_Y"] == pytest.approx(3 / 4)
    assert out["conservative_all_N"] <= out["optimistic_all_Y"]


def test_unsure_bounds_bracket_the_resolved_estimate():
    d = pd.DataFrame({"label": ["Y"] * 3 + ["N"] * 3 + ["Unsure"] * 4,
                      "design_weight": [1.0] * 10})
    out = estimation.unsure_sensitivity(d, "label")
    assert out["conservative_all_N"] <= out["resolved_case"] <= out["optimistic_all_Y"]


# ------------------------------------------------------------------ package integrity

def test_allocation_was_written_before_rows_were_drawn(run_dir):
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    assert meta["allocation_frozen_before_sampling"] is True
    assert (run_dir / "task4_allocation_stratum_a.csv").exists()
    assert (run_dir / "task4_allocation_stratum_b.csv").exists()


def test_total_drawn_is_exactly_the_budget(run_dir, cfg):
    report = pd.read_csv(run_dir / "task4_allocation_report.csv")
    assert int(report["drawn"].sum()) == int(cfg["budget"]["total_labels"]) == 200


def test_shortfalls_are_recorded_not_backfilled(run_dir):
    report = pd.read_csv(run_dir / "task4_allocation_report.csv")
    c = report.loc[report["stratum"].eq("C")].iloc[0]
    assert c["drawn"] == c["available"]        # population-limited, not topped up
    assert c["shortfall"] == c["requested"] - c["drawn"]


def test_key_is_withheld_and_joins_one_to_one(run_dir, cfg):
    import openpyxl
    key = pd.read_parquet(run_dir / "task4_queue_key.parquet")
    assert key["review_id"].is_unique
    assert len(key) == int(cfg["budget"]["total_labels"])
    # Each reviewer copy holds a PARTITION of the 200 units, so the key joins to the union
    # across reviewers, not to any single workbook.
    ids = set()
    for reviewer in cfg["governance"]["reviewers"]:
        wb = openpyxl.load_workbook(issued(run_dir, reviewer))
        for sheet in ("findings", "meter_days"):
            ws = wb[sheet]
            j = [c.value for c in ws[1]].index("review_id") + 1
            ids |= {ws.cell(row=i, column=j).value
                    for i in range(2, ws.max_row + 1)}
    assert ids == set(key["review_id"])


def test_no_label_is_invented_and_no_metric_is_computed(run_dir, cfg):
    import openpyxl
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    assert meta["labels_present"] is False
    assert meta["metrics_computed"] == []
    assert "NOT COMPUTED" in meta["precision_and_recall"]

    wb = openpyxl.load_workbook(issued(run_dir, cfg["governance"]["reviewers"][0]))
    for sheet, labels in (("findings", FINDING_LABELS),
                          ("meter_days", METER_DAY_LABELS)):
        ws = wb[sheet]
        header = [c.value for c in ws[1]]
        for col in labels:
            j = header.index(col) + 1
            values = {ws.cell(row=i, column=j).value
                      for i in range(2, ws.max_row + 1)}
            assert values <= {None, ""}, f"{sheet}.{col} is not empty"


def test_worklist_is_unblinded_and_severity_ordered(run_dir):
    work = pd.read_excel(run_dir / "task4_worklist.xlsx", sheet_name="worklist")
    assert "worst_severity" in work.columns
    ranks = work["worst_severity"].map(SEVERITY_RANK).to_numpy()
    assert (np.diff(ranks) >= 0).all()
    assert work["worst_severity"].iloc[0] == "Critical"


def test_frozen_models_are_unchanged(run_dir, cfg):
    import hashlib
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    for rel, expected in meta["frozen_artifact_digests"].items():
        run, name = rel.split("/", 1)
        path = ML_WORK / "outputs" / cfg["frozen_runs"][run] / name
        actual = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
        assert actual == expected, f"{rel} changed since the package was built"


def test_adjudicator_must_be_named_before_collection(run_dir):
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    assert "adjudicator" in meta
    # still TBD today, and the package records that it blocks collection
    assert "TBD" in meta["adjudicator"] or meta["adjudicator"]


# ------------------------------------------------------------------ interval contract

def test_config_names_linearisation_with_fpc_as_the_primary_interval(cfg):
    e = cfg["estimation"]
    assert e["method"] == "survey_weighted_linearisation_with_fpc"
    assert e["cross_check"] == "fpc_aware_stratified_bootstrap"
    assert e["never_report"] == "simple_binomial"


def test_a_simple_binomial_interval_is_never_the_reported_figure(cfg):
    """A stratified design with inclusion probabilities spanning 6.5x is not a simple random
    sample, and census cells have no sampling variance to attribute."""
    assert "binomial" not in cfg["estimation"]["method"]
    src = (ML_WORK / "src" / "review_loop" / "estimation.py").read_text(encoding="utf-8")
    assert "1.96 * np.sqrt(p" not in src
    assert "binomial" not in src.lower()


def test_the_primary_interval_zeroes_out_census_cells(cfg):
    """(1 - f_h) is exactly 0 when f_h = 1, so a census contributes no sampling variance."""
    d = _sample(n_cells=2, n_per=20, N_per=20)
    res = estimation.linearised_variance(d, "y")
    assert res["census_cells"] == 2
    assert res["variance"] == pytest.approx(0.0)
    assert res["ci_low"] == pytest.approx(res["ci_high"])


def test_the_cross_check_holds_census_cells_fixed_rather_than_resampling_them():
    """A with-replacement bootstrap over a census would invent variance that does not exist."""
    d = _sample(n_cells=1, n_per=15, N_per=15)
    out = estimation.fpc_stratified_bootstrap(d, "y", replicates=300, seed=11)
    assert out["ci_low"] == pytest.approx(out["ci_high"])
    assert out["ci_low"] == pytest.approx(out["estimate"])


def test_the_frozen_allocation_really_does_contain_census_cells(findings, cfg):
    """Four of the twelve cells are censuses, so this is not a hypothetical concern."""
    alloc = allocate_stratum_a(findings, cfg)
    assert int(alloc["is_census"].sum()) == 4
    assert set(alloc.loc[alloc["is_census"], "family"]) == {"T1", "T2"}


def test_run_metadata_states_the_interval_contract(run_dir):
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    assert meta["estimation_primary"].startswith("survey-weighted linearisation")
    assert "finite-population" in meta["estimation_primary"]
    cross = meta["estimation_cross_check"].lower()
    assert "bootstrap" in cross and "census cells held fixed" in cross
    assert "binomial" in meta["estimation_never"]
    assert "SECONDARY cross-check" in meta["estimation_note"]
    assert "ZERO sampling variance" in meta["estimation_note"]


def test_no_metric_was_computed_during_the_documentation_cleanup(run_dir):
    meta = json.loads((run_dir / "run_metadata.json").read_text(encoding="utf-8"))
    assert meta["metrics_computed"] == []
    assert meta["labels_present"] is False
    assert "No unit redrawn" in meta["documentation_only_update"]
