"""Model 2 — train, validate, then score the final test once.

Order is deliberate and enforced by the code path: every validation artifact is written to
disk BEFORE the final-test model is fitted. Final-test outcomes and performance are not used
for model selection, feature selection, hyperparameter tuning or threshold selection.

Usage:
    python src/model2_forecaster/run_model2.py
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
from db import connection_facts, readonly_connection  # noqa: E402
from meters import load_meter_static  # noqa: E402
from model2_forecaster.evaluation import (  # noqa: E402
    MIN_EVAL_OBS, MIN_TRAIN_OBS, SELECTION_WINDOWS, WINDOWS,
    classify_validation_evidence, paired_bootstrap_wape_delta, qualifying_windows,
    split_for_window, wape,
)
from model2_forecaster.features import build_feature_table, transformation_counts  # noqa: E402
from model2_forecaster.train import (  # noqa: E402
    BASELINES, FEATURES, PARAMS, QUANTILES, baseline_predictions, category_levels,
    fit_quantile_models, predict_quantiles,
)

MODEL_METHOD = "pooled_lgbm_p50"
# Raw model outputs are kept alongside the monotonic set and are never overwritten.
QUANTILE_COLUMNS = ["p10_raw", "p50_raw", "p90_raw",
                    "p10_monotonic", "p50_monotonic", "p90_monotonic",
                    "quantile_crossed", "clipped_at_zero"]
# Every reported interval and coverage figure uses the MONOTONIC set.
INTERVAL_LOW, INTERVAL_HIGH = "p10_monotonic", "p90_monotonic"
N_BOOT = 10_000
BLOCK = 7


def _latest_profile() -> Path:
    hits = sorted((ML_WORK / "outputs").glob("task0b_*/daily_consumption_profile_v2.csv"))
    if not hits:
        raise FileNotFoundError("no Task 0B profile found")
    return hits[-1]


def score_window(table: pd.DataFrame, name: str, categories: dict) -> pd.DataFrame:
    """Fit on rows strictly before the window, predict out-of-sample inside it."""
    split = split_for_window(table, name)
    train, evaluate = split["train"], split["eval"]
    if train.empty or evaluate.empty:
        return pd.DataFrame()

    models = fit_quantile_models(train, categories)
    q = predict_quantiles(models, evaluate, categories)

    rows = evaluate[["energy_meter_key", "meter_label", "issue_date_saudi",
                     "target_date_saudi", "target_kwh"]].copy()
    rows["window"] = name
    rows["n_train_rows_pooled"] = len(train)

    out = []
    model_rows = rows.copy()
    model_rows["method"] = MODEL_METHOD
    model_rows["prediction"] = q["p50_monotonic"].to_numpy()
    for col in QUANTILE_COLUMNS:
        model_rows[col] = q[col].to_numpy()
    out.append(model_rows)

    for method, preds in baseline_predictions(evaluate).items():
        b = rows.copy()
        b["method"] = method
        b["prediction"] = preds
        for col in QUANTILE_COLUMNS:
            b[col] = False if col in ("quantile_crossed", "clipped_at_zero") else np.nan
        out.append(b)

    return pd.concat(out, ignore_index=True)


def metrics_by_meter(backtest: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (window, method, meter), g in backtest.groupby(
            ["window", "method", "meter_label"], sort=True):
        actual, pred = g["target_kwh"].to_numpy(float), g["prediction"].to_numpy(float)
        rec = {
            "window": window, "method": method, "meter_label": meter,
            "n_observations": len(g),
            "wape_pct": 100 * wape(actual, pred),
            "mae_kwh": float(np.abs(actual - pred).mean()),
            "total_actual_kwh": float(actual.sum()),
        }
        if method == MODEL_METHOD:
            inside = ((actual >= g[INTERVAL_LOW].to_numpy(float))
                      & (actual <= g[INTERVAL_HIGH].to_numpy(float)))
            rec["p10_p90_coverage_pct"] = 100 * float(inside.mean())
            rec["quantile_crossing_pct"] = 100 * float(g["quantile_crossed"].mean())
            raw_in = ((actual >= g["p10_raw"].to_numpy(float))
                      & (actual <= g["p90_raw"].to_numpy(float)))
            rec["p10_p90_coverage_pct_raw"] = 100 * float(raw_in.mean())
        rows.append(rec)
    return pd.DataFrame(rows)


def aggregate_metrics(backtest: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (window, method), g in backtest.groupby(["window", "method"], sort=True):
        actual, pred = g["target_kwh"].to_numpy(float), g["prediction"].to_numpy(float)
        rec = {"window": window, "method": method, "n_observations": len(g),
               "wape_pct": 100 * wape(actual, pred),
               "mae_kwh": float(np.abs(actual - pred).mean())}
        if method == MODEL_METHOD:
            inside = ((actual >= g[INTERVAL_LOW].to_numpy(float))
                      & (actual <= g[INTERVAL_HIGH].to_numpy(float)))
            rec["p10_p90_coverage_pct"] = 100 * float(inside.mean())
            raw_in = ((actual >= g["p10_raw"].to_numpy(float))
                      & (actual <= g["p90_raw"].to_numpy(float)))
            rec["p10_p90_coverage_pct_raw"] = 100 * float(raw_in.mean())
        rows.append(rec)
    return pd.DataFrame(rows)


def validation_bootstrap(table: pd.DataFrame, backtest: pd.DataFrame) -> pd.DataFrame:
    """Per meter, pooling ONLY the validation windows that meet both minimums for it."""
    rows = []
    for meter in sorted(backtest["meter_label"].unique()):
        windows = qualifying_windows(table, meter)
        if not windows:
            rows.append({"meter_label": meter, "qualifying_windows": "",
                         "n_observations": 0,
                         "excluded_reason": "no validation window met both minimums"})
            continue

        sel = backtest.loc[
            backtest["meter_label"].eq(meter) & backtest["window"].isin(windows)]
        model = sel.loc[sel["method"] == MODEL_METHOD].sort_values(
            ["window", "target_date_saudi"])
        base = sel.loc[sel["method"] == "previous_day"].sort_values(
            ["window", "target_date_saudi"])
        assert (model["target_date_saudi"].to_numpy()
                == base["target_date_saudi"].to_numpy()).all()

        boot = paired_bootstrap_wape_delta(
            model["target_kwh"].to_numpy(float),
            model["prediction"].to_numpy(float),
            base["prediction"].to_numpy(float),
            n_boot=N_BOOT, block=BLOCK,
            segments=model["window"].to_numpy(),
        )
        verdict = classify_validation_evidence(boot, margin_pp=2.0)
        rows.append({
            "meter_label": meter,
            "undefined_reason": verdict.get("undefined_reason", ""),
            "qualifying_windows": "+".join(windows),
            "n_windows_qualified": len(windows),
            "n_observations": boot["n_observations"],
            "previous_day_wape_pct": 100 * boot["wape_baseline"],
            "pooled_model_wape_pct": 100 * boot["wape_model"],
            "improvement_pp": verdict["delta_observed_pp"],
            "ci_low_pp": verdict["delta_ci_low_pp"],
            "ci_high_pp": verdict["delta_ci_high_pp"],
            "one_sided_lower_pp": verdict["delta_one_sided_lower_pp"],
            "prob_model_better": verdict["prob_model_better"],
            "statistically_supported_improvement":
                verdict["statistically_supported_improvement"],
            "strong_practical_improvement": verdict["strong_practical_improvement"],
            "status": verdict["status"],
        })
    return pd.DataFrame(rows)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", type=Path, default=None)
    args = ap.parse_args(argv)

    profile_path = args.profile or _latest_profile()
    run_dir = new_run_dir("model2")
    print(f"profile input: {profile_path}\nrun directory: {run_dir}\n")

    profile = pd.read_csv(profile_path, parse_dates=["reading_date_saudi"])
    with readonly_connection() as conn:
        facts = connection_facts(conn)
        static = load_meter_static(conn)

    table = build_feature_table(profile, static)
    counts = transformation_counts(profile, table)
    categories = category_levels(table)
    print(f"eligible feature rows: {counts['eligible_rows']:,}\n")

    # ---------------------------------------------------------------- VALIDATION PHASE
    print("=== validation phase ===")
    val_backtests = []
    for name in SELECTION_WINDOWS:
        print(f"  fitting for {name} ...", flush=True)
        val_backtests.append(score_window(table, name, categories))
    val_backtest = pd.concat(val_backtests, ignore_index=True)

    val_metrics = metrics_by_meter(val_backtest)
    val_aggregate = aggregate_metrics(val_backtest)
    print("\n  aggregate validation performance:")
    for r in val_aggregate.itertuples(index=False):
        cov = getattr(r, "p10_p90_coverage_pct", np.nan)
        cov_s = f"  coverage {cov:5.1f}%" if pd.notna(cov) else ""
        print(f"    {r.window:<14s} {r.method:<24s} n={r.n_observations:>5,}  "
              f"WAPE {r.wape_pct:6.2f}%  MAE {r.mae_kwh:7.2f}{cov_s}")

    boot = validation_bootstrap(table, val_backtest)

    # Freeze validation to disk before the final-test model is fitted.
    val_backtest.to_csv(run_dir / "validation_backtest_v2.csv", index=False)
    val_metrics.to_csv(run_dir / "validation_metrics_by_meter_v2.csv", index=False)
    boot.to_csv(run_dir / "validation_bootstrap_v2.csv", index=False)
    selection = boot[[
        "meter_label", "qualifying_windows", "n_observations", "undefined_reason",
        "previous_day_wape_pct", "pooled_model_wape_pct", "improvement_pp",
        "ci_low_pp", "ci_high_pp", "one_sided_lower_pp",
        "statistically_supported_improvement", "strong_practical_improvement", "status",
    ]].copy()
    selection.to_csv(run_dir / "model_selection_v2.csv", index=False)
    print("\n  validation artifacts written - selection rule is now frozen.")

    # ---------------------------------------------------------------- FINAL TEST, ONCE
    print("\n=== final test (scored once, nothing tuned afterwards) ===")
    test_backtest = score_window(table, "final_test", categories)
    test_metrics = metrics_by_meter(test_backtest)
    test_aggregate = aggregate_metrics(test_backtest)
    for r in test_aggregate.itertuples(index=False):
        cov = getattr(r, "p10_p90_coverage_pct", np.nan)
        cov_s = f"  coverage {cov:5.1f}%" if pd.notna(cov) else ""
        print(f"    {r.method:<24s} n={r.n_observations:>5,}  "
              f"WAPE {r.wape_pct:6.2f}%  MAE {r.mae_kwh:7.2f}{cov_s}")

    backtest = pd.concat([val_backtest, test_backtest], ignore_index=True)
    backtest.to_csv(run_dir / "forecast_backtest_v2.csv", index=False)
    pd.concat([val_metrics, test_metrics], ignore_index=True).to_csv(
        run_dir / "metrics_by_meter_v2.csv", index=False)

    coverage = pd.concat([val_metrics, test_metrics], ignore_index=True)
    coverage = coverage.loc[coverage["method"] == MODEL_METHOD, [
        "window", "meter_label", "n_observations",
        "p10_p90_coverage_pct", "p10_p90_coverage_pct_raw", "quantile_crossing_pct"]]
    coverage.to_csv(run_dir / "quantile_coverage_v2.csv", index=False)

    n_stat = int(boot["statistically_supported_improvement"].fillna(False).sum())
    n_prac = int(boot["strong_practical_improvement"].fillna(False).sum())

    metadata = {
        "task": "Model 2 - pooled quantile forecaster, training and validation",
        "run_directory": str(run_dir),
        "inputs": {"daily_profile": str(profile_path),
                   "static_covariates": ["gold.meter", "gold.zone",
                                         "silver.dim_meter_cb_rating"]},
        "connection": facts,
        "features": FEATURES,
        "quantiles": list(QUANTILES),
        "hyperparameters": PARAMS,
        "hyperparameter_policy": (
            "Fixed in advance. No search, no early stopping, no eval_set, so no evaluation "
            "window influenced them."),
        "baselines": BASELINES,
        "transformation_counts": counts,
        "rolling_window_rule": (
            "roll_mean_7 and roll_std_7 require all seven previous calendar days to be "
            "eligible (min_periods=7, roll_7_n_eligible == 7)."),
        "minimums": {"min_train_obs": MIN_TRAIN_OBS, "min_eval_obs": MIN_EVAL_OBS},
        "bootstrap": {"n_boot": N_BOOT, "block_days": BLOCK,
                      "paired": True, "segmented_by_window": True,
                      "blocks_cross_window_boundary": False},
        "validation_aggregate": val_aggregate.to_dict("records"),
        "final_test_aggregate": test_aggregate.to_dict("records"),
        "validation_summary": {
            "meters_evaluated": int(len(boot)),
            "statistically_supported_improvement": n_stat,
            "strong_practical_improvement_ge_2pp": n_prac,
        },
        "final_test_policy": (
            "final-test outcomes and performance are not used for model selection, feature "
            "selection, hyperparameter tuning or threshold selection. It was scored once, "
            "after every validation artifact had been written."),
        "promotion_status": (
            "NONE. These are validation findings only. No meter is production-promoted; the "
            "project has no formally defined absolute forecast acceptance criterion."),
    }
    write_run_metadata(run_dir, metadata)

    _write_summary(run_dir, val_aggregate, test_aggregate, boot, counts, n_stat, n_prac)
    print(f"\nartifacts: {run_dir}")
    return 0


def _write_summary(run_dir, val_agg, test_agg, boot, counts, n_stat, n_prac) -> None:
    def table(df):
        lines = ["| window | method | n | WAPE % | MAE kWh | P10-P90 coverage % |",
                 "|---|---|---:|---:|---:|---:|"]
        for r in df.itertuples(index=False):
            cov = getattr(r, "p10_p90_coverage_pct", np.nan)
            lines.append(f"| {r.window} | {r.method} | {r.n_observations:,} | "
                         f"{r.wape_pct:.2f} | {r.mae_kwh:.2f} | "
                         f"{'' if pd.isna(cov) else f'{cov:.1f}'} |")
        return "\n".join(lines)

    ranked = boot.dropna(subset=["improvement_pp"]).sort_values(
        "improvement_pp", ascending=False)
    per_meter = ["| meter | windows | n | prev-day WAPE % | model WAPE % | improvement pp | "
                 "95% CI pp | lower>0 | >=2pp |", "|---|---|---:|---:|---:|---:|---|---|---|"]
    for r in ranked.itertuples(index=False):
        per_meter.append(
            f"| {r.meter_label} | {r.qualifying_windows} | {r.n_observations:,} | "
            f"{r.previous_day_wape_pct:.2f} | {r.pooled_model_wape_pct:.2f} | "
            f"{r.improvement_pp:+.2f} | [{r.ci_low_pp:+.2f}, {r.ci_high_pp:+.2f}] | "
            f"{'yes' if r.statistically_supported_improvement else 'no'} | "
            f"{'yes' if r.strong_practical_improvement else 'no'} |")

    (run_dir / "results_summary_v2.md").write_text("\n".join([
        "# Model 2 — pooled quantile forecaster, validation results",
        "",
        "**Status: validation findings only. No meter is production-promoted.** The project",
        "has no formally defined absolute forecast acceptance criterion, so the two labels",
        "below describe historical validation behaviour and nothing more.",
        "",
        f"- Eligible feature rows: **{counts['eligible_rows']:,}** across 29 meters.",
        f"- Statistically supported improvement (95% lower bound > 0): **{n_stat} of 29**.",
        f"- Strong practical improvement (point >= 2pp): **{n_prac} of 29**.",
        "",
        "## Aggregate validation",
        "", table(val_agg), "",
        "## Final test — scored once, after validation was frozen",
        "",
        "Not used for model selection, feature selection, hyperparameter tuning or",
        "threshold selection.",
        "", table(test_agg), "",
        "## Per meter (pooled qualifying validation windows only)",
        "", "\n".join(per_meter), "",
        "Improvement is previous-day WAPE minus pooled-model WAPE, in percentage points;",
        "positive favours the model. Intervals come from a paired moving-block bootstrap",
        "(10,000 draws, 7-day blocks) segmented so no block crosses the validation_1 /",
        "validation_2 boundary, because those windows are scored by separately trained models.",
        "",
    ]), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
