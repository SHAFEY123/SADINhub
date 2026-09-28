"""Model 3, stage 2 — fit and score. NO MODEL 1 ARTIFACT IS OPENED IN THIS STAGE.

Reads only the stage-1 feature table, which is itself free of any Model 1 column. The
Model 1 cross-check is a separate stage that runs afterwards, so circularity is prevented
by process rather than by discipline.

Usage:
    python src/model3_triage/run_model3.py
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, new_run_dir, write_run_metadata  # noqa: E402
from model3_triage.config import config_fingerprint, load_config  # noqa: E402
from model3_triage.features import validate_ranges  # noqa: E402
from model3_triage.scoring import (  # noqa: E402
    SCORE_COLUMNS, order, per_meter_top, rank_agreement, score_all_days, top_n,
)


def latest_feature_table() -> Path:
    runs = sorted((ML_WORK / "outputs").glob("model3_features_*"))
    if not runs:
        raise FileNotFoundError("no Model 3 feature run found; run run_features.py first")
    return runs[-1] / "model3_feature_table.parquet"


def distributions(scores: pd.DataFrame) -> pd.DataFrame:
    q = [0.01, 0.25, 0.5, 0.75, 0.9, 0.99, 1.0]
    rows = []
    for col in SCORE_COLUMNS:
        r = {"score": col, "mean": float(scores[col].mean()),
             "std": float(scores[col].std(ddof=1)),
             "n_distinct": int(scores[col].nunique())}
        r.update({f"p{int(x*100):02d}": float(scores[col].quantile(x)) for x in q})
        rows.append(r)
    return pd.DataFrame(rows)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    ap.add_argument("--features", type=Path, default=None)
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    feature_path = args.features or latest_feature_table()
    run_dir = new_run_dir("model3")
    print(f"feature table : {feature_path}")
    print(f"run directory : {run_dir}\n")

    table = pd.read_parquet(feature_path)
    leaked = [c for c in table.columns if c.lower().startswith(("m1_", "model1"))]
    if leaked:
        raise RuntimeError(f"Model 1 columns present in the feature table: {leaked}")

    ranges = validate_ranges(table, cfg)
    if not ranges["all_fitted_values_finite"]:
        raise RuntimeError(f"non-finite fitted values: {ranges['non_finite']}")
    if not ranges["all_bounded_rates_in_unit_interval"]:
        bad = [k for k, v in ranges["bounded_ok"].items() if not v]
        raise RuntimeError(f"rate features outside [0,1]: {bad}")
    print(f"pre-fit validation: bounded rates OK, all fitted values finite\n")

    tier1 = list(cfg["features"]["tier1"])
    tier12 = tier1 + list(cfg["features"]["tier2"])

    print(f"=== canonical Tier 1 ({len(tier1)} features) ===")
    scores1 = score_all_days(table, tier1, cfg)
    print(f"  scored {len(scores1):,} meter-days across "
          f"{scores1['day_saudi'].nunique()} Saudi dates\n")

    print(f"=== sensitivity variant Tier 1+2 ({len(tier12)} features) ===")
    scores12 = score_all_days(table, tier12, cfg)
    print(f"  scored {len(scores12):,} meter-days\n")

    print("=== deterministic rerun check (canonical Tier 1, refitted from scratch) ===")
    rerun = score_all_days(table, tier1, cfg, progress_every=0)
    identical = scores1.equals(rerun)
    max_delta = float(np.abs(
        scores1["raw_score"].to_numpy() - rerun["raw_score"].to_numpy()).max())
    print(f"  byte-identical frames : {identical}")
    print(f"  max |raw_score delta| : {max_delta:.3e}\n")

    ordered = order(scores1, cfg)
    ordered.to_parquet(run_dir / "model3_scores.parquet", index=False)
    order(scores12, cfg).to_parquet(
        run_dir / "model3_scores_tier12_sensitivity.parquet", index=False)

    lists = []
    for n in cfg["ranking"]["top_n"]:
        t = top_n(ordered, n).assign(list_name=f"A_top{n}", rank=range(1, n + 1))
        lists.append(t)
    per_meter = per_meter_top(ordered, int(cfg["ranking"]["per_meter_top_n"]))
    per_meter = per_meter.assign(list_name="B_per_meter")
    pd.concat(lists + [per_meter], ignore_index=True).to_csv(
        run_dir / "model3_review_lists.csv", index=False)

    agreement = [rank_agreement(ordered, order(scores12, cfg), n)
                 for n in cfg["ranking"]["top_n"]]
    pd.DataFrame(agreement).to_csv(run_dir / "model3_tier_sensitivity.csv", index=False)

    dist = distributions(ordered)
    dist.to_csv(run_dir / "model3_score_distributions.csv", index=False)

    saturated = int((ordered["window_anomaly_pct"] >= 1.0).sum())
    daily_winners = int((ordered["daily_rank_pct"] >= 1.0).sum())

    write_run_metadata(run_dir, {
        "task": "Model 3 stage 2 - Isolation Forest fitting and scoring",
        "run_directory": str(run_dir),
        "feature_table": str(feature_path),
        "config": config_fingerprint(cfg),
        "reads_model1": False,
        "reads_task0a_or_0b": False,
        "canonical_feature_set": "tier1",
        "tier1_features": tier1,
        "tier2_sensitivity_features": cfg["features"]["tier2"],
        "scored_meter_days": int(len(ordered)),
        "scored_dates": int(ordered["day_saudi"].nunique()),
        "first_scored_date": str(ordered["day_saudi"].min().date()),
        "last_scored_date": str(ordered["day_saudi"].max().date()),
        "train_rows_min": int(ordered["n_train_rows"].min()),
        "train_rows_max": int(ordered["n_train_rows"].max()),
        "train_dates_min": int(ordered["n_train_dates"].min()),
        "train_dates_max": int(ordered["n_train_dates"].max()),
        "deterministic_rerun_identical": bool(identical),
        "deterministic_rerun_max_raw_score_delta": max_delta,
        "window_anomaly_pct_saturated_at_1": saturated,
        "daily_rank_pct_equal_1": daily_winners,
        "score_distributions": dist.to_dict("records"),
        "tier_sensitivity": agreement,
        "ranking_policy": (
            "window_anomaly_pct is the PRIMARY cross-refit historical ranking score. "
            "window_anomaly_z is a DETERMINISTIC SECONDARY TIE-BREAK ONLY, for equal "
            "percentiles and above all for the 1.0 saturation point. It is not a "
            "calibrated probability, not a confidence, and not an independent anomaly "
            "measure. daily_rank_pct is comparable only WITHIN a Saudi day and is never "
            "used for historical ranking."),
        "calibration_note": (
            "window_anomaly_pct is an empirical percentile against each forest's own "
            "training-score distribution, which is scored IN SAMPLE. It is a calibration "
            "reference, not a performance estimate."),
        "contamination_note": (
            "contamination='auto' sets a decision threshold that Model 3 never uses, "
            "because predict() is never called. It is NOT an estimate of fault prevalence."),
        "precision_and_recall": (
            "NOT CLAIMED. Model 3 produces a ranking for human review, never a verdict. No "
            "engineering labels exist, so no precision, recall, accuracy or confirmed-fault "
            "detection can be or is asserted."),
    })

    print("=== score distributions ===")
    print(dist.to_string(index=False, float_format=lambda v: f"{v:.4f}"))
    print(f"\nwindow_anomaly_pct saturated at 1.0 : {saturated:,} of {len(ordered):,}")
    print(f"daily_rank_pct == 1.0               : {daily_winners:,} "
          f"(one per scored date)")
    print("\n=== Tier 1 vs Tier 1+2 ranking stability (sensitivity only) ===")
    print(pd.DataFrame(agreement).to_string(index=False))
    print(f"\nartifacts: {run_dir}")
    print("\nModel 1 has NOT been opened. Cross-check is a separate stage.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
