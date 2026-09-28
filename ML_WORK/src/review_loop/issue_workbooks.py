"""Task 4 — apply the reviewer assignment and re-issue the workbooks.

This NEVER redraws a review unit. It reads the already-built package, verifies that the 200
units and their inclusion probabilities are untouched, partitions them between reviewers,
and rewrites only the reviewer-specific .xlsx copies plus the key.

Sampling is frozen. Assignment decides who reviews a unit, not which units exist.

Usage:
    python src/review_loop/issue_workbooks.py
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, write_run_metadata  # noqa: E402
from review_loop.assignment import assign_reviewers, assignment_summary, verify  # noqa: E402
from review_loop.build_queue import load_config  # noqa: E402
from review_loop.workbook import (  # noqa: E402
    FINDING_LABELS, FINDING_VISIBLE, METER_DAY_LABELS, METER_DAY_VISIBLE,
    assert_blinded, write_workbook,
)

PLACEHOLDERS = ("reviewer_1", "reviewer_2", "TBD", "")
SHEETS = {"findings": (FINDING_VISIBLE, FINDING_LABELS),
          "meter_days": (METER_DAY_VISIBLE, METER_DAY_LABELS)}


def identity_status(cfg: dict) -> dict:
    """Named identities are a precondition for issuance, not a formality.

    A placeholder reviewer id makes the double-labelled overlap un-attributable, and an
    unnamed adjudicator leaves `Unsure` and disagreement with no owner.
    """
    reviewers = list(cfg["governance"]["reviewers"])
    adjudicator = str(cfg["governance"]["adjudicator"])
    unnamed = [r for r in reviewers
               if any(p and p in r for p in PLACEHOLDERS) or r in PLACEHOLDERS]
    adjudicator_named = not any(p and p in adjudicator for p in ("TBD", "placeholder"))
    return {
        "reviewers": reviewers,
        "unnamed_reviewers": unnamed,
        "adjudicator": adjudicator,
        "adjudicator_named": adjudicator_named,
        "identities_complete": bool(not unnamed and adjudicator_named),
    }


UNITS_FILE = "task4_review_units.parquet"


def read_review_units(run_dir: Path) -> tuple[dict[str, pd.DataFrame], str]:
    """The authoritative, unpartitioned 200 review units.

    Prefers `task4_review_units.parquet`, which holds every unit regardless of who it is
    later assigned to. Falling back to a reviewer workbook is only safe on the very first
    run, before partitioning; afterwards a reviewer copy holds a SUBSET, and re-reading one
    would silently shrink the package.
    """
    units_path = run_dir / UNITS_FILE
    if units_path.exists():
        allu = pd.read_parquet(units_path)
        return ({name: allu.loc[allu["_sheet"].eq(name)].drop(columns=["_sheet"])
                 .reset_index(drop=True) for name in SHEETS}, UNITS_FILE)

    candidates = [p for p in sorted(run_dir.glob("task4_labelling_sample_*.xlsx"))
                  if "_DRAFT" not in p.name]
    if not candidates:
        raise FileNotFoundError(
            f"no {UNITS_FILE} and no unpartitioned workbook in {run_dir}")
    src = candidates[0]
    sheets = {name: pd.read_excel(src, sheet_name=name) for name in SHEETS}
    # Persist them so no later run has to trust a workbook that may have been partitioned.
    pd.concat([df.assign(_sheet=name) for name, df in sheets.items()],
              ignore_index=True).to_parquet(units_path, index=False)
    return sheets, src.name


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, default=None)
    ap.add_argument("--config", type=Path, default=None)
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    run_dir = args.run or sorted((ML_WORK / "outputs").glob("task4_2*"))[-1]
    print(f"package : {run_dir.name}\n")

    key = pd.read_parquet(run_dir / "task4_queue_key.parquet")
    sheets, source_name = read_review_units(run_dir)
    print(f"review units from: {source_name}")
    for name, df in sheets.items():
        print(f"  {name:<11s} {len(df):>3d} units")

    # ---- the units and their weights must be exactly what was already accepted
    ids_before = set(key["review_id"])
    sheet_ids = set().union(*(set(df["review_id"]) for df in sheets.values()))
    if ids_before != sheet_ids:
        raise RuntimeError("workbook review_ids do not match the key; refusing to re-issue")
    weights_before = key.set_index("review_id")["inclusion_probability"].to_dict()

    # ---- assignment
    assigned = assign_reviewers(key, cfg)
    report = verify(assigned, cfg)
    summary = assignment_summary(assigned, cfg)

    print("\n=== assignment verification ===")
    for k, v in report["checks"].items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    print(f"\n  units {report['total_units']}   overlap {report['actual_overlap']} "
          f"(target {report['target_overlap']})   "
          f"total assignments {report['total_assignments']}")
    print(f"  overlap by sheet: {report['overlap_by_sheet']}")
    print(f"  units per reviewer: {report['units_per_reviewer']}")
    if not report["all_passed"]:
        raise RuntimeError("assignment contract not satisfied")

    weights_after = assigned.set_index("review_id")["inclusion_probability"].to_dict()
    if weights_before != weights_after:
        raise RuntimeError("inclusion probabilities changed; refusing to re-issue")
    print("  inclusion probabilities unchanged for all 200 units")

    print("\n=== assignment summary ===")
    print(summary.to_string(index=False))

    # ---- identities
    status = identity_status(cfg)
    print("\n=== reviewer / adjudicator identities ===")
    print(f"  reviewers  : {status['reviewers']}")
    print(f"  adjudicator: {status['adjudicator']}")
    if not status["identities_complete"]:
        print("  STATUS: placeholder identities still present - workbooks are written as a")
        print("          DRAFT and must not be issued until real names are configured.")
    else:
        print("  STATUS: named - workbooks are issuable.")

    # ---- rewrite ONLY the reviewer copies
    lab = cfg["labels"]
    validation = {
        "findings": {"confirmed_fault": lab["findings_sheet"]["confirmed_fault_values"]},
        "meter_days": {
            "engineering_abnormality":
                lab["meter_days_sheet"]["engineering_abnormality_values"],
            "electrical_fault": lab["meter_days_sheet"]["electrical_fault_values"],
            "abnormality_type": lab["meter_days_sheet"]["abnormality_type_values"],
        },
    }
    suffix = "" if status["identities_complete"] else "_DRAFT"
    assign_map = assigned.set_index("review_id")["assigned_to"].to_dict()

    written, counts = [], {}
    for reviewer in cfg["governance"]["reviewers"]:
        out_sheets = {}
        for name, (visible, labels) in SHEETS.items():
            df = sheets[name].copy()
            mine = df["review_id"].map(
                lambda rid: reviewer in str(assign_map.get(rid, "")).split("+"))
            df = df.loc[mine].copy()
            df["reviewer_id"] = reviewer
            for col in labels:
                df[col] = ""
            df = df[visible + labels]
            assert_blinded(df)
            out_sheets[name] = df
        counts[reviewer] = {k: len(v) for k, v in out_sheets.items()}
        path = run_dir / f"task4_labelling_sample_{reviewer}{suffix}.xlsx"
        write_workbook(path, out_sheets,
                       editable={"findings": lab["findings_sheet"]["editable"],
                                 "meter_days": lab["meter_days_sheet"]["editable"]},
                       validation=validation)
        written.append(path.name)
        print(f"\n  {path.name}: findings {counts[reviewer]['findings']}, "
              f"meter_days {counts[reviewer]['meter_days']}")

    assigned.to_parquet(run_dir / "task4_queue_key.parquet", index=False)
    summary.to_csv(run_dir / "task4_assignment_summary.csv", index=False)
    assigned[["review_id", "sheet", "stratum", "assigned_to", "is_overlap"]].to_csv(
        run_dir / "task4_reviewer_assignment.csv", index=False)

    write_run_metadata(run_dir, {
        "task": "Task 4 - reviewer assignment and workbook issuance",
        "package": str(run_dir),
        "units_redrawn": False,
        "sampling_design_changed": False,
        "inclusion_probabilities_unchanged": True,
        "assignment": report,
        "assignment_summary": summary.to_dict("records"),
        "assignment_rule": (
            "Stratified by (sheet, stratum) so neither reviewer receives a skewed mix and "
            "the overlap sample spans strata. Overlap allocated across strata in proportion "
            "to size by largest remainder; the remainder alternates between reviewers, with "
            "the starting reviewer flipped per group to keep workloads level. Fixed seed."),
        "agreement_reporting": (
            "Raw agreement AND Cohen's kappa are both reported, per sheet and per label "
            "column. With about 20 double-reviewed units both carry very wide intervals, so "
            "they are DIAGNOSTIC: they indicate whether the labelling task is reproducible, "
            "not what the agreement is. A bootstrap interval on kappa is reported so its "
            "instability is visible."),
        "identities": status,
        "issuable": status["identities_complete"],
        "workbooks": written,
        "workbook_row_counts": counts,
        "labels_present": False,
        "metrics_computed": [],
        "precision_and_recall": (
            "NOT CLAIMED and NOT COMPUTED. No engineering label exists. Precision, "
            "unflagged_fault_rate, Model 3 validation and agreement all wait for returned "
            "labels."),
        "task4_status": (
            "ASSIGNMENT FROZEN - READY FOR ENGINEERING REVIEW"
            if status["identities_complete"]
            else "ASSIGNMENT FROZEN - DRAFT pending named reviewer/adjudicator identities. "
                 "The sampling, assignment and workbooks are complete and frozen; only the "
                 "reviewer and adjudicator names are outstanding, and the workbooks carry a "
                 "_DRAFT suffix until they are supplied."),
    }, filename="run_metadata_issuance.json")

    print(f"\nkey updated with assignments: task4_queue_key.parquet")
    print("NO UNIT REDRAWN. NO LABEL INVENTED. NO METRIC COMPUTED.")
    return 0 if status["identities_complete"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
