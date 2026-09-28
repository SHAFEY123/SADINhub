"""Model 2 — build and validate the pooled feature table. NO MODEL IS TRAINED.

Produces the feature table, the transformation-count funnel and the per-meter split counts,
so the design can be reviewed before any model exists.

Usage:
    python src/model2_forecaster/run_feature_design.py [--profile <daily_consumption_profile_v2.csv>]
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, new_run_dir, write_run_metadata  # noqa: E402
from db import connection_facts, readonly_connection  # noqa: E402
from meters import load_meter_static  # noqa: E402
from model2_forecaster.evaluation import (  # noqa: E402
    MIN_EVAL_OBS, MIN_TRAIN_OBS, RESERVED_WINDOW, WINDOWS,
    per_meter_counts, split_for_window, windows_are_disjoint_and_ordered,
)
from model2_forecaster.features import (  # noqa: E402
    SCHEMA, build_feature_table, transformation_counts,
)


def _latest_profile() -> Path:
    hits = sorted((ML_WORK / "outputs").glob("task0b_*/daily_consumption_profile_v2.csv"))
    if not hits:
        raise FileNotFoundError("no Task 0B profile found; run run_daily_profile.py first")
    return hits[-1]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", type=Path, default=None)
    args = ap.parse_args(argv)

    profile_path = args.profile or _latest_profile()
    run_dir = new_run_dir("model2_design")
    print(f"profile input: {profile_path}")
    print(f"run directory: {run_dir}\n")

    profile = pd.read_csv(profile_path, parse_dates=["reading_date_saudi"])

    with readonly_connection() as conn:
        facts = connection_facts(conn)
        static = load_meter_static(conn)
    print(f"static covariates for {len(static)} meters "
          f"(zone_name from gold.zone, cb_max_rating_a from silver.dim_meter_cb_rating)")

    table = build_feature_table(profile, static)
    counts = transformation_counts(profile, table)

    feature_path = run_dir / "model2_feature_table.parquet"
    table.to_parquet(feature_path, index=False)
    eligible = table.loc[table["is_eligible"]]

    per_meter = per_meter_counts(table)
    per_meter.to_csv(run_dir / "model2_split_counts_by_meter.csv", index=False)

    split_summary = {}
    for name in WINDOWS:
        s = split_for_window(table, name)
        split_summary[name] = {
            "window": list(WINDOWS[name]),
            "train_rows": int(len(s["train"])),
            "eval_rows": int(len(s["eval"])),
            "train_meters": int(s["train"]["meter_label"].nunique()),
            "eval_meters": int(s["eval"]["meter_label"].nunique()),
            "train_max_target_date": str(s["train"]["target_date_saudi"].max().date())
                if len(s["train"]) else None,
            "eval_min_target_date": str(s["eval"]["target_date_saudi"].min().date())
                if len(s["eval"]) else None,
            "meters_meeting_both_minimums": int(
                per_meter.loc[per_meter["window"] == name, "usable"].sum()),
        }

    # Facility-wide blackout days: calendar dates where NO meter has an eligible row. These
    # are real outages, correctly excluded rather than zero-filled, but they thin an
    # evaluation window and must not be discovered later by surprise.
    per_date = eligible.groupby("target_date_saudi").size()
    all_dates = pd.date_range(table["target_date_saudi"].min(),
                              table["target_date_saudi"].max(), freq="D")
    blackout = sorted(set(all_dates) - set(per_date.index))
    blackout_by_window = {}
    for name in WINDOWS:
        start, end = pd.Timestamp(WINDOWS[name][0]), pd.Timestamp(WINDOWS[name][1])
        days = [d for d in blackout if start <= d <= end]
        blackout_by_window[name] = {
            "window_length_days": int((end - start).days) + 1,
            "days_with_no_eligible_row": len(days),
            "first": str(days[0].date()) if days else None,
            "last": str(days[-1].date()) if days else None,
        }

    unusable = per_meter.loc[~per_meter["usable"], ["window", "meter_label",
                                                    "n_train", "n_eval"]]

    checks = {
        "windows_disjoint_and_ordered": windows_are_disjoint_and_ordered(),
        "no_train_row_reaches_into_its_window": all(
            split_for_window(table, n)["train"]["target_date_saudi"].max()
            < pd.Timestamp(WINDOWS[n][0]) for n in WINDOWS),
        "all_29_meters_present": counts["meters"] == 29,
        "eligible_rows_have_no_nulls": bool(
            eligible[["lag_1", "lag_7", "lag_14", "roll_mean_7", "roll_std_7",
                      "target_kwh"]].notna().all().all()),
        "no_negative_targets": bool((eligible["target_kwh"] >= 0).all()),
        "issue_date_is_target_minus_one_day": bool(
            ((table["target_date_saudi"] - table["issue_date_saudi"])
             == pd.Timedelta(days=1)).all()),
    }

    metadata = {
        "task": "Model 2 - feature and evaluation design (NO MODEL TRAINED)",
        "run_directory": str(run_dir),
        "inputs": {
            "daily_profile": str(profile_path),
            "static_covariates": ["gold.meter", "gold.zone", "silver.dim_meter_cb_rating"],
            "boundary_exception": (
                "cb_max_rating_a is exposed by no Gold view, so Model 2 reads "
                "silver.dim_meter_cb_rating directly, read-only."),
        },
        "connection": facts,
        "forecasting_contract": {
            "issue_time": "close of Saudi day D (D 21:00:00 UTC)",
            "target": "total validated consumption for Saudi day D+1",
            "lag_1_meaning": "consumption of day D, i.e. target date minus one calendar day",
            "row_key": ["energy_meter_key", "target_date_saudi"],
        },
        "feature_schema": [
            {"column": c, "dtype": t, "definition": d} for c, t, d in SCHEMA],
        "transformation_counts": counts,
        "splits": split_summary,
        "minimums": {"min_train_obs": MIN_TRAIN_OBS, "min_eval_obs": MIN_EVAL_OBS},
        "reserved_window": RESERVED_WINDOW,
        "reserved_window_policy": (
            "final-test OUTCOMES AND PERFORMANCE are not used for model selection, feature "
            "selection, hyperparameter tuning or threshold selection. The window is "
            "inspected structurally (eligible row counts, date coverage); it is its "
            "performance that is reserved, not its existence."),
        "design_findings": {
            "facility_wide_blackout_days": blackout_by_window,
            "blackout_note": (
                "Calendar dates on which no meter has an eligible row. Verified as a real "
                "facility-wide telemetry outage (2026-02-03 to 2026-02-18, all 29 meters), "
                "correctly excluded by the Task 0B screen rather than zero-filled. Its "
                "effect is to thin validation_1, which loses 16 of its 60 days."),
            "meters_below_minimums": unusable.to_dict("records"),
            "minimums_note": (
                "A meter/window pair below either minimum is not eligible for a promotion "
                "decision in that window. ZN.17-PB falls short on training observations in "
                "validation_1 as a direct consequence of its 201-day gap "
                "(2025-05-18 to 2025-12-05); it qualifies in validation_2 and final_test."),
            "selection_recommendation": (
                "Decide promotion on validation_1 and validation_2 pooled rather than on "
                "validation_1 alone: after the outage its median is 30 evaluation "
                "observations per meter against 53 for validation_2."),
        },
        "checks": checks,
        "all_checks_passed": all(checks.values()),
        "models_trained": [],
    }
    meta_path = write_run_metadata(run_dir, metadata)

    print("=== transformation funnel ===")
    for k, v in counts.items():
        print(f"  {k:<38s} {v:>8,}")
    print("\n=== splits (eligible rows) ===")
    for name, s in split_summary.items():
        tag = "  [RESERVED]" if name == RESERVED_WINDOW else ""
        print(f"  {name:<14s} {WINDOWS[name][0]} .. {WINDOWS[name][1]}{tag}")
        print(f"      train {s['train_rows']:>6,} rows (to {s['train_max_target_date']})   "
              f"eval {s['eval_rows']:>5,} rows (from {s['eval_min_target_date']})")
        print(f"      meters meeting both minimums: "
              f"{s['meters_meeting_both_minimums']}/29")
    print("\n=== checks ===")
    for k, v in checks.items():
        print(f"  {'PASS' if v else 'FAIL'}  {k}")
    print(f"\nfeature table: {feature_path}")
    print(f"metadata     : {meta_path}")
    print("\nNO MODEL TRAINED - design and validation only.")
    return 0 if metadata["all_checks_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
