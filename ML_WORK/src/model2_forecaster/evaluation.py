"""Model 2 — chronological evaluation contract and the paired-bootstrap promotion procedure.

DESIGN ONLY. Nothing here trains or scores a model; it defines the splits, the minimums and
the uncertainty procedure, and is exercised on synthetic and baseline-only data.

SPLITS (on the TARGET date)
    validation_1  2026-01-12 .. 2026-03-12
    validation_2  2026-03-13 .. 2026-05-11
    final_test    2026-05-12 .. 2026-07-10

For every window, training rows are those whose target date is STRICTLY EARLIER than the
window start. Because each row's features look only backwards from its own target date, a
training row ending the day before a window cannot see into it.

The final test is reserved. Model selection, threshold tuning and the promotion decision all
run on validation evidence only; the final test is scored once, afterwards, for whatever the
validation already chose.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

WINDOWS = {
    "validation_1": ("2026-01-12", "2026-03-12"),
    "validation_2": ("2026-03-13", "2026-05-11"),
    "final_test": ("2026-05-12", "2026-07-10"),
}
SELECTION_WINDOWS = ("validation_1", "validation_2")
RESERVED_WINDOW = "final_test"

MIN_TRAIN_OBS = 120     # pipeline 11.4
MIN_EVAL_OBS = 20       # pipeline 11.4, per meter per window


def window_bounds(name: str) -> tuple[pd.Timestamp, pd.Timestamp]:
    start, end = WINDOWS[name]
    return pd.Timestamp(start), pd.Timestamp(end)


def split_for_window(table: pd.DataFrame, name: str) -> dict[str, pd.DataFrame]:
    """Eligible training and evaluation rows for one window."""
    start, end = window_bounds(name)
    eligible = table.loc[table["is_eligible"]]
    target = eligible["target_date_saudi"]
    return {
        "train": eligible.loc[target < start],
        "eval": eligible.loc[(target >= start) & (target <= end)],
    }


def per_meter_counts(table: pd.DataFrame) -> pd.DataFrame:
    """Train/eval observation counts per meter per window, with the minimums applied."""
    rows = []
    for name in WINDOWS:
        split = split_for_window(table, name)
        tr = split["train"].groupby("meter_label").size()
        ev = split["eval"].groupby("meter_label").size()
        for meter in sorted(table["meter_label"].unique()):
            n_train, n_eval = int(tr.get(meter, 0)), int(ev.get(meter, 0))
            rows.append({
                "window": name, "meter_label": meter,
                "n_train": n_train, "n_eval": n_eval,
                "meets_min_train": n_train >= MIN_TRAIN_OBS,
                "meets_min_eval": n_eval >= MIN_EVAL_OBS,
                "usable": n_train >= MIN_TRAIN_OBS and n_eval >= MIN_EVAL_OBS,
            })
    return pd.DataFrame(rows)


def windows_are_disjoint_and_ordered() -> bool:
    bounds = [window_bounds(n) for n in ("validation_1", "validation_2", "final_test")]
    for (_, prev_end), (next_start, _) in zip(bounds, bounds[1:]):
        if not prev_end < next_start:
            return False
    return True


# ------------------------------------------------------------------ WAPE + bootstrap

def wape(actual: np.ndarray, predicted: np.ndarray) -> float:
    """Total absolute error over total actual — a ratio of sums, not a mean of ratios."""
    actual = np.asarray(actual, dtype=float)
    predicted = np.asarray(predicted, dtype=float)
    denom = np.abs(actual).sum()
    if denom == 0:
        return np.nan
    return float(np.abs(actual - predicted).sum() / denom)


def _moving_block_indices(n: int, block: int, rng: np.random.Generator) -> np.ndarray:
    """Moving-block resample indices, preserving local autocorrelation."""
    if block <= 1:
        return rng.integers(0, n, size=n)
    n_blocks = int(np.ceil(n / block))
    starts = rng.integers(0, max(n - block + 1, 1), size=n_blocks)
    idx = np.concatenate([np.arange(s, min(s + block, n)) for s in starts])
    return idx[:n]


def _segmented_block_indices(
    segments: np.ndarray, block: int, rng: np.random.Generator
) -> np.ndarray:
    """Moving-block indices drawn WITHIN each segment, never across a segment boundary.

    validation_1 and validation_2 are scored by two separately trained models, so a block
    spanning the boundary would splice predictions from different models into one synthetic
    run. Each segment is resampled to its own length and the pieces are concatenated.
    """
    out = []
    for seg in pd.unique(segments):
        pos = np.flatnonzero(segments == seg)
        k = len(pos)
        out.append(pos[_moving_block_indices(k, min(block, k), rng)])
    return np.concatenate(out)


def paired_bootstrap_wape_delta(
    actual: np.ndarray,
    pred_model: np.ndarray,
    pred_baseline: np.ndarray,
    n_boot: int = 10_000,
    block: int = 7,
    seed: int = 20260918,
    alpha: float = 0.05,
    segments: np.ndarray | None = None,
) -> dict:
    """Uncertainty in (baseline WAPE - model WAPE) for one meter in one window.

    Positive delta means the model beats the previous-day baseline.

    Three deliberate choices:

    * PAIRED - both methods are recomputed on the SAME resampled meter-days each draw, so
      the shared day-to-day variation cancels and what is left is the difference itself.
    * RATIO RECOMPUTED - WAPE is a ratio of sums, so each draw re-sums numerator and
      denominator. Bootstrapping per-day ratios would estimate a different quantity.
    * MOVING BLOCK - daily consumption is autocorrelated, so an i.i.d. resample would
      understate the spread. Blocks of 7 days keep the weekly structure intact.
      block=1 gives the ordinary i.i.d. bootstrap, for comparison.
    """
    actual = np.asarray(actual, dtype=float)
    pred_model = np.asarray(pred_model, dtype=float)
    pred_baseline = np.asarray(pred_baseline, dtype=float)
    n = len(actual)
    if not (len(pred_model) == len(pred_baseline) == n):
        raise ValueError("actual, model and baseline must be the same length")
    if n == 0:
        raise ValueError("no observations to bootstrap")

    err_model = np.abs(actual - pred_model)
    err_base = np.abs(actual - pred_baseline)

    # WAPE divides by total actual consumption. A meter that records no consumption at all
    # over the window has no denominator, so the metric is undefined rather than zero or
    # infinite. ZN.16-PB is the live case: its register does not advance, so every eligible
    # day is 0.0 kWh. Report that honestly instead of producing a meaningless number.
    if np.abs(actual).sum() == 0:
        return {
            "n_observations": n, "wape_model": np.nan, "wape_baseline": np.nan,
            "delta_observed_pp": np.nan, "delta_ci_low_pp": np.nan,
            "delta_ci_high_pp": np.nan, "delta_one_sided_lower_pp": np.nan,
            "prob_model_better": np.nan, "n_boot": 0, "block": int(block),
            "seed": int(seed), "alpha": alpha, "segments": None,
            "blocks_cross_segments": False,
            "undefined_reason": "total actual consumption over the window is zero; "
                                "WAPE has no denominator",
        }

    observed = wape(actual, pred_baseline) - wape(actual, pred_model)

    seg = None if segments is None else np.asarray(segments)
    if seg is not None and len(seg) != n:
        raise ValueError("segments must be the same length as actual")

    rng = np.random.default_rng(seed)
    deltas = np.empty(n_boot, dtype=float)
    for b in range(n_boot):
        idx = (_moving_block_indices(n, block, rng) if seg is None
               else _segmented_block_indices(seg, block, rng))
        denom = actual[idx].sum()
        if denom == 0:
            deltas[b] = np.nan
            continue
        deltas[b] = (err_base[idx].sum() - err_model[idx].sum()) / denom

    finite = deltas[np.isfinite(deltas)]
    if finite.size == 0:
        return {
            "n_observations": n, "wape_model": wape(actual, pred_model),
            "wape_baseline": wape(actual, pred_baseline),
            "delta_observed_pp": 100 * observed, "delta_ci_low_pp": np.nan,
            "delta_ci_high_pp": np.nan, "delta_one_sided_lower_pp": np.nan,
            "prob_model_better": np.nan, "n_boot": int(n_boot), "block": int(block),
            "seed": int(seed), "alpha": alpha, "blocks_cross_segments": False,
            "segments": None if seg is None else [str(x) for x in pd.unique(seg)],
            "undefined_reason": "every bootstrap draw had a zero denominator",
        }
    lo, hi = np.percentile(finite, [100 * alpha / 2, 100 * (1 - alpha / 2)])
    return {
        "n_observations": n,
        "wape_model": wape(actual, pred_model),
        "wape_baseline": wape(actual, pred_baseline),
        "delta_observed_pp": 100 * observed,
        "delta_ci_low_pp": 100 * float(lo),
        "delta_ci_high_pp": 100 * float(hi),
        "delta_one_sided_lower_pp": 100 * float(np.percentile(finite, 100 * alpha)),
        "prob_model_better": float((finite > 0).mean()),
        "n_boot": int(n_boot), "block": int(block), "seed": int(seed), "alpha": alpha,
        "segments": None if seg is None else [str(s) for s in pd.unique(seg)],
        "blocks_cross_segments": False,
    }


def qualifying_windows(table: pd.DataFrame, meter_label: str) -> list[str]:
    """Validation windows this meter may contribute evidence from.

    A window qualifies only if it independently satisfies BOTH historical minimums for this
    meter. A window that fails either one contributes nothing to the pooled evidence — it is
    not topped up from the other window. ZN.17-PB is the live case: 102 training observations
    in validation_1 against the 120 required, a direct consequence of its 201-day gap.
    """
    out = []
    for name in SELECTION_WINDOWS:
        s = split_for_window(table.loc[table["meter_label"] == meter_label], name)
        if len(s["train"]) >= MIN_TRAIN_OBS and len(s["eval"]) >= MIN_EVAL_OBS:
            out.append(name)
    return out


def classify_validation_evidence(bootstrap: dict, margin_pp: float = 2.0) -> dict:
    """Describe the validation evidence. This is NOT a production promotion.

    Two independent descriptive labels, deliberately kept apart:

      statistically_supported  the 95% lower bound on the improvement exceeds zero
      strong_practical         the point improvement is at least margin_pp

    No meter is "promoted" on this basis. The project has no formally defined absolute
    forecast acceptance criterion, so these describe historical validation behaviour only.
    """
    lower = bootstrap["delta_one_sided_lower_pp"]
    point = bootstrap["delta_observed_pp"]
    undefined = bootstrap.get("undefined_reason")
    if undefined or not np.isfinite(lower) or not np.isfinite(point):
        return {
            "delta_observed_pp": point,
            "delta_ci_low_pp": bootstrap["delta_ci_low_pp"],
            "delta_ci_high_pp": bootstrap["delta_ci_high_pp"],
            "delta_one_sided_lower_pp": lower,
            "prob_model_better": bootstrap["prob_model_better"],
            "statistically_supported_improvement": False,
            "strong_practical_improvement": False,
            "practical_margin_pp": margin_pp,
            "status": "not_evaluable",
            "undefined_reason": undefined or "improvement could not be estimated",
        }
    return {
        "delta_observed_pp": point,
        "delta_ci_low_pp": bootstrap["delta_ci_low_pp"],
        "delta_ci_high_pp": bootstrap["delta_ci_high_pp"],
        "delta_one_sided_lower_pp": lower,
        "prob_model_better": bootstrap["prob_model_better"],
        "statistically_supported_improvement": bool(lower > 0.0),
        "strong_practical_improvement": bool(point >= margin_pp),
        "practical_margin_pp": margin_pp,
        "status": "validation_evidence_only_not_production_promoted",
    }


def promotion_decision(bootstrap: dict, margin_pp: float | None = None) -> dict:
    """Promote a meter only where the evidence, not the point estimate, supports it.

    Default rule: the one-sided 95% lower bound on the improvement must exceed zero. That
    asks "is this meter's model reliably better than the naive baseline?" and answers it with
    the uncertainty included, instead of comparing a point estimate against a fixed margin.

    Passing margin_pp additionally requires the lower bound to clear that margin, which is
    how the historical 2.0pp threshold should be applied IF it is retained: as a bound on the
    interval, not on the point estimate. Whether 2.0pp is the right number is a question for
    the validation evidence, not an assumption.
    """
    lower = bootstrap["delta_one_sided_lower_pp"]
    reliably_better = lower > 0.0
    clears_margin = None if margin_pp is None else lower >= margin_pp
    chosen = reliably_better if margin_pp is None else (reliably_better and clears_margin)
    return {
        "delta_observed_pp": bootstrap["delta_observed_pp"],
        "delta_one_sided_lower_pp": lower,
        "prob_model_better": bootstrap["prob_model_better"],
        "reliably_better_than_baseline": reliably_better,
        "margin_pp": margin_pp,
        "clears_margin": clears_margin,
        "chosen_method": "pooled_model" if chosen else "previous_day_baseline",
    }
