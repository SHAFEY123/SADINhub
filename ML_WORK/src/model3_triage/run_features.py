"""Model 3, stage 1 — build and reconcile the daily feature table. NOTHING IS FITTED.

Raw Gold only. No Task 0A/0B artifact and no Model 1 artifact is opened at any point.

Usage:
    python src/model3_triage/run_features.py
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import new_run_dir, write_run_metadata  # noqa: E402
from db import connection_facts, readonly_connection  # noqa: E402
from model3_triage.config import config_fingerprint, load_config  # noqa: E402
from model3_triage.features import (  # noqa: E402
    SCOPE_SQL, build_feature_table, fetch_daily_counts, mark_scorable, reconcile,
    validate_ranges,
)


def coverage_report(d: pd.DataFrame) -> pd.DataFrame:
    q = [0.01, 0.05, 0.25, 0.5, 0.75, 0.95, 0.99]
    rows = []
    for label, sub in (("all_meters", d), ("zone13", d[d.is_zone13]),
                       ("non_zone13", d[~d.is_zone13]),
                       ("scored_universe", d[d.scorable])):
        if sub.empty:
            continue
        r = {"population": label, "meter_days": len(sub),
             "meters": sub["meter_label"].nunique(),
             "dates": sub["day_saudi"].nunique(),
             "mean_readings": round(float(sub["readings_reported"].mean()), 2)}
        r.update({f"p{int(x*100):02d}_readings": int(sub["readings_reported"].quantile(x))
                  for x in q})
        for t in (10, 50, 100, 200, 250):
            r[f"days_below_{t}_readings"] = int((sub["readings_reported"] < t).sum())
        rows.append(r)
    return pd.DataFrame(rows)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    run_dir = new_run_dir("model3_features")
    print(f"run directory: {run_dir}\n")

    with readonly_connection() as conn:
        facts = connection_facts(conn)
        with conn.cursor() as cur:
            cur.execute(SCOPE_SQL)
            total_readings = int(cur.fetchone()[0])
        print(f"gold.energy_raw readings: {total_readings:,}")
        counts = fetch_daily_counts(conn, cfg)
    print(f"daily counters: {len(counts):,} meter-days\n")

    table = build_feature_table(counts, cfg)
    table = mark_scorable(table, cfg)

    rec = reconcile(table, cfg, total_readings)
    ranges = validate_ranges(table, cfg)

    print("=== reconciliation ===")
    for name, v in rec["checks"].items():
        print(f"  {v['result']}  {name:<32s} {str(v['actual']):>14s} "
              f"(expected {v['expected']})")
    print(f"\n  calendar span days              : {rec['calendar_span_days']}")
    print(f"  dates with no meter reporting   : {rec['dates_with_no_meter_reporting']}")
    print(f"  missing interior meter-days     : {rec['missing_interior_days']:,}")
    print(f"  missing meter-days total        : {rec['missing_meter_days_total']:,}")
    print(f"  warm-up meter-days excluded     : {rec['warmup_meter_days_excluded']:,}")
    print(f"  warm-up dates excluded          : {rec['warmup_dates_excluded']}")

    print("\n=== feature ranges ===")
    print(f"  all bounded rates within [0,1] : {ranges['all_bounded_rates_in_unit_interval']}")
    print(f"  all fitted values finite       : {ranges['all_fitted_values_finite']}")
    for col, v in ranges["unbounded_observed"].items():
        note = ""
        if v["n_above_1"]:
            note = f"  <- exceeds 1 on {v['n_above_1']:,} meter-days (expected, not clipped)"
        if v["n_below_0"]:
            note += f"  <- negative on {v['n_below_0']:,} (expected for a deviation)"
        print(f"    {col:<34s} [{v['min']:+.4f}, {v['max']:+.4f}]{note}")

    feature_path = run_dir / "model3_feature_table.parquet"
    table.to_parquet(feature_path, index=False)
    coverage = coverage_report(table)
    coverage.to_csv(run_dir / "model3_coverage_report.csv", index=False)

    # The artifact must be free of any Model 1 column, by construction and by assertion.
    leaked = [c for c in table.columns if c.lower().startswith(("m1_", "model1"))]
    if leaked:
        raise RuntimeError(f"Model 1 columns leaked into the feature table: {leaked}")

    write_run_metadata(run_dir, {
        "task": "Model 3 stage 1 - daily feature table (NOTHING FITTED)",
        "run_directory": str(run_dir),
        "connection": facts,
        "config": config_fingerprint(cfg),
        "sources": ["gold.energy_raw", "gold.meter", "gold.zone",
                    "silver.dim_meter_cb_rating"],
        "reads_task0a_or_0b": False,
        "reads_model1": False,
        "model1_columns_present": [],
        "reconciliation": rec,
        "feature_ranges": ranges,
        "feature_columns_fitted_tier1": cfg["features"]["tier1"],
        "feature_columns_tier2_sensitivity_only": cfg["features"]["tier2"],
        "range_policy": (
            "Only genuine rates (numerator a subset of denominator) are constrained to "
            "[0,1]. coverage_ratio may exceed 1 because its denominator is the facility "
            "median; mean_load_pct_cb may exceed 100 and is NEVER clipped; *_dev28 may be "
            "negative. The only universal constraint on fitted values is finiteness."),
        "precision_and_recall": (
            "NOT CLAIMED. Model 3 produces a ranking for human review, never a verdict, and "
            "no engineering labels exist against which any accuracy could be measured."),
        "models_fitted": [],
    })
    print(f"\nfeature table: {feature_path}")
    print(f"rows {len(table):,}  scorable {int(table['scorable'].sum()):,}")
    print("\nNOTHING FITTED - stage 1 only.")
    return 0 if (rec["all_passed"] and ranges["all_bounded_rates_in_unit_interval"]
                 and ranges["all_fitted_values_finite"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
