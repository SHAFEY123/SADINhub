"""Model 3, stage 3 — Model 1 cross-check. Runs ONLY after all scoring is complete.

Usage:
    python src/model3_triage/run_crosscheck.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK, write_run_metadata  # noqa: E402
from model3_triage.config import load_config  # noqa: E402
from model3_triage.crosscheck import (  # noqa: E402
    base_rates, build_crosscheck, list_c, overlap_and_lift,
)


def _latest(pattern: str) -> Path:
    """Newest run directory matching a glob. The pattern is passed through verbatim so a
    caller can exclude design directories (model1_2* matches runs, not model1_design_*)."""
    runs = sorted((ML_WORK / "outputs").glob(pattern))
    if not runs:
        raise FileNotFoundError(f"no directory matching {pattern!r} under outputs/")
    return runs[-1]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scores", type=Path, default=None)
    ap.add_argument("--model1", type=Path, default=None)
    args = ap.parse_args(argv)

    cfg = load_config()
    score_dir = args.scores or _latest("model3_2*")
    m1_dir = args.model1 or _latest("model1_2*")
    print(f"model 3 scores : {score_dir.name}")
    print(f"model 1 frozen : {m1_dir.name}\n")

    scores = pd.read_parquet(score_dir / "model3_scores.parquet")
    m1_meta = json.loads((m1_dir / "run_metadata.json").read_text(encoding="utf-8"))
    if "FROZEN" not in str(m1_meta.get("model1_status", "")):
        raise RuntimeError(
            f"Model 1 run {m1_dir.name} is not frozen; refusing to cross-check against it")
    events = pd.read_parquet(m1_dir / "anomaly_events.parquet")

    cc = build_crosscheck(scores, events, cfg)
    rates = base_rates(cc, cfg)
    lift = overlap_and_lift(cc, cfg)

    cc.to_parquet(score_dir / "model3_model1_crosscheck.parquet", index=False)
    rates.to_csv(score_dir / "model3_base_rates.csv", index=False)
    lift.to_csv(score_dir / "model3_overlap_lift.csv", index=False)

    lists = []
    for n in cfg["ranking"]["top_n"]:
        c = list_c(cc, n).assign(list_name=f"C_unexplained_top{n}")
        lists.append(c)
    list_c_all = pd.concat(lists, ignore_index=True)
    list_c_all.to_csv(score_dir / "model3_list_c_unexplained.csv", index=False)

    print("=== Model 1 base rates over the Model 3 SCORED universe ===")
    print(rates.to_string(index=False, float_format=lambda v: f"{v:.2f}"))
    print("\n=== overlap, lift and permutation null ===")
    show = ["n", "population", "base_rate_pct", "overlap_pct", "lift",
            "null_p95_pct", "observed_above_null_p95", "empirical_p_value"]
    print(lift[show].to_string(index=False, float_format=lambda v: f"{v:.3f}"))

    print("\n=== List C: unexplained items (same meter, same Saudi day) ===")
    for n in cfg["ranking"]["top_n"]:
        sub = list_c(cc, n)
        print(f"  top-{n:<4d} unexplained: {len(sub):>3d} of {n}  "
              f"({100*len(sub)/n:5.1f}%)")

    write_run_metadata(score_dir, {
        "task": "Model 3 stage 3 - Model 1 cross-check (runs AFTER all scoring)",
        "model3_scores": str(score_dir),
        "model1_frozen_run": str(m1_dir),
        "model1_status": m1_meta.get("model1_status"),
        "explains_definition": (
            "A Model 3 item is explained only when the SAME (meter_label, day_saudi) "
            "carries a Model 1 event with event_class='ELECTRICAL_FAULT' and "
            "commissioning=False. Judged per meter-day, never facility-wide. "
            "COMMISSIONING and DATA_AVAILABILITY events are joined and shown as context "
            "but never count as an explanation."),
        "scored_universe": int(len(cc)),
        "base_rates": rates.to_dict("records"),
        "overlap_and_lift": lift.to_dict("records"),
        "list_c_counts": {f"top{n}": int(len(list_c(cc, n)))
                          for n in cfg["ranking"]["top_n"]},
        "zone13_register_caveat": (
            "Model 1's T5 register family runs on 29 meters, excluding Zone 13. For a Zone "
            "13 meter-day, 'no T5 event' means T5 did not evaluate that meter, not that it "
            "found nothing. Flagged as m1_register_family_in_scope."),
        "interpretation": (
            "Agreement is CONCORDANCE, not precision. Neither model has engineering labels. "
            "Lift of 1.0 is chance. Disagreement in either direction is an output, not a "
            "failure, and no Model 3 parameter or feature set was selected by maximising "
            "lift."),
        "precision_and_recall": "NOT CLAIMED.",
    }, filename="run_metadata_crosscheck.json")
    print(f"\nartifacts added to {score_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
