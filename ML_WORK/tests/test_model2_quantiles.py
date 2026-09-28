"""Model 2 — the raw quantile predictions must survive monotonic post-processing.

Sorting three independently fitted quantiles IS reordering them. These tests lock the
contract that the raw model outputs are preserved under their own names, that the monotonic
set is a separate derived set, and that the two flags describe exactly what happened.
"""
from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from model2_forecaster.train import (
    CATEGORICAL_FEATURES, NUMERIC_FEATURES, QUANTILES, predict_quantiles,
)

RAW = {
    #                     p10     p50     p90
    "ordered": [10.0, 20.0, 30.0],          # already monotonic
    "crossed_low": [25.0, 20.0, 30.0],      # p10 above p50
    "crossed_high": [10.0, 35.0, 30.0],     # p50 above p90
    "fully_reversed": [30.0, 20.0, 10.0],   # completely inverted
    "negative": [-5.0, 2.0, 8.0],           # p10 below zero
    "all_negative": [-9.0, -4.0, -1.0],     # every quantile below zero
}
ORDER = list(RAW)


class _StubModel:
    """Returns a fixed column of the RAW table, so the post-processing is what is tested."""

    def __init__(self, column: int):
        self._column = column

    def predict(self, X):
        return np.array([RAW[name][self._column] for name in ORDER], dtype=float)


@pytest.fixture
def frame() -> pd.DataFrame:
    n = len(ORDER)
    data = {c: np.zeros(n) for c in NUMERIC_FEATURES}
    data["meter_label"] = ["ZN.1-PB.1"] * n
    data["zone_name"] = ["Zone 1"] * n
    return pd.DataFrame(data, index=pd.RangeIndex(100, 100 + n))


@pytest.fixture
def categories() -> dict:
    return {"meter_label": ["ZN.1-PB.1"], "zone_name": ["Zone 1"]}


@pytest.fixture
def out(frame, categories) -> pd.DataFrame:
    models = {q: _StubModel(i) for i, q in enumerate(QUANTILES)}
    return predict_quantiles(models, frame, categories)


def test_raw_columns_are_exactly_what_the_models_predicted(out):
    for i, q in enumerate(QUANTILES):
        expected = [RAW[name][i] for name in ORDER]
        assert out[f"p{int(q * 100)}_raw"].tolist() == expected


def test_raw_columns_are_not_sorted(out):
    """The whole point: a crossed raw triple stays crossed in the raw columns."""
    row = out.iloc[ORDER.index("fully_reversed")]
    assert [row["p10_raw"], row["p50_raw"], row["p90_raw"]] == [30.0, 20.0, 10.0]


def test_raw_columns_keep_negative_values(out):
    row = out.iloc[ORDER.index("all_negative")]
    assert row["p10_raw"] == -9.0 and row["p90_raw"] == -1.0


def test_monotonic_columns_are_non_decreasing(out):
    mono = out[["p10_monotonic", "p50_monotonic", "p90_monotonic"]].to_numpy()
    assert (np.diff(mono, axis=1) >= 0).all()


def test_monotonic_columns_are_never_negative(out):
    mono = out[["p10_monotonic", "p50_monotonic", "p90_monotonic"]].to_numpy()
    assert (mono >= 0).all()


def test_monotonic_is_the_sorted_then_clipped_raw_triple(out):
    raw = out[["p10_raw", "p50_raw", "p90_raw"]].to_numpy()
    expected = np.clip(np.sort(raw, axis=1), 0.0, None)
    assert np.array_equal(out[["p10_monotonic", "p50_monotonic",
                               "p90_monotonic"]].to_numpy(), expected)


def test_quantile_crossed_flags_exactly_the_out_of_order_rows(out):
    expected = {"crossed_low", "crossed_high", "fully_reversed"}
    flagged = {ORDER[i] for i in np.flatnonzero(out["quantile_crossed"].to_numpy())}
    assert flagged == expected


def test_clipped_at_zero_flags_exactly_the_rows_clipping_changed(out):
    expected = {"negative", "all_negative"}
    flagged = {ORDER[i] for i in np.flatnonzero(out["clipped_at_zero"].to_numpy())}
    assert flagged == expected


def test_sorting_happens_before_clipping(out):
    """all_negative sorts to (-9, -4, -1) then clips to (0, 0, 0) — never (0, -4, -1)."""
    row = out.iloc[ORDER.index("all_negative")]
    assert [row["p10_monotonic"], row["p50_monotonic"],
            row["p90_monotonic"]] == [0.0, 0.0, 0.0]


def test_index_is_preserved_so_predictions_align_with_their_rows(out, frame):
    assert out.index.equals(frame.index)


def test_no_legacy_column_silently_holds_a_reordered_value(out):
    """The ambiguous p10/p50/p90 names are gone; a caller must choose raw or monotonic."""
    assert not {"p10", "p50", "p90"} & set(out.columns)


def test_categorical_features_are_not_consumed_as_numeric(frame, categories):
    """A guard on prepare_frame: the two categoricals must reach the model as categories."""
    from model2_forecaster.train import prepare_frame
    prepared = prepare_frame(frame, categories)
    for col in CATEGORICAL_FEATURES:
        assert isinstance(prepared[col].dtype, pd.CategoricalDtype)
