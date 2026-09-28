"""Model 3 — corrected permutation null for the Model 1 cross-check.

CROSS-CHECK ONLY. This touches no score, no ranking, no Top-N list, no feature and no
fitted model. It reads the frozen cross-check artifact and adds a meter-preserving null
beside the original global one.

Usage:
    python src/model3_triage/run_null_correction.py
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, write_run_metadata  # noqa: E402
from model3_triage.config import load_config  # noqa: E402
from model3_triage.crosscheck import compare_nulls  # noqa: E402


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, default=None)
    args = ap.parse_args(argv)

    cfg = load_config()
    run_dir = args.run or sorted((ML_WORK / "outputs").glob("model3_2*"))[-1]
    print(f"model 3 run : {run_dir.name}\n")

    # Fingerprint the frozen scores so the report can state they were not altered.
    frozen = {name: _digest(run_dir / name) for name in
              ("model3_scores.parquet", "model3_scores_tier12_sensitivity.parquet",
               "model3_review_lists.csv", "model3_tier_sensitivity.csv")}

    cc = pd.read_parquet(run_dir / "model3_model1_crosscheck.parquet")
    table, meta = compare_nulls(cc, cfg)
    table.to_csv(run_dir / "model3_overlap_lift_corrected_null.csv", index=False)

    print("=== Top-N meter composition and observed clustering ===")
    for key, v in meta.items():
        print(f"  {key:<8s} meters {v['n_meters_in_top_n']:>2d}  "
              f"mean run {v['observed_mean_run_length_days']:.2f} days  "
              f"max {v['observed_max_run_length_days']}  "
              f"block used {v['block_length_used']}")

    show = ["n", "population", "observed_overlap_pct", "facility_base_rate_pct",
            "global_mean_pct", "global_p",
            "meter_preserving_iid_mean_pct", "meter_preserving_iid_p",
            "meter_preserving_block_mean_pct", "meter_preserving_block_p"]
    print("\n=== three nulls, p = (exceedances + 1) / (B + 1) ===")
    print(table[show].to_string(index=False, float_format=lambda v: f"{v:.3f}"))

    alpha = 0.05
    flipped = table.loc[(table["global_p"] < alpha)
                        & (table["meter_preserving_block_p"] >= alpha)]
    print(f"\n=== populations significant under the GLOBAL null but NOT under the "
          f"meter-preserving block null (alpha={alpha}) ===")
    if flipped.empty:
        print("  none")
    else:
        print(flipped[["n", "population", "observed_overlap_pct", "global_p",
                       "meter_preserving_block_p"]].to_string(
            index=False, float_format=lambda v: f"{v:.4f}"))

    after = {name: _digest(run_dir / name) for name in frozen}
    unchanged = frozen == after

    write_run_metadata(run_dir, {
        "task": "Model 3 - corrected permutation null (CROSS-CHECK ONLY)",
        "model3_run": str(run_dir),
        "scores_and_rankings_altered": False,
        "frozen_artifact_digests_before": frozen,
        "frozen_artifact_digests_after": after,
        "frozen_artifacts_unchanged": unchanged,
        "n_permutations": int(cfg["crosscheck"]["n_permutations"]),
        "p_value_formula": "(exceedances + 1) / (B + 1)",
        "p_value_note": (
            "The +1 in both terms counts the observed statistic among the possible "
            "arrangements, so 10,000 permutations can never report p = 0 and claim more "
            "certainty than the draws support. The minimum reportable p is 1/10001 = "
            "9.999e-05."),
        "nulls": {
            "global": (
                "Uniform draws over the whole scored universe. Preserved as the original "
                "descriptive result. Ignores meter-level prevalence, so it mostly tests "
                "WHICH METERS were chosen rather than which days."),
            "meter_preserving_iid": (
                "Top-N meter composition held fixed; days re-drawn independently within "
                "each meter. Isolates the contribution of meter composition."),
            "meter_preserving_block": (
                "Top-N meter composition held fixed; days re-drawn in contiguous blocks "
                "whose length comes from the observed run length of consecutive selected "
                "dates, so consecutive days are not treated as independent."),
        },
        "top_n_composition": meta,
        "results": table.to_dict("records"),
        "not_used_for_tuning": (
            "This null was computed AFTER Model 3 was frozen and was not used to select "
            "any feature, parameter, window or threshold."),
        "precision_and_recall": "NOT CLAIMED.",
    }, filename="run_metadata_null_correction.json")

    print(f"\nfrozen Model 3 artifacts unchanged: {unchanged}")
    print(f"artifacts added to {run_dir}")
    return 0 if unchanged else 1


if __name__ == "__main__":
    raise SystemExit(main())
