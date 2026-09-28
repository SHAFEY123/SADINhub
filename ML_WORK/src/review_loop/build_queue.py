"""Task 4 — build the unlabelled review package.

Order is deliberate and enforced by the code path:

  1. reconcile every population
  2. FREEZE and write the allocation table
  3. only then draw rows
  4. build the blinded reviewer workbooks and the un-blinded worklist
  5. write the withheld key

NO ENGINEERING LABEL IS INVENTED and NO VALIDATION METRIC IS COMPUTED. The label columns
are emitted empty for engineering to fill.

Usage:
    python src/review_loop/build_queue.py
"""
from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, new_run_dir, write_run_metadata  # noqa: E402
from review_loop.allocation import (  # noqa: E402
    SEVERITY_RANK, allocate_stratum_a, allocate_stratum_b, allocation_report,
)
from review_loop.sampling import (  # noqa: E402
    sample_stratum_a, sample_stratum_b, sample_stratum_c, sample_stratum_d,
)
from review_loop.workbook import (  # noqa: E402
    FINDING_LABELS, FINDING_VISIBLE, METER_DAY_LABELS, METER_DAY_VISIBLE,
    assert_blinded, shuffle, write_workbook,
)

KEY = ["meter_label", "day_saudi"]


def load_config(path: Path | None = None) -> dict:
    p = path or (ML_WORK / "config" / "task4_config.yaml")
    return yaml.safe_load(p.read_text(encoding="utf-8"))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def expand_events(events: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for r in events.itertuples(index=False):
        for day in pd.date_range(pd.Timestamp(r.event_start).normalize(),
                                 pd.Timestamp(r.event_end).normalize(), freq="D"):
            rows.append((r.meter_label, day, r.event_class, bool(r.commissioning)))
    return pd.DataFrame(rows, columns=["meter_label", "day_saudi", "event_class",
                                       "commissioning"]).drop_duplicates()


def build_evidence(feature_table: pd.DataFrame) -> pd.DataFrame:
    """Neutral evidence available for EVERY observed meter-day, flagged or not."""
    e = feature_table[[
        "meter_label", "short_label", "day_saudi", "readings_reported",
        "coverage_ratio", "mean_load_pct_cb",
        "negative_total_power_rate", "negative_phase_power_rate",
        "current_without_power_rate", "power_without_current_rate",
        "pf_critical_rate_gated_1", "pf_critical_rate_gated_2", "pf_critical_rate_gated_3",
        "pf_gate_open_rate_1", "pf_gate_open_rate_2", "pf_gate_open_rate_3",
        "major_issue_rate", "major_problem_rate",
        "voltage_not_acceptable_rate", "frequency_not_acceptable_rate"]].copy()
    return e.rename(columns={
        "pf_critical_rate_gated_1": "pf_critical_rate_phase_1",
        "pf_critical_rate_gated_2": "pf_critical_rate_phase_2",
        "pf_critical_rate_gated_3": "pf_critical_rate_phase_3",
        "pf_gate_open_rate_1": "pf_load_gate_open_rate_1",
        "pf_gate_open_rate_2": "pf_load_gate_open_rate_2",
        "pf_gate_open_rate_3": "pf_load_gate_open_rate_3"})


def finding_observation(row) -> str:
    """A neutral description of what was MEASURED. It never states a conclusion, a severity
    or a detector name."""
    unit = str(row.magnitude_unit or "")
    return (f"{int(row.total_flagged):,} readings on phase {int(row.phase)} over "
            f"{float(row.total_duration_days):.1f} days showed "
            f"{float(row.max_magnitude):.3f} {unit.replace('_', ' ')}.")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", type=Path, default=None)
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    frozen = cfg["frozen_runs"]
    out_dir = ML_WORK / "outputs"
    m1_dir, m3_dir = out_dir / frozen["model1"], out_dir / frozen["model3"]
    feat_path = out_dir / frozen["model3_features"] / "model3_feature_table.parquet"

    run_dir = new_run_dir("task4")
    print(f"run directory : {run_dir}\n")

    findings = pd.read_csv(m1_dir / "findings_summary.csv")
    events = pd.read_parquet(m1_dir / "anomaly_events.parquet")
    scores = pd.read_parquet(m3_dir / "model3_model1_crosscheck.parquet")
    feature = pd.read_parquet(feat_path)
    evidence = build_evidence(feature)

    # ---------------------------------------------------------------- 1. reconcile
    universe = feature[KEY].drop_duplicates()
    daily = expand_events(events)
    flagged = daily.loc[daily["event_class"].eq("ELECTRICAL_FAULT")
                        & ~daily["commissioning"], KEY].drop_duplicates()
    observed_flagged = flagged.merge(universe, on=KEY, how="inner")
    unflagged = universe.merge(flagged, on=KEY, how="left", indicator=True)
    unflagged = unflagged.loc[unflagged["_merge"].eq("left_only"), KEY]

    recon = {
        "observed_meter_days": int(len(universe)),
        "model1_findings_total": int(len(findings)),
        "model1_events": int(len(events)),
        "flagged_meter_days_all": int(len(flagged)),
        "flagged_meter_days_observed": int(len(observed_flagged)),
        "unflagged_observed_meter_days": int(len(unflagged)),
        "reconciles": bool(len(observed_flagged) + len(unflagged) == len(universe)),
    }
    print("=== population reconciliation ===")
    for k, v in recon.items():
        print(f"  {k:<34s} {v}")
    if not recon["reconciles"]:
        raise RuntimeError("flagged + unflagged does not equal the observed universe")

    # ---------------------------------------------------------------- 2. FREEZE allocation
    alloc_a = allocate_stratum_a(findings, cfg)
    exp = cfg["stratum_a"]["expected_family_totals"]
    got = alloc_a.groupby("family")["n_h"].sum().to_dict()
    if got != exp:
        raise RuntimeError(f"stratum A family totals {got} != frozen {exp}")
    if int(alloc_a["n_h"].sum()) != int(cfg["budget"]["stratum_a"]):
        raise RuntimeError("stratum A allocation is not integer-exact")

    top = scores.head(int(cfg["stratum_b"]["top_n"]))
    explained = top.loc[top["m1_explains"]]
    unexplained = top.loc[~top["m1_explains"]]
    alloc_b = allocate_stratum_b(explained, scores, cfg)

    n_c = min(len(unexplained), int(cfg["budget"]["stratum_c_cap"]))
    b_target = int(cfg["budget"]["model3_total"]) - n_c
    if int(alloc_b["n_high"].sum() + alloc_b["n_reference"].sum()) != b_target:
        raise RuntimeError(
            f"stratum B drew {int(alloc_b['n_high'].sum() + alloc_b['n_reference'].sum())}, "
            f"expected 50 - C = {b_target}")

    alloc_a.to_csv(run_dir / "task4_allocation_stratum_a.csv", index=False)
    alloc_b.to_csv(run_dir / "task4_allocation_stratum_b.csv", index=False)
    print(f"\nallocation FROZEN and written before any row was drawn")
    print(f"  stratum A: {int(alloc_a['n_h'].sum())} of {int(alloc_a['N_h'].sum())} "
          f"findings, pi {alloc_a['pi_h'].min():.4f}..{alloc_a['pi_h'].max():.4f}")
    print(f"  stratum B: {int(alloc_b['n_high'].sum())} high + "
          f"{int(alloc_b['n_reference'].sum())} reference across "
          f"{int((alloc_b['n_high'] > 0).sum())} meters")

    # ---------------------------------------------------------------- 3. draw rows
    sa = sample_stratum_a(findings, alloc_a, cfg)
    sb = sample_stratum_b(explained, scores, alloc_b, cfg)
    sc = sample_stratum_c(unexplained, cfg)
    sd = sample_stratum_d(unflagged.merge(evidence, on=KEY, how="left"), cfg)
    print(f"\ndrawn: A={len(sa)}  B={len(sb)}  C={len(sc)}  D={len(sd)}  "
          f"total={len(sa) + len(sb) + len(sc) + len(sd)}")

    report = allocation_report(alloc_a, alloc_b, len(unexplained), len(sd),
                               len(unflagged), cfg)
    report.to_csv(run_dir / "task4_allocation_report.csv", index=False)

    # ---------------------------------------------------------------- 4. assemble sheets
    sa = sa.reset_index(drop=True)
    sa["review_id"] = [f"F{i:04d}" for i in range(1, len(sa) + 1)]
    sa["meter"] = sa["short_label"]
    sa["first_date"] = pd.to_datetime(sa["first_start"]).dt.date
    sa["last_date"] = pd.to_datetime(sa["last_end"]).dt.date
    sa["n_days_spanned"] = sa["total_duration_days"].round(1)
    sa["observation"] = [finding_observation(r) for r in sa.itertuples(index=False)]
    sa["evidence_metric"] = "peak magnitude"
    sa["evidence_value"] = sa["max_magnitude"].round(4)
    sa["evidence_unit"] = sa["magnitude_unit"].str.replace("_", " ", regex=False)
    sa["concurrent_classifier_status"] = sa["corroboration"].map(
        {"full": "agrees throughout", "partial": "agrees in part", "none": "does not agree"}
    ).fillna("")

    md = pd.concat([sb, sc, sd], ignore_index=True)
    md = md.drop(columns=[c for c in evidence.columns
                          if c in md.columns and c not in KEY], errors="ignore")
    md = md.merge(evidence, on=KEY, how="left")
    md = md.reset_index(drop=True)
    md["review_id"] = [f"D{i:04d}" for i in range(1, len(md) + 1)]
    md["meter"] = md["short_label"]
    md["date"] = pd.to_datetime(md["day_saudi"]).dt.date

    # ---------------------------------------------------------------- 5. key, then blind
    key_cols_a = ["review_id", "meter_label", "short_label", "phase", "family", "detector",
                  "worst_severity", "stratum", "cell", "N_h", "n_h",
                  "inclusion_probability", "design_weight", "is_census_cell"]
    key_cols_d = ["review_id", "meter_label", "short_label", "day_saudi", "stratum",
                  "b_role", "cell", "N_h", "n_h", "inclusion_probability",
                  "design_weight", "window_anomaly_pct", "window_anomaly_z",
                  "daily_rank_pct", "m1_explains", "rank_contrast"]
    key = pd.concat([
        sa[[c for c in key_cols_a if c in sa.columns]].assign(sheet="findings"),
        md[[c for c in key_cols_d if c in md.columns]].assign(sheet="meter_days"),
    ], ignore_index=True)
    key.to_parquet(run_dir / "task4_queue_key.parquet", index=False)

    lab = cfg["labels"]
    reviewers = list(cfg["governance"]["reviewers"])
    shuffle_seed = int(cfg["seed"]["sheet_shuffle"])

    findings_sheet = shuffle(sa, shuffle_seed)
    meter_days_sheet = shuffle(md, shuffle_seed + 1)

    validation = {
        "findings": {"confirmed_fault": lab["findings_sheet"]["confirmed_fault_values"]},
        "meter_days": {
            "engineering_abnormality":
                lab["meter_days_sheet"]["engineering_abnormality_values"],
            "electrical_fault": lab["meter_days_sheet"]["electrical_fault_values"],
            "abnormality_type": lab["meter_days_sheet"]["abnormality_type_values"],
        },
    }

    workbooks = []
    for reviewer in reviewers:
        f = findings_sheet.copy()
        d = meter_days_sheet.copy()
        f["reviewer_id"] = reviewer
        d["reviewer_id"] = reviewer
        for col in FINDING_LABELS:
            f[col] = ""
        for col in METER_DAY_LABELS:
            d[col] = ""
        f_out = f[FINDING_VISIBLE + FINDING_LABELS]
        d_out = d[METER_DAY_VISIBLE + METER_DAY_LABELS]
        assert_blinded(f_out)
        assert_blinded(d_out)

        path = run_dir / f"task4_labelling_sample_{reviewer}.xlsx"
        write_workbook(path, {"findings": f_out, "meter_days": d_out},
                       editable={"findings": lab["findings_sheet"]["editable"],
                                 "meter_days": lab["meter_days_sheet"]["editable"]},
                       validation=validation)
        workbooks.append(path.name)
    print(f"\nblinded workbooks: {', '.join(workbooks)}")
    print(f"  findings sheet   {len(findings_sheet)} rows, {len(FINDING_VISIBLE)} visible "
          f"columns, {len(FINDING_LABELS)} label columns")
    print(f"  meter_days sheet {len(meter_days_sheet)} rows, "
          f"{len(METER_DAY_VISIBLE)} visible columns, {len(METER_DAY_LABELS)} label columns")

    # ---------------------------------------------------------------- 6. worklist
    work = findings.copy()
    work["severity_rank"] = work["worst_severity"].map(SEVERITY_RANK)
    work = work.sort_values(["severity_rank", "family", "short_label", "phase"])
    work_cols = ["worst_severity", "family", "detector", "short_label", "phase",
                 "n_episodes", "total_flagged", "first_start", "last_end",
                 "max_magnitude", "magnitude_unit", "event_class", "corroboration",
                 "any_commissioning"]
    write_workbook(run_dir / "task4_worklist.xlsx",
                   {"worklist": work[work_cols]}, editable={}, validation={},
                   protect=False)

    # ---------------------------------------------------------------- 7. frozen check
    frozen_digests = {}
    for name, d in (("model1", m1_dir), ("model3", m3_dir)):
        for f in sorted(d.glob("*.parquet")):
            frozen_digests[f"{name}/{f.name}"] = digest(f)
    frozen_digests["model3_features/model3_feature_table.parquet"] = digest(feat_path)

    write_run_metadata(run_dir, {
        "task": "Task 4 - unlabelled review package (NO LABELS, NO METRICS)",
        "run_directory": str(run_dir),
        "frozen_runs": frozen,
        "frozen_artifact_digests": frozen_digests,
        "population_reconciliation": recon,
        "allocation_frozen_before_sampling": True,
        "allocation_report": report.to_dict("records"),
        "stratum_a": {
            "frame": int(alloc_a["N_h"].sum()),
            "drawn": int(alloc_a["n_h"].sum()),
            "family_totals": got,
            "inclusion_probability_min": float(alloc_a["pi_h"].min()),
            "inclusion_probability_max": float(alloc_a["pi_h"].max()),
            "census_cells": int(alloc_a["is_census"].sum()),
            "cells": alloc_a.to_dict("records"),
        },
        "stratum_b": {
            "high_rows": int(alloc_b["n_high"].sum()),
            "reference_rows": int(alloc_b["n_reference"].sum()),
            "participating_meters": int((alloc_b["n_high"] > 0).sum()),
            "meters": alloc_b.to_dict("records"),
            "reference_rule": (
                "same meter, that meter's own bottom quartile of window_anomaly_pct, and at "
                "least 14 days from every high-ranked day for that meter. The contrast is "
                "WITHIN-METER RELATIVE because an absolute gap is impossible for "
                "ZN.10-PB.1, whose lowest score in the whole history is 0.707."),
            "realised_rank_contrast_min": float(sb["rank_contrast"].min())
            if "rank_contrast" in sb else None,
        },
        "stratum_c": {"drawn": int(len(sc)), "available": int(len(unexplained)),
                      "cap": int(cfg["budget"]["stratum_c_cap"])},
        "stratum_d": {"frame": int(len(unflagged)), "drawn": int(len(sd)),
                      "inclusion_probability": float(len(sd) / len(unflagged)),
                      "frame_note": (
                          "Model 1's OWN observed universe, not Model 3's "
                          "warm-up-restricted 14,130.")},
        "outcomes": {
            "stratum_a": "confirmed_fault",
            "stratum_b_primary": cfg["estimation"]["stratum_b_primary_outcome"],
            "stratum_b_secondary": cfg["estimation"]["stratum_b_secondary_outcome"],
            "stratum_d": cfg["estimation"]["stratum_d_outcome"],
            "note": (
                "Model 3 ranks ABNORMALITY, not faults, so stratum B's primary outcome is "
                "engineering_abnormality; electrical_fault enrichment is secondary. "
                "Stratum D's unflagged_fault_rate uses electrical_fault."),
        },
        "estimation_method": cfg["estimation"]["method"],
        "estimation_primary": "survey-weighted linearisation with finite-population "
                              "correction",
        "estimation_cross_check": "FPC-aware stratified bootstrap, census cells held fixed",
        "estimation_never": "simple binomial 1.96*sqrt(p(1-p)/n)",
        "estimation_note": (
            "The REPORTED interval is survey-weighted linearisation with a "
            "finite-population correction; the (1 - f_h) factor is exactly zero when "
            "f_h = 1, so a census cell contributes ZERO sampling variance. The FPC-aware "
            "stratified bootstrap is a SECONDARY cross-check only: it holds census cells "
            "fixed and rescales non-census cells by sqrt(1 - f_h). A simple binomial "
            "interval is never reported. The weighted ratio point estimate and the "
            "four-way Unsure bounds are unchanged."),
        "labels_present": False,
        "metrics_computed": [],
        "precision_and_recall": (
            "NOT CLAIMED and NOT COMPUTED. No engineering label exists yet; the label "
            "columns are emitted empty."),
        "adjudicator": cfg["governance"]["adjudicator"],
        "workbooks": workbooks,
    })

    print(f"\nkey withheld: task4_queue_key.parquet ({len(key)} rows)")
    print(f"worklist    : task4_worklist.xlsx ({len(work)} findings, severity-ordered)")
    print("\nNO LABELS INVENTED. NO METRICS COMPUTED.")
    print(f"artifacts: {run_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
