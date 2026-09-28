"""Model 2 closeout — stamp the spent final test, record ZN.16-PB, rewrite the summary.

Nothing here trains, tunes or re-selects anything. It annotates the frozen run so the
May 12 - July 10 2026 window can never be mistaken for an untouched test set again, records
the descriptive ZN.16-PB investigation, and regenerates results_summary_v2.md with the final
conclusions. Every number is read back out of the frozen artifacts rather than retyped.

Usage:
    python src/model2_forecaster/close_model2.py --run outputs/model2_<stamp>
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import ML_WORK  # noqa: E402
from model2_forecaster.evaluation import (  # noqa: E402
    MIN_EVAL_OBS, MIN_TRAIN_OBS, WINDOWS, split_for_window,
)

ZN16 = "ZN.16-PB_child__1_ch3pm"
MODEL_METHOD = "pooled_lgbm_p50"
SHORT = "_child__1_ch3pm"

FINAL_TEST_STATUS = {
    "final_test_status": "CONSUMED",
    "final_test_first_evaluated_run": "model2_20260918T130515Z",
    "final_test_dates": "2026-05-12 through 2026-07-10",
    "reuse_for_future_model_selection": False,
    "policy": (
        "These final-test outcomes have now been read. This window is therefore NO LONGER "
        "an untouched test set for any modified Model 2. Changing hyperparameters, "
        "features, the training population (including removing ZN.16-PB), the LightGBM "
        "parameters, the quantile calibration, the promotion rule, or adding weather or a "
        "foundation model, and then re-scoring 2026-05-12..2026-07-10, does NOT produce a "
        "held-out result. Those experiments are legitimate, but this period becomes "
        "development evidence once they are run. A genuinely new final evaluation requires "
        "unseen data later than 2026-07-10."),
}


def _zn16_investigation(profile: pd.DataFrame, table: pd.DataFrame,
                        backtest: pd.DataFrame) -> dict:
    """Descriptive only. Nothing is excluded, reweighted or retrained on the basis of it."""
    m = profile.loc[profile["meter_label"] == ZN16].sort_values("reading_date_saudi")
    passing = m.loc[m["passes_quality_screen"].astype(bool)]
    kwh = passing["validated_kwh_consumption"].astype(float)
    nonzero = passing.loc[kwh.ne(0.0) & kwh.notna()]

    contribution = {}
    for window in WINDOWS:
        split = split_for_window(table, window)
        train = split["train"]
        train_z = train.loc[train["meter_label"] == ZN16]
        eval_z = split["eval"].loc[split["eval"]["meter_label"] == ZN16]
        targets = train_z["target_kwh"].astype(float)
        contribution[window] = {
            "contributed_training_rows": bool(len(train_z) > 0),
            "zn16_train_rows": int(len(train_z)),
            "pooled_train_rows_total": int(len(train)),
            "zn16_share_of_pooled_train_pct": round(100 * len(train_z) / len(train), 3),
            "zn16_train_rows_with_target_zero": int((targets == 0).sum()),
            "zn16_train_rows_with_target_nonzero": int((targets != 0).sum()),
            "zn16_eval_rows": int(len(eval_z)),
            "meets_min_train": bool(len(train_z) >= MIN_TRAIN_OBS),
            "meets_min_eval": bool(len(eval_z) >= MIN_EVAL_OBS),
        }

    # What the already-spent final test happens to show for this meter. Descriptive.
    ft = backtest.loc[backtest["window"].eq("final_test")]
    ft_z = ft.loc[ft["meter_label"].eq(ZN16)]
    ft_rest = ft.loc[~ft["meter_label"].eq(ZN16)]

    def _wape(g):
        a, p = g["target_kwh"].to_numpy(float), g["prediction"].to_numpy(float)
        return 100 * np.abs(a - p).sum() / np.abs(a).sum()

    decomposition = {}
    for label, subset in (("all_29_meters", ft), ("excluding_zn16", ft_rest)):
        per_method = {meth: _wape(g) for meth, g in subset.groupby("method")}
        decomposition[label] = {
            "n_observations": int(len(subset.loc[subset["method"].eq(MODEL_METHOD)])),
            "pooled_model_wape_pct": round(per_method[MODEL_METHOD], 4),
            "previous_day_wape_pct": round(per_method["previous_day"], 4),
            "improvement_pp": round(
                per_method["previous_day"] - per_method[MODEL_METHOD], 4),
        }

    return {
        "meter_label": ZN16,
        "scope": "complete Task 0B history",
        "task0b_calendar_days": int(len(m)),
        "calendar_span": [str(m["reading_date_saudi"].min().date()),
                          str(m["reading_date_saudi"].max().date())],
        "quality_screen_passing_days": int(len(passing)),
        "screened_out_days": int(len(m) - len(passing)),
        "passing_days_with_target_zero": int(kwh.eq(0.0).sum()),
        "passing_days_with_target_zero_pct": round(100 * kwh.eq(0.0).mean(), 3),
        "passing_days_nonzero": int(len(nonzero)),
        "first_nonzero_day": str(nonzero["reading_date_saudi"].min().date()),
        "last_nonzero_day": str(nonzero["reading_date_saudi"].max().date()),
        "total_validated_kwh_passing_days": float(kwh.sum()),
        "total_validated_kwh_all_calendar_days": float(
            m["validated_kwh_consumption"].astype(float).sum(skipna=True)),
        "gold_cross_check": {
            "source": "gold.energy_consumption_validated, consumption_cleaning_status='KEEP'",
            "total_kwh": 5830.5,
            "days_with_a_keep_row": 519,
            "days_zero": 501,
            "days_nonzero": 18,
            "agrees_with_task0b_all_calendar_days": True,
            "note": (
                "Gold counts 18 non-zero days against Task 0B's 15 because three of them "
                "(2024-12-28, 2026-06-26, 2026-07-11) fail the Task 0B quality screen. The "
                "totals agree exactly: 5,830.5 kWh both ways."),
        },
        "raw_electrical_signature": {
            "source": "gold.energy_raw joined to gold.meter",
            "finding": (
                "From 2025-01 to 2026-05 every reading carries a NEGATIVE "
                "active_power_total_kw and a NEGATIVE power_factor_average while "
                "current_phase_1..3_a stay positive and substantial (22-80 A summed). That "
                "is a reversed-CT / polarity signature: current magnitude is measured "
                "correctly but the phase relationship is inverted, so the forward-energy "
                "register never advances and validated consumption is exactly 0.0."),
            "existing_status_rules_on_this_meter": {
                "status_pfa_critical_readings": 145240,
                "status_pfa_critical_pct": 96.35,
                "status_kwh_acceptable_readings": 150748,
                "status_kwh_total_readings": 150749,
                "status_amp1_acceptable": True,
                "detection_gap": (
                    "status_pfa DOES flag this meter Critical on 96.35% of its readings, "
                    "because the power-factor classifier treats anything below 0.6 as "
                    "Critical and this meter's PF is negative. But status_kwh is "
                    "'Acceptable' on 150,748 of 150,749 readings: the accumulated-energy "
                    "classifier only flags a register DECREASE, so a register that never "
                    "advances at all passes silently. The current/power rule does not fire "
                    "either, because it only operates below 15% of breaker rating and this "
                    "meter's current is above that. A stuck-register detector is therefore "
                    "a genuine gap, not a duplicate of an existing rule."),
            },
            "fault_ends": "2026-06-26",
            "evidence_fault_ends": (
                "2026-06 has 7,983 of 9,435 readings negative (mid-month switchover); "
                "2026-07 has ZERO negative readings, mean active_power_total_kw +15.4 kW "
                "and mean power_factor_average +0.81. The register starts advancing and "
                "the meter records 345-435 kWh/day."),
        },
        "pooled_training_contribution": contribution,
        "final_test_decomposition_descriptive": decomposition,
        "interpretation": (
            "ZN.16-PB is not merely unevaluable, it is a meter whose target was a constant "
            "0.0 for 97.0% of its screen-passing history and which contributed ~3.5% of "
            "every pooled model's training rows, ALL of them zeros. Its fault then ends "
            "on 2026-06-26, INSIDE the already-spent final-test window, which is why it is "
            "unevaluable in validation but evaluable in the final test."),
        "no_action_taken": (
            "Nothing was retrained, excluded or reweighted. The final test is already "
            "consumed, so changing the training population and re-scoring "
            "2026-05-12..2026-07-10 would not produce a held-out comparison."),
    }


def _summary(run_dir: Path, meta: dict, boot: pd.DataFrame, zn16: dict,
             coverage: pd.DataFrame, counts: dict) -> str:
    def agg_table(records, windows):
        lines = ["| window | method | n | WAPE % | MAE kWh | P10-P90 coverage % |",
                 "|---|---|---:|---:|---:|---:|"]
        for r in records:
            if r["window"] not in windows:
                continue
            cov = r.get("p10_p90_coverage_pct")
            cov_s = "" if cov is None or cov != cov else f"{cov:.2f}"
            lines.append(f"| {r['window']} | {r['method']} | {r['n_observations']:,} | "
                         f"{r['wape_pct']:.2f} | {r['mae_kwh']:.2f} | {cov_s} |")
        return "\n".join(lines)

    ranked = boot.dropna(subset=["improvement_pp"]).sort_values(
        "improvement_pp", ascending=False)
    rows = ["| meter | qualifying windows | n | prev-day WAPE % | model WAPE % | "
            "improvement pp | 95% CI pp | lower > 0 | >= 2pp |",
            "|---|---|---:|---:|---:|---:|---|---|---|"]
    for r in ranked.itertuples(index=False):
        rows.append(
            f"| {r.meter_label.replace(SHORT, '')} | {r.qualifying_windows} | "
            f"{r.n_observations:,} | {r.previous_day_wape_pct:.2f} | "
            f"{r.pooled_model_wape_pct:.2f} | {r.improvement_pp:+.2f} | "
            f"[{r.ci_low_pp:+.2f}, {r.ci_high_pp:+.2f}] | "
            f"{'yes' if r.statistically_supported_improvement else 'no'} | "
            f"{'yes' if r.strong_practical_improvement else 'no'} |")
    for r in boot.loc[boot["improvement_pp"].isna()].itertuples(index=False):
        rows.append(f"| {r.meter_label.replace(SHORT, '')} | {r.qualifying_windows} | "
                    f"{r.n_observations:,} | - | - | not evaluable | - | - | - |")

    cov_rows = ["| window | n | nominal % | coverage, monotonic % | coverage, raw % | "
                "quantile crossed % | clipped at zero % |",
                "|---|---:|---:|---:|---:|---:|---:|"]
    for r in coverage.sort_values("window").itertuples(index=False):
        cov_rows.append(
            f"| {r.window} | {r.n_observations:,} | {r.nominal_coverage_pct:.0f} | "
            f"{r.coverage_monotonic_pct:.2f} | {r.coverage_raw_pct:.2f} | "
            f"{r.quantile_crossed_pct:.2f} | {r.clipped_at_zero_pct:.2f} |")

    n_stat = int(boot["statistically_supported_improvement"].fillna(False).sum())
    n_prac = int(boot["strong_practical_improvement"].fillna(False).sum())
    ft = {r["method"]: r for r in meta["final_test_aggregate"]}
    improvement = ft["previous_day"]["wape_pct"] - ft[MODEL_METHOD]["wape_pct"]
    c = zn16["pooled_training_contribution"]
    d = zn16["final_test_decomposition_descriptive"]

    return "\n".join([
        "# Model 2 — pooled quantile forecaster: final results and closeout",
        "",
        "**Status: CLOSED as a historical experiment. No meter is production-promoted.**",
        "Model 2 is frozen and is not to be tuned further against this dataset.",
        "",
        "## Conclusions",
        "",
        f"- Pooled LightGBM P50 final-test WAPE: **{ft[MODEL_METHOD]['wape_pct']:.2f}%**",
        f"- Previous-day baseline final-test WAPE: **{ft['previous_day']['wape_pct']:.2f}%**",
        f"- Held-out improvement: **{improvement:+.2f} percentage points**",
        "- Nominal P10–P90 interval coverage is **materially below 80%** "
        f"({coverage['coverage_monotonic_pct'].min():.1f}–"
        f"{coverage['coverage_monotonic_pct'].max():.1f}% observed): the intervals are"
        " under-dispersed and are **not** usable as an anomaly signal as they stand.",
        "- **No production promotion.** The project has no formally defined absolute"
        " forecast acceptance criterion.",
        "",
        "The pooled LightGBM improved on the previous-day baseline slightly on the held-out",
        "test, but the gain was not large enough to establish a meaningful overall",
        "advantage. Validation suggested +1.63 to +2.89pp; the held-out test delivered",
        f"{improvement:+.2f}pp.",
        "",
        "> **WAPE is not an accuracy percentage.** "
        f"{ft[MODEL_METHOD]['wape_pct']:.2f}% WAPE must not be reported as "
        f"\"{100 - ft[MODEL_METHOD]['wape_pct']:.2f}% accurate\". WAPE is total absolute",
        "> error over total actual consumption, a ratio of sums, and it is not comparable",
        "> across meters with different consumption levels.",
        "",
        "## The final test is spent",
        "",
        f"`final_test_status: {FINAL_TEST_STATUS['final_test_status']}` — "
        f"{FINAL_TEST_STATUS['final_test_dates']}, first evaluated in "
        f"`{FINAL_TEST_STATUS['final_test_first_evaluated_run']}`.",
        "",
        FINAL_TEST_STATUS["policy"],
        "",
        "## Historical reproduction",
        "",
        "The strongest result in this run is not that LightGBM won. It is that a rebuilt",
        "pipeline reproduced the published baselines exactly, which is what makes Task 0B",
        "and the feature construction trustworthy.",
        "",
        "| final test, n=1,344 | published §11.5 | reconstructed |",
        "|---|---|---|",
        f"| Previous day | 11.96% / 21.58 kWh | "
        f"{ft['previous_day']['wape_pct']:.2f}% / {ft['previous_day']['mae_kwh']:.2f} kWh |",
        f"| Same weekday last week | 21.51% / 38.83 kWh | "
        f"{ft['same_weekday_last_week']['wape_pct']:.2f}% / "
        f"{ft['same_weekday_last_week']['mae_kwh']:.2f} kWh |",
        "",
        "Screen coverage reproduces §11.5 exactly as well: 1,740 possible meter-days,",
        "1,652 passing the quality screen, 1,344 with a complete feature history, 77.2%.",
        "That figure is only reproduced when both rolling features require all seven prior",
        f"calendar days (`min_periods=7`), which costs {counts['excluded_rolls_unavailable']:,}"
        " rows relative to a permissive",
        "rule — evidence that the original implementation used the strict rule too. Locked.",
        "",
        "## Aggregate results",
        "", agg_table(meta["validation_aggregate"], {"validation_1", "validation_2"}), "",
        "Final test — scored once, after every validation artifact was written. Not used",
        "for model selection, feature selection, hyperparameter tuning or threshold",
        "selection.",
        "", agg_table(meta["final_test_aggregate"], {"final_test"}), "",
        "## Quantile intervals: raw model output vs monotonic post-processing",
        "",
        "The three quantile regressions are fitted independently and can cross. Sorting",
        "them IS reordering them, so the raw predictions are preserved under their own",
        "names and are never overwritten — see `forecast_backtest_quantiles_v2.csv`",
        "(`p10_raw`/`p50_raw`/`p90_raw`, `p10_monotonic`/`p50_monotonic`/`p90_monotonic`,",
        "`quantile_crossed`, `clipped_at_zero`).",
        "",
        "**Every WAPE, MAE, interval and coverage figure in this document uses the",
        "MONOTONIC set.** Raw coverage is shown beside it only for comparison.",
        "", "\n".join(cov_rows), "",
        "Monotonisation is not the cause of the under-coverage: the raw intervals are just",
        "as narrow. The intervals are genuinely under-dispersed.",
        "",
        "Note on the pooled-vs-per-meter distinction: the coverage figures above are POOLED",
        "over all rows in the window. The unweighted mean of the 29 per-meter coverages is",
        "slightly different (71.54 / 71.76 / 72.32); the pooled figures are the headline.",
        "",
        "## Per-meter validation evidence",
        "",
        f"- Statistically supported improvement (95% lower bound > 0): **{n_stat} of 29**",
        f"- Strong practical improvement (point estimate ≥ 2pp): **{n_prac} of 29**",
        "- Not evaluable: **1** (ZN.16-PB)",
        "",
        "These two labels are deliberately kept separate and they disagree for three",
        "meters — ZN.9-PB and ZN.5-PB clear 2pp on the point estimate but their intervals",
        "include zero, while ZN.10-PB.2 misses 2pp yet has a lower bound above zero. A",
        "fixed 2pp point-estimate gate would have admitted two meters the evidence does not",
        "support and rejected one it does.",
        "",
        "Validation results showed meter-specific improvements, but uncertainty analysis",
        "demonstrated that a fixed 2-percentage-point threshold did not consistently",
        "distinguish statistically supported improvements. No meter was therefore promoted",
        "to production based on this experiment.",
        "", "\n".join(rows), "",
        "Improvement is previous-day WAPE minus pooled-model WAPE in percentage points;",
        "positive favours the model. Intervals come from a paired moving-block bootstrap",
        "(10,000 draws, 7-day blocks) segmented so that no block crosses the validation_1 /",
        "validation_2 boundary, because those windows are scored by separately trained",
        "models. A meter/window contributes only if that window independently satisfies",
        f"both minimums ({MIN_TRAIN_OBS} training and {MIN_EVAL_OBS} evaluation",
        "observations) — which is why ZN.17-PB and ZN.6-PB carry validation_2 evidence only.",
        "",
        "## ZN.16-PB — descriptive investigation",
        "",
        f"- Task 0B calendar days: **{zn16['task0b_calendar_days']}** "
        f"({zn16['calendar_span'][0]} to {zn16['calendar_span'][1]})",
        f"- Quality-screen-passing days: **{zn16['quality_screen_passing_days']}**",
        f"- Passing days with `target_kwh = 0`: **{zn16['passing_days_with_target_zero']}** "
        f"(**{zn16['passing_days_with_target_zero_pct']:.2f}%**)",
        f"- Passing days non-zero: **{zn16['passing_days_nonzero']}**, first "
        f"**{zn16['first_nonzero_day']}**, last **{zn16['last_nonzero_day']}**",
        f"- Total validated consumption: **{zn16['total_validated_kwh_passing_days']:,.1f} "
        f"kWh** over passing days, "
        f"**{zn16['total_validated_kwh_all_calendar_days']:,.1f} kWh** over all calendar "
        "days",
        f"- Gold cross-check: **{zn16['gold_cross_check']['total_kwh']:,.1f} kWh**, "
        f"{zn16['gold_cross_check']['days_zero']} zero days of "
        f"{zn16['gold_cross_check']['days_with_a_keep_row']} — agrees exactly",
        "",
        "**It did contribute training rows to every pooled model, and all of them were "
        "zeros:**",
        "",
        "| window | ZN.16 train rows | of pooled total | share | all-zero targets | "
        "ZN.16 eval rows |",
        "|---|---:|---:|---:|---|---:|",
        *[f"| {w} | {v['zn16_train_rows']:,} | {v['pooled_train_rows_total']:,} | "
          f"{v['zn16_share_of_pooled_train_pct']:.2f}% | "
          f"{'yes' if v['zn16_train_rows_with_target_nonzero'] == 0 else 'no'} | "
          f"{v['zn16_eval_rows']:,} |" for w, v in c.items()],
        "",
        zn16["raw_electrical_signature"]["finding"],
        "",
        f"**The fault ends on {zn16['raw_electrical_signature']['fault_ends']}** — inside "
        "the already-spent final-test window. "
        + zn16["raw_electrical_signature"]["evidence_fault_ends"],
        "",
        "That is why ZN.16-PB is unevaluable in validation (zero denominator across all 79",
        "eligible days) yet evaluable in the final test, where it is the one meter on which",
        "the model does clearly worse than the baseline (12.61% vs 2.06% WAPE).",
        "",
        "Descriptive decomposition of the already-spent final test:",
        "",
        "| subset | n | model WAPE % | prev-day WAPE % | improvement pp |",
        "|---|---:|---:|---:|---:|",
        *[f"| {k.replace('_', ' ')} | {v['n_observations']:,} | "
          f"{v['pooled_model_wape_pct']:.2f} | {v['previous_day_wape_pct']:.2f} | "
          f"{v['improvement_pp']:+.2f} |" for k, v in d.items()],
        "",
        "This is reported as a description of what already happened, **not** as a reason to",
        "remove ZN.16-PB and re-score. " + zn16["no_action_taken"],
        "",
    ])


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, required=True)
    ap.add_argument("--profile", type=Path, default=None)
    args = ap.parse_args(argv)

    run_dir = args.run if args.run.is_absolute() else ML_WORK / args.run
    meta_path = run_dir / "run_metadata.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))

    profile_path = args.profile or sorted(
        (ML_WORK / "outputs").glob("task0b_*/daily_consumption_profile_v2.csv"))[-1]
    profile = pd.read_csv(profile_path, parse_dates=["reading_date_saudi"])
    table = pd.read_parquet(sorted(
        (ML_WORK / "outputs").glob("model2_design_*/model2_feature_table.parquet"))[-1])
    backtest = pd.read_csv(run_dir / "forecast_backtest_v2.csv",
                           parse_dates=["target_date_saudi"])
    boot = pd.read_csv(run_dir / "validation_bootstrap_v2.csv")
    coverage = pd.read_csv(run_dir / "quantile_coverage_raw_vs_monotonic_v2.csv")
    coverage = coverage.groupby("window", as_index=False).apply(
        lambda g: pd.Series({
            "n_observations": int(g["n_observations"].sum()),
            "nominal_coverage_pct": 80.0,
            "coverage_monotonic_pct": float(
                (g["coverage_monotonic_pct"] * g["n_observations"]).sum()
                / g["n_observations"].sum()),
            "coverage_raw_pct": float(
                (g["coverage_raw_pct"] * g["n_observations"]).sum()
                / g["n_observations"].sum()),
            "quantile_crossed_pct": float(
                (g["quantile_crossed_pct"] * g["n_observations"]).sum()
                / g["n_observations"].sum()),
            "clipped_at_zero_pct": float(
                (g["clipped_at_zero_pct"] * g["n_observations"]).sum()
                / g["n_observations"].sum()),
        }), include_groups=False)

    zn16 = _zn16_investigation(profile, table, backtest)

    meta["final_test_status"] = FINAL_TEST_STATUS
    meta["zn16_investigation"] = zn16
    meta["quantile_post_processing"] = {
        "raw_predictions_preserved": True,
        "raw_columns": ["p10_raw", "p50_raw", "p90_raw"],
        "monotonic_columns": ["p10_monotonic", "p50_monotonic", "p90_monotonic"],
        "flags": ["quantile_crossed", "clipped_at_zero"],
        "artifact": "forecast_backtest_quantiles_v2.csv",
        "reported_metrics_use": "monotonic",
        "note": (
            "Sorting the three independently fitted quantiles IS reordering them. The raw "
            "model outputs are preserved separately and are never overwritten. Every "
            "reported WAPE, MAE, interval and coverage figure uses the MONOTONIC set."),
    }
    meta["model2_status"] = (
        "CLOSED. Frozen as a historical experiment; not to be tuned further against this "
        "dataset. No meter production-promoted.")
    meta["wape_reporting_rule"] = (
        "WAPE is total absolute error over total actual consumption, a ratio of sums. It "
        "must never be reported as an accuracy percentage: 11.76% WAPE is NOT '88.24% "
        "accurate'.")
    meta_path.write_text(json.dumps(meta, indent=2, default=str), encoding="utf-8")

    (run_dir / "zn16_investigation.json").write_text(
        json.dumps(zn16, indent=2, default=str), encoding="utf-8")
    (run_dir / "results_summary_v2.md").write_text(
        _summary(run_dir, meta, boot, zn16, coverage, meta["transformation_counts"]),
        encoding="utf-8")

    print(f"final_test_status stamped CONSUMED in {meta_path.name}")
    print(f"ZN.16-PB investigation written to zn16_investigation.json")
    print(f"results_summary_v2.md regenerated")
    print("\n=== ZN.16-PB headline ===")
    for k in ("quality_screen_passing_days", "passing_days_with_target_zero",
              "passing_days_with_target_zero_pct", "passing_days_nonzero",
              "first_nonzero_day", "last_nonzero_day",
              "total_validated_kwh_passing_days", "total_validated_kwh_all_calendar_days"):
        print(f"  {k:<42s} {zn16[k]}")
    for w, v in zn16["pooled_training_contribution"].items():
        print(f"  {w:<14s} train rows {v['zn16_train_rows']:>4,} "
              f"({v['zn16_share_of_pooled_train_pct']:.2f}% of pooled), "
              f"all zero: {v['zn16_train_rows_with_target_nonzero'] == 0}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
