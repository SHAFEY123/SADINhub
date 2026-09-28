"""Model 2 — pooled LightGBM quantile forecaster.

One model per quantile across ALL 29 meters, with meter and zone as native categorical
features. Hyperparameters are fixed in advance and are never tuned against any evaluation
window; there is no search, no early stopping and no eval_set, so no window can influence
them.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

QUANTILES = (0.10, 0.50, 0.90)

NUMERIC_FEATURES = [
    "lag_1", "lag_7", "lag_14", "roll_mean_7", "roll_std_7",
    "weekday", "is_weekend_fri_sat", "day_of_year", "cb_max_rating_a",
]
CATEGORICAL_FEATURES = ["meter_label", "zone_name"]
FEATURES = NUMERIC_FEATURES + CATEGORICAL_FEATURES

# Fixed before any window was scored. Conservative and near-default, chosen for a small,
# pooled daily table rather than tuned.
PARAMS = dict(
    objective="quantile",
    n_estimators=500,
    learning_rate=0.03,
    num_leaves=31,
    min_child_samples=30,
    random_state=20260918,
    n_jobs=-1,
    verbose=-1,
)

BASELINES = {
    "previous_day": "lag_1",            # consumption of the issue day D
    "same_weekday_last_week": "lag_7",  # exactly seven calendar days earlier
}


def prepare_frame(table: pd.DataFrame, categories: dict) -> pd.DataFrame:
    """Cast categoricals to a FIXED category set so train and eval encode identically."""
    out = table.copy()
    for col in CATEGORICAL_FEATURES:
        out[col] = pd.Categorical(out[col], categories=categories[col])
    out["is_weekend_fri_sat"] = out["is_weekend_fri_sat"].astype("int8")
    return out


def category_levels(table: pd.DataFrame) -> dict:
    return {c: sorted(table[c].dropna().unique().tolist()) for c in CATEGORICAL_FEATURES}


def fit_quantile_models(train: pd.DataFrame, categories: dict) -> dict:
    """Three pooled models — P10, P50, P90 — sharing all 29 meters' rows."""
    import lightgbm as lgb

    X = prepare_frame(train, categories)[FEATURES]
    y = train["target_kwh"].to_numpy(dtype=float)
    models = {}
    for q in QUANTILES:
        model = lgb.LGBMRegressor(alpha=q, **PARAMS)
        model.fit(X, y, categorical_feature=CATEGORICAL_FEATURES)
        models[q] = model
    return models


def predict_quantiles(models: dict, frame: pd.DataFrame, categories: dict) -> pd.DataFrame:
    """Return BOTH the raw model outputs and the monotonic post-processed set.

    The three quantile regressions are fitted independently, so nothing forces
    p10 <= p50 <= p90 and they do sometimes cross. Sorting them IS reordering them, so the
    raw predictions are kept under their own names and are never overwritten:

        p10_raw / p50_raw / p90_raw              exactly what each model predicted
        p10_monotonic / p50_monotonic / p90_monotonic   sorted, then clipped at zero
        quantile_crossed                         the raw triple was out of order
        clipped_at_zero                          clipping changed at least one value

    Every reported metric, interval and coverage figure uses the MONOTONIC set; the raw set
    is retained so the post-processing can be audited and reversed.
    """
    X = prepare_frame(frame, categories)[FEATURES]
    raw = np.column_stack([models[q].predict(X) for q in QUANTILES])
    out = pd.DataFrame(
        raw, index=frame.index,
        columns=[f"p{int(q * 100)}_raw" for q in QUANTILES])

    out["quantile_crossed"] = (raw[:, 0] > raw[:, 1]) | (raw[:, 1] > raw[:, 2])

    monotonic = np.sort(raw, axis=1)
    # Consumption cannot be negative; clip AFTER sorting so the order survives clipping.
    clipped = np.clip(monotonic, 0.0, None)
    out["clipped_at_zero"] = (clipped != monotonic).any(axis=1)
    for i, q in enumerate(QUANTILES):
        out[f"p{int(q * 100)}_monotonic"] = clipped[:, i]
    return out


def baseline_predictions(frame: pd.DataFrame) -> dict:
    """Both naive baselines come straight from features every eligible row already has, so
    all methods are scored on exactly the same observations."""
    return {name: frame[col].to_numpy(dtype=float) for name, col in BASELINES.items()}
