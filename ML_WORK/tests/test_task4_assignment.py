"""Task 4 — reviewer assignment contract and inter-rater agreement.

Assignment decides WHO reviews a unit. It must not change which units exist, or what any of
them weighs: the 200 sampled units and their inclusion probabilities are frozen.

The agreement functions are built and tested here but are NOT run against real data — no
engineering label exists yet.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

from review_loop import agreement as agree_mod
from review_loop.assignment import assign_reviewers, assignment_summary, verify
from review_loop.build_queue import load_config
from review_loop.issue_workbooks import identity_status
from review_loop.workbook import (
    FINDING_LABELS, FORBIDDEN_SUBSTRINGS, METER_DAY_LABELS,
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


@pytest.fixture(scope="module")
def assigned(run_dir) -> pd.DataFrame:
    key = pd.read_parquet(run_dir / "task4_queue_key.parquet")
    if "assigned_to" not in key.columns:
        pytest.skip("assignment has not been applied yet")
    return key


def _issued(run_dir: Path, reviewer: str) -> Path:
    for name in (f"task4_labelling_sample_{reviewer}.xlsx",
                 f"task4_labelling_sample_{reviewer}_DRAFT.xlsx"):
        if (run_dir / name).exists():
            return run_dir / name
    pytest.skip(f"no workbook for {reviewer}")


# ------------------------------------------------------------------ coverage

def test_all_200_units_are_covered_exactly_once(assigned, cfg):
    assert len(assigned) == int(cfg["budget"]["total_labels"]) == 200
    assert assigned["review_id"].is_unique
    assert assigned["assigned_to"].notna().all()
    assert (assigned["assigned_to"].str.len() > 0).all()


def test_about_ten_percent_are_double_reviewed(assigned, cfg):
    overlap = int(assigned["is_overlap"].sum())
    target = round(len(assigned) * cfg["assignment"]["overlap_fraction"])
    assert abs(overlap - target) <= cfg["assignment"]["overlap_tolerance"]
    assert overlap == 20


def test_not_all_rows_go_to_both_reviewers(assigned):
    assert int(assigned["is_overlap"].sum()) < len(assigned)
    assert int((~assigned["is_overlap"]).sum()) == 180


def test_overlap_appears_in_both_sheets(assigned):
    by_sheet = assigned.loc[assigned["is_overlap"]].groupby("sheet").size()
    assert set(by_sheet.index) == {"findings", "meter_days"}
    assert (by_sheet > 0).all()


def test_overlap_spans_more_than_one_stratum(assigned):
    strata = set(assigned.loc[assigned["is_overlap"], "stratum"])
    assert len(strata) >= 2, f"overlap landed in only {strata}"


def test_the_remainder_is_divided_between_the_two(assigned, cfg):
    reviewers = cfg["governance"]["reviewers"]
    sole = assigned.loc[~assigned["is_overlap"]]
    assert set(sole["assigned_to"]) == set(reviewers)
    counts = sole["assigned_to"].value_counts()
    assert abs(counts[reviewers[0]] - counts[reviewers[1]]) <= 2


def test_a_double_reviewed_unit_keeps_one_review_id(assigned, cfg):
    reviewers = cfg["governance"]["reviewers"]
    overlap = assigned.loc[assigned["is_overlap"]]
    assert overlap["review_id"].is_unique
    for value in overlap["assigned_to"]:
        assert sorted(value.split("+")) == sorted(reviewers)


def test_assignments_are_stored_in_the_withheld_key(assigned):
    for col in ("assigned_to", "is_overlap", "inclusion_probability", "design_weight"):
        assert col in assigned.columns


# ------------------------------------------------------------------ reproducibility

def test_assignment_is_reproducible_from_the_seed(cfg, assigned):
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    a = assign_reviewers(base, cfg)
    b = assign_reviewers(base, cfg)
    pd.testing.assert_frame_equal(a, b)
    assert a["assigned_to"].tolist() == assigned["assigned_to"].tolist()


def test_a_different_seed_gives_a_different_assignment(cfg, assigned):
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    other = dict(cfg, assignment=dict(cfg["assignment"], seed=999))
    assert (assign_reviewers(base, other)["assigned_to"].tolist()
            != assigned["assigned_to"].tolist())


def test_verify_rejects_sending_everything_to_both(cfg, assigned):
    broken = assigned.copy()
    broken["assigned_to"] = "+".join(cfg["governance"]["reviewers"])
    broken["is_overlap"] = True
    out = verify(broken, cfg)
    assert out["all_passed"] is False
    assert out["checks"]["not_everything_is_double_reviewed"] is False


def test_assignment_summary_totals_match_the_key(assigned, cfg):
    summary = assignment_summary(assigned, cfg)
    totals = summary.loc[summary["reviewer"].eq("<total unique>")]
    assert int(totals["units"].sum()) == len(assigned)


# ------------------------------------------------------------------ frozen sampling

def test_assignment_changed_no_inclusion_probability(assigned, run_dir):
    meta = json.loads((run_dir / "run_metadata_issuance.json").read_text(encoding="utf-8"))
    assert meta["inclusion_probabilities_unchanged"] is True
    assert meta["units_redrawn"] is False
    assert meta["sampling_design_changed"] is False


def test_stratum_a_still_has_its_110_units_and_weights(assigned, run_dir):
    alloc = pd.read_csv(run_dir / "task4_allocation_stratum_a.csv")
    rows = assigned.loc[assigned["stratum"].eq("A")]
    assert len(rows) == int(alloc["n_h"].sum()) == 110
    assert (rows["inclusion_probability"] > 0).all()
    assert rows["inclusion_probability"].max() == pytest.approx(1.0)
    assert rows["inclusion_probability"].min() == pytest.approx(0.1538, abs=1e-3)


def test_every_stratum_survives_assignment(assigned):
    assert assigned.groupby("stratum").size().to_dict() == {
        "A": 110, "B": 49, "C": 1, "D": 40}


# ------------------------------------------------------------------ issued workbooks

def test_each_reviewer_workbook_holds_only_their_assigned_units(run_dir, cfg, assigned):
    for reviewer in cfg["governance"]["reviewers"]:
        expected = set(assigned.loc[
            assigned["assigned_to"].str.split("+").apply(lambda v: reviewer in v),
            "review_id"])
        got = set()
        for sheet in ("findings", "meter_days"):
            got |= set(pd.read_excel(_issued(run_dir, reviewer),
                                     sheet_name=sheet)["review_id"])
        assert got == expected
        assert len(got) < 200, "a reviewer must not receive all 200 units"


def test_the_union_of_both_workbooks_covers_every_unit(run_dir, cfg, assigned):
    union = set()
    for reviewer in cfg["governance"]["reviewers"]:
        for sheet in ("findings", "meter_days"):
            union |= set(pd.read_excel(_issued(run_dir, reviewer),
                                       sheet_name=sheet)["review_id"])
    assert union == set(assigned["review_id"])


def test_double_reviewed_ids_appear_in_both_copies(run_dir, cfg, assigned):
    overlap_ids = set(assigned.loc[assigned["is_overlap"], "review_id"])
    sets = []
    for reviewer in cfg["governance"]["reviewers"]:
        ids = set()
        for sheet in ("findings", "meter_days"):
            ids |= set(pd.read_excel(_issued(run_dir, reviewer),
                                     sheet_name=sheet)["review_id"])
        sets.append(ids)
    assert overlap_ids <= (sets[0] & sets[1])
    assert len(sets[0] & sets[1]) == len(overlap_ids)


def test_issued_workbooks_stay_blinded_and_unlabelled(run_dir, cfg):
    import openpyxl
    for reviewer in cfg["governance"]["reviewers"]:
        wb = openpyxl.load_workbook(_issued(run_dir, reviewer))
        for sheet, labels in (("findings", FINDING_LABELS),
                              ("meter_days", METER_DAY_LABELS)):
            ws = wb[sheet]
            header = [c.value for c in ws[1]]
            assert not any(any(bad in str(h).lower() for bad in FORBIDDEN_SUBSTRINGS)
                           for h in header)
            for col in labels:
                j = header.index(col) + 1
                values = {ws.cell(row=i, column=j).value
                          for i in range(2, ws.max_row + 1)}
                assert values <= {None, ""}


# ------------------------------------------------------------------ identities

def test_placeholder_identities_block_issuance(cfg):
    status = identity_status(cfg)
    if status["identities_complete"]:
        pytest.skip("identities have been named")
    assert status["unnamed_reviewers"] or not status["adjudicator_named"]


def test_named_identities_unblock_issuance():
    named = {"governance": {"reviewers": ["a.khan", "s.ali"],
                            "adjudicator": "m.ibrahim"}}
    status = identity_status(named)
    assert status["identities_complete"] is True
    assert status["unnamed_reviewers"] == []


def test_a_tbd_adjudicator_is_rejected():
    bad = {"governance": {"reviewers": ["a.khan", "s.ali"], "adjudicator": "TBD"}}
    assert identity_status(bad)["identities_complete"] is False


def test_a_placeholder_reviewer_is_rejected():
    bad = {"governance": {"reviewers": ["reviewer_1", "s.ali"],
                          "adjudicator": "m.ibrahim"}}
    assert identity_status(bad)["identities_complete"] is False


# ------------------------------------------------------------------ agreement

def test_raw_agreement_and_kappa_are_both_reported():
    a = pd.Series(["Y", "Y", "N", "N", "Y"])
    b = pd.Series(["Y", "Y", "N", "Y", "Y"])
    out = agree_mod.cohens_kappa(a, b)
    assert out["raw_agreement"] == pytest.approx(0.8)
    assert "kappa" in out and "expected_agreement" in out


def test_perfect_agreement_gives_kappa_one():
    a = pd.Series(["Y", "N", "Y", "N"])
    assert agree_mod.cohens_kappa(a, a)["kappa"] == pytest.approx(1.0)


def test_kappa_can_be_low_despite_high_raw_agreement():
    """The kappa paradox: with one dominant category, chance agreement is already high, so
    kappa collapses even though the reviewers almost always agree. This is why raw
    agreement is reported alongside it rather than instead of it."""
    a = pd.Series(["Y"] * 18 + ["N", "Y"])
    b = pd.Series(["Y"] * 18 + ["Y", "N"])
    out = agree_mod.cohens_kappa(a, b)
    assert out["raw_agreement"] >= 0.9
    assert out["kappa"] < 0.2


def test_kappa_interval_is_wide_at_this_sample_size():
    rng = np.random.default_rng(0)
    a = pd.Series(rng.choice(["Y", "N"], 20))
    b = pd.Series(rng.choice(["Y", "N"], 20))
    ci = agree_mod.bootstrap_kappa_ci(a, b, replicates=500, seed=3)
    assert ci["ci_low"] < ci["ci_high"]
    assert ci["ci_high"] - ci["ci_low"] > 0.3


def test_agreement_is_labelled_diagnostic():
    assert "DIAGNOSTIC" in agree_mod.DIAGNOSTIC_NOTE


def test_agreement_report_returns_nothing_without_labels(assigned, cfg):
    """No label exists yet, so the report must return no estimate rather than invent one."""
    empty = pd.DataFrame(columns=["review_id", "reviewer_id", "confirmed_fault"])
    out = agree_mod.agreement_report(
        empty, assigned, {"findings": ["confirmed_fault"]},
        cfg["governance"]["reviewers"])
    assert (out["n_overlap"] == 0).all()
    assert out["raw_agreement"].isna().all()


def test_no_outcome_metric_has_been_computed(run_dir):
    meta = json.loads((run_dir / "run_metadata_issuance.json").read_text(encoding="utf-8"))
    assert meta["labels_present"] is False
    assert meta["metrics_computed"] == []
    assert "NOT COMPUTED" in meta["precision_and_recall"]


# ------------------------------------------------------------------ forced C overlap

def test_overlap_by_stratum_matches_the_frozen_plan(assigned, cfg):
    got = assigned.loc[assigned["is_overlap"]].groupby("stratum").size().to_dict()
    assert {k: int(v) for k, v in got.items()} == \
        cfg["assignment"]["expected_overlap_by_stratum"]
    assert got == {"A": 11, "B": 4, "C": 1, "D": 4}


def test_the_single_stratum_c_unit_is_double_reviewed(assigned, cfg):
    """It is the only unexplained Model-3 Top-100 item, so two people look at it."""
    c = assigned.loc[assigned["stratum"].eq("C")]
    assert len(c) == 1
    assert bool(c["is_overlap"].iloc[0]) is True
    assert sorted(c["assigned_to"].iloc[0].split("+")) == \
        sorted(cfg["governance"]["reviewers"])


def test_forcing_c_costs_exactly_one_stratum_b_overlap(cfg, assigned):
    """The total stays at 20: one B unit is demoted, and the choice follows from the seed
    already in use rather than a new decision."""
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    unforced = assign_reviewers(
        base, dict(cfg, assignment=dict(cfg["assignment"], force_overlap_strata=[])))
    before = set(unforced.loc[unforced["is_overlap"], "review_id"])
    after = set(assigned.loc[assigned["is_overlap"], "review_id"])

    assert len(before) == len(after) == 20
    demoted, promoted = before - after, after - before
    assert len(demoted) == 1 and len(promoted) == 1
    assert assigned.loc[assigned["review_id"].isin(promoted), "stratum"].iloc[0] == "C"
    assert unforced.loc[unforced["review_id"].isin(demoted), "stratum"].iloc[0] == "B"


def test_a_demoted_unit_is_still_reviewed_by_someone(cfg, assigned):
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    unforced = assign_reviewers(
        base, dict(cfg, assignment=dict(cfg["assignment"], force_overlap_strata=[])))
    demoted = (set(unforced.loc[unforced["is_overlap"], "review_id"])
               - set(assigned.loc[assigned["is_overlap"], "review_id"]))
    row = assigned.loc[assigned["review_id"].isin(demoted)].iloc[0]
    assert row["assigned_to"] in cfg["governance"]["reviewers"]
    assert bool(row["is_overlap"]) is False


def test_forced_overlap_does_not_change_the_total(assigned):
    assert int(assigned["is_overlap"].sum()) == 20
    assert len(assigned) == 200


def test_forcing_is_reproducible(cfg, assigned):
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    a = assign_reviewers(base, cfg)
    b = assign_reviewers(base, cfg)
    pd.testing.assert_frame_equal(a, b)
    assert a["assigned_to"].tolist() == assigned["assigned_to"].tolist()


def test_a_donor_that_is_its_own_forced_stratum_is_refused(cfg, assigned):
    """It would pay for itself: the +1 and the -1 cancel and the forcing silently vanishes."""
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    broken = dict(cfg, assignment=dict(
        cfg["assignment"], force_overlap_strata=["C"], compensate_overlap_from="C"))
    with pytest.raises(ValueError, match="cancel its own forcing"):
        assign_reviewers(base, broken)


def test_forcing_fails_loudly_if_the_donor_cannot_pay(cfg, assigned):
    base = assigned.drop(columns=["assigned_to", "is_overlap"])
    broken = dict(cfg, assignment=dict(
        cfg["assignment"], force_overlap_strata=["A", "B", "C", "D"],
        compensate_overlap_from="A", overlap_fraction=0.005))
    with pytest.raises(ValueError, match="cannot release|cancel its own forcing"):
        assign_reviewers(base, broken)


# ------------------------------------------------------------------ n=1 is not an estimate

def test_a_single_pair_is_reported_but_never_estimated():
    """The C double-review is a governance check that two people looked at it. With n = 1
    there is no agreement to estimate, and the report must say so rather than print a
    number."""
    key = pd.DataFrame([{"review_id": "D0050", "sheet": "meter_days",
                         "is_overlap": True}])
    labels = pd.DataFrame([
        {"review_id": "D0050", "reviewer_id": "r1", "engineering_abnormality": "Y"},
        {"review_id": "D0050", "reviewer_id": "r2", "engineering_abnormality": "Y"}])
    out = agree_mod.agreement_report(
        labels, key, {"meter_days": ["engineering_abnormality"]}, ["r1", "r2"],
        min_pairs=5)
    row = out.iloc[0]
    assert row["n_overlap"] == 1
    assert pd.isna(row["kappa"])
    assert "NOT ESTIMABLE" in row["note"]


def test_enough_pairs_do_produce_an_estimate():
    ids = [f"X{i:03d}" for i in range(8)]
    key = pd.DataFrame({"review_id": ids, "sheet": "findings", "is_overlap": True})
    labels = pd.concat([
        pd.DataFrame({"review_id": ids, "reviewer_id": "r1",
                      "confirmed_fault": ["Y", "N"] * 4}),
        pd.DataFrame({"review_id": ids, "reviewer_id": "r2",
                      "confirmed_fault": ["Y", "N", "Y", "Y"] * 2})])
    out = agree_mod.agreement_report(
        labels, key, {"findings": ["confirmed_fault"]}, ["r1", "r2"], min_pairs=5)
    row = out.iloc[0]
    assert row["n_overlap"] == 8
    assert not pd.isna(row["kappa"])
    assert "DIAGNOSTIC" in row["note"]


def test_min_pairs_threshold_comes_from_config(cfg):
    assert cfg["assignment"]["min_pairs_for_agreement"] >= 2
