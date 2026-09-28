"""Model 2 feature and evaluation-design tests. No model is trained anywhere here."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

ML_WORK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ML_WORK / "src"))

from model2_forecaster.evaluation import (  # noqa: E402
    MIN_EVAL_OBS, MIN_TRAIN_OBS, WINDOWS, paired_bootstrap_wape_delta, per_meter_counts,
    promotion_decision, split_for_window, wape, window_bounds,
    windows_are_disjoint_and_ordered,
)
from model2_forecaster.features import build_feature_table, eligible_series  # noqa: E402

STATIC = pd.DataFrame([{
    "energy_meter_key": "m1", "meter_label": "ZN.99-PB_child__1_ch3pm",
    "zone_name": "Zone 99", "cb_max_rating_a": 100.0,
}])


def _profile(start="2026-01-01", n_days=60, kwh=100.0, passes=True, key="m1"):
    dates = pd.date_range(start, periods=n_days, freq="D")
    return pd.DataFrame({
        "energy_meter_key": key,
        "meter_label": "ZN.99-PB_child__1_ch3pm",
        "reading_date_saudi": dates,
        "validated_kwh_consumption": np.arange(n_days, dtype=float) + kwh,
        "passes_quality_screen": passes,
    })


# ---------------------------------------------------------------- calendar lag meaning

def test_lags_are_calendar_days_not_previous_available_rows():
    """The central guarantee: a hole in the calendar must NOT slide the lag."""
    p = _profile(n_days=30)
    # Screen out 2026-01-10..2026-01-14 so those days become ineligible (null), not absent.
    holes = pd.to_datetime(["2026-01-10", "2026-01-11", "2026-01-12",
                            "2026-01-13", "2026-01-14"])
    p.loc[p["reading_date_saudi"].isin(holes), "passes_quality_screen"] = False

    t = build_feature_table(p, STATIC).set_index("target_date_saudi")

    # 2026-01-15: lag_1 is 01-14 (ineligible -> null), NOT the last available day 01-09.
    assert pd.isna(t.loc[pd.Timestamp("2026-01-15"), "lag_1"])
    # 2026-01-16: lag_1 is 01-15, which is eligible and equals its own value.
    expected = p.loc[p["reading_date_saudi"] == pd.Timestamp("2026-01-15"),
                     "validated_kwh_consumption"].iloc[0]
    assert t.loc[pd.Timestamp("2026-01-16"), "lag_1"] == pytest.approx(expected)


@pytest.mark.parametrize("lag", [1, 7, 14])
def test_each_lag_is_exactly_n_calendar_days_earlier(lag):
    p = _profile(n_days=40)
    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    kwh = p.set_index("reading_date_saudi")["validated_kwh_consumption"]
    for target in pd.date_range("2026-02-05", periods=5, freq="D"):
        assert t.loc[target, f"lag_{lag}"] == pytest.approx(
            kwh[target - pd.Timedelta(days=lag)])


def test_lag_7_spans_seven_calendar_days_even_when_six_are_ineligible():
    p = _profile(n_days=30)
    target = pd.Timestamp("2026-01-20")
    # Make every day in (target-7, target) ineligible, leaving target-7 itself eligible.
    mask = (p["reading_date_saudi"] > target - pd.Timedelta(days=7)) & \
           (p["reading_date_saudi"] < target)
    p.loc[mask, "passes_quality_screen"] = False
    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    expected = p.loc[p["reading_date_saudi"] == target - pd.Timedelta(days=7),
                     "validated_kwh_consumption"].iloc[0]
    assert t.loc[target, "lag_7"] == pytest.approx(expected)
    assert pd.isna(t.loc[target, "lag_1"])


# ----------------------------------------------------------------- target definition

def test_target_is_next_saudi_day_and_lag_1_is_the_issue_day():
    p = _profile(n_days=20)
    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    kwh = p.set_index("reading_date_saudi")["validated_kwh_consumption"]
    target = pd.Timestamp("2026-01-10")
    row = t.loc[target]
    assert row["issue_date_saudi"] == target - pd.Timedelta(days=1)
    assert row["target_kwh"] == pytest.approx(kwh[target])
    assert row["lag_1"] == pytest.approx(kwh[row["issue_date_saudi"]])


def test_calendar_features_describe_the_target_date():
    p = _profile(n_days=20)
    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    friday = pd.Timestamp("2026-01-09")          # a Friday
    assert friday.dayofweek == 4
    assert bool(t.loc[friday, "is_weekend_fri_sat"]) is True
    assert t.loc[friday, "weekday"] == 4
    assert t.loc[friday, "day_of_year"] == friday.dayofyear
    monday = pd.Timestamp("2026-01-12")
    assert bool(t.loc[monday, "is_weekend_fri_sat"]) is False


# ------------------------------------------------------------ no future value may leak

def test_future_value_poisoning_leaves_features_unchanged():
    """Task 0A's poisoning test, applied to feature construction.

    Corrupting every day after a cut must not move any feature for target dates at or before
    the cut — those rows may only look backwards.
    """
    p = _profile(n_days=60)
    cut = pd.Timestamp("2026-02-01")

    clean = build_feature_table(p, STATIC)
    poisoned_profile = p.copy()
    future = poisoned_profile["reading_date_saudi"] > cut
    poisoned_profile.loc[future, "validated_kwh_consumption"] = -1e9
    poisoned = build_feature_table(poisoned_profile, STATIC)

    cols = ["lag_1", "lag_7", "lag_14", "roll_mean_7", "roll_std_7", "target_kwh"]
    a = clean.loc[clean["target_date_saudi"] <= cut, cols].reset_index(drop=True)
    b = poisoned.loc[poisoned["target_date_saudi"] <= cut, cols].reset_index(drop=True)
    pd.testing.assert_frame_equal(a, b)


def test_rolling_window_never_includes_the_target_day_itself():
    p = _profile(n_days=30)
    target = pd.Timestamp("2026-01-20")
    t_before = build_feature_table(p, STATIC).set_index("target_date_saudi")

    bumped = p.copy()
    bumped.loc[bumped["reading_date_saudi"] == target,
               "validated_kwh_consumption"] = 1e6
    t_after = build_feature_table(bumped, STATIC).set_index("target_date_saudi")

    assert t_before.loc[target, "roll_mean_7"] == pytest.approx(
        t_after.loc[target, "roll_mean_7"])
    assert t_before.loc[target, "lag_1"] == pytest.approx(t_after.loc[target, "lag_1"])
    # ...but the target itself did change, proving the fixture actually bit.
    assert t_after.loc[target, "target_kwh"] == pytest.approx(1e6)


def test_rolling_window_covers_the_seven_prior_calendar_days():
    p = _profile(n_days=30)
    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    kwh = p.set_index("reading_date_saudi")["validated_kwh_consumption"]
    target = pd.Timestamp("2026-01-20")
    window = kwh[target - pd.Timedelta(days=7): target - pd.Timedelta(days=1)]
    assert len(window) == 7
    assert t.loc[target, "roll_mean_7"] == pytest.approx(window.mean())
    assert t.loc[target, "roll_std_7"] == pytest.approx(window.std())
    assert t.loc[target, "roll_7_n_eligible"] == 7


# ------------------------------------------------------------------- missing days

def test_missing_days_are_null_never_zero_and_never_backfilled():
    p = _profile(n_days=30)
    hole = pd.Timestamp("2026-01-15")
    p.loc[p["reading_date_saudi"] == hole, "validated_kwh_consumption"] = np.nan
    p.loc[p["reading_date_saudi"] == hole, "passes_quality_screen"] = False

    s = eligible_series(p.assign(energy_meter_key="m1"))
    assert pd.isna(s[hole]), "an ineligible day must be null"
    assert (s.fillna(-999) != 0).all(), "nothing may be zero-filled"

    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    assert pd.isna(t.loc[hole, "target_kwh"])
    assert bool(t.loc[hole, "target_available"]) is False
    assert bool(t.loc[hole, "is_eligible"]) is False
    assert pd.isna(t.loc[hole + pd.Timedelta(days=1), "lag_1"])
    assert pd.isna(t.loc[hole + pd.Timedelta(days=7), "lag_7"])


def test_a_partial_rolling_window_is_null_not_a_shorter_statistic():
    """min_periods=7: one ineligible day voids the window rather than silently producing a
    6-day mean under a 7-day name. It is certainly never zero-filled."""
    p = _profile(n_days=30, kwh=100.0)
    target = pd.Timestamp("2026-01-20")
    drop = target - pd.Timedelta(days=3)
    p.loc[p["reading_date_saudi"] == drop, "passes_quality_screen"] = False

    t = build_feature_table(p, STATIC).set_index("target_date_saudi")
    row = t.loc[target]
    assert row["roll_7_n_eligible"] == 6
    assert pd.isna(row["roll_mean_7"])
    assert pd.isna(row["roll_std_7"])
    assert bool(row["rolls_available"]) is False
    assert bool(row["is_eligible"]) is False

    # The day after the hole leaves the window, the feature returns.
    recovered = t.loc[drop + pd.Timedelta(days=8)]
    assert recovered["roll_7_n_eligible"] == 7
    assert not pd.isna(recovered["roll_mean_7"])


def test_eligible_rolling_features_always_use_exactly_seven_days():
    p = _profile(n_days=40)
    p.loc[p["reading_date_saudi"].isin(
        pd.to_datetime(["2026-01-15", "2026-01-28"])), "passes_quality_screen"] = False
    t = build_feature_table(p, STATIC)
    ok = t.loc[t["is_eligible"]]
    assert (ok["roll_7_n_eligible"] == 7).all()
    assert ok["roll_mean_7"].notna().all() and ok["roll_std_7"].notna().all()


def test_incomplete_calendar_is_rejected_rather_than_silently_shifted():
    p = _profile(n_days=20)
    p = p.loc[p["reading_date_saudi"] != pd.Timestamp("2026-01-10")]
    with pytest.raises(ValueError, match="calendar is not complete"):
        eligible_series(p)


# ------------------------------------------------------------------- split contract

def test_windows_are_disjoint_ordered_and_match_the_published_dates():
    assert windows_are_disjoint_and_ordered()
    assert WINDOWS["validation_1"] == ("2026-01-12", "2026-03-12")
    assert WINDOWS["validation_2"] == ("2026-03-13", "2026-05-11")
    assert WINDOWS["final_test"] == ("2026-05-12", "2026-07-10")
    v1e = window_bounds("validation_1")[1]
    v2s, v2e = window_bounds("validation_2")
    fts = window_bounds("final_test")[0]
    assert v1e + pd.Timedelta(days=1) == v2s, "validation windows must be contiguous"
    assert v2e + pd.Timedelta(days=1) == fts, "final test must start the day after val2"


def test_training_rows_are_strictly_earlier_than_their_window():
    p = _profile(start="2025-06-01", n_days=420)
    t = build_feature_table(p, STATIC)
    for name in WINDOWS:
        s = split_for_window(t, name)
        start, end = window_bounds(name)
        assert s["train"]["target_date_saudi"].max() < start
        assert s["eval"]["target_date_saudi"].min() >= start
        assert s["eval"]["target_date_saudi"].max() <= end


def test_no_row_appears_in_two_windows():
    p = _profile(start="2025-06-01", n_days=420)
    t = build_feature_table(p, STATIC)
    seen: set = set()
    for name in WINDOWS:
        keys = set(map(tuple, split_for_window(t, name)["eval"]
                       [["meter_label", "target_date_saudi"]].to_numpy()))
        assert not (keys & seen), f"{name} overlaps an earlier window"
        seen |= keys


def test_final_test_rows_never_enter_any_training_set():
    p = _profile(start="2025-06-01", n_days=420)
    t = build_feature_table(p, STATIC)
    ft_start = window_bounds("final_test")[0]
    for name in WINDOWS:
        train = split_for_window(t, name)["train"]
        assert (train["target_date_saudi"] < ft_start).all()


def test_minimums_are_applied_per_meter_and_window():
    p = _profile(start="2025-06-01", n_days=420)
    counts = per_meter_counts(build_feature_table(p, STATIC))
    assert set(counts["window"]) == set(WINDOWS)
    row = counts.loc[counts["window"] == "validation_1"].iloc[0]
    assert row["usable"] == (row["n_train"] >= MIN_TRAIN_OBS
                             and row["n_eval"] >= MIN_EVAL_OBS)


# ------------------------------------------------------------- bootstrap machinery

def test_wape_is_a_ratio_of_sums():
    actual = np.array([10.0, 20.0, 30.0])
    pred = np.array([11.0, 18.0, 33.0])
    assert wape(actual, pred) == pytest.approx((1 + 2 + 3) / 60)


def test_identical_methods_give_exactly_zero_delta_with_a_degenerate_interval():
    rng = np.random.default_rng(0)
    actual = rng.uniform(50, 150, 120)
    pred = actual + rng.normal(0, 10, 120)
    r = paired_bootstrap_wape_delta(actual, pred, pred, n_boot=400)
    assert r["delta_observed_pp"] == pytest.approx(0.0, abs=1e-12)
    assert r["delta_ci_low_pp"] == pytest.approx(0.0, abs=1e-12)
    assert r["delta_ci_high_pp"] == pytest.approx(0.0, abs=1e-12)


def test_a_clearly_better_method_is_detected_with_a_positive_lower_bound():
    rng = np.random.default_rng(1)
    actual = rng.uniform(50, 150, 200)
    good = actual + rng.normal(0, 2, 200)
    poor = actual + rng.normal(0, 30, 200)
    r = paired_bootstrap_wape_delta(actual, good, poor, n_boot=600)
    assert r["delta_observed_pp"] > 0
    assert r["delta_one_sided_lower_pp"] > 0
    assert r["prob_model_better"] > 0.99
    assert promotion_decision(r)["chosen_method"] == "pooled_model"


def test_a_marginally_better_method_is_not_promoted_on_the_point_estimate_alone():
    rng = np.random.default_rng(7)
    actual = rng.uniform(50, 150, 60)
    baseline = actual + rng.normal(0, 25, 60)
    model = baseline + rng.normal(0, 24, 60) * 0.02   # a whisker better, mostly noise
    r = paired_bootstrap_wape_delta(actual, model, baseline, n_boot=600)
    d = promotion_decision(r, margin_pp=2.0)
    if r["delta_one_sided_lower_pp"] < 2.0:
        assert d["chosen_method"] == "previous_day_baseline"
    assert d["margin_pp"] == 2.0
    assert d["clears_margin"] == (r["delta_one_sided_lower_pp"] >= 2.0)


def _ar1(n, rho, sd, rng):
    """An AR(1) *error* series. Autocorrelation in the error is what drives the variance of
    the WAPE delta — an autocorrelated level alone does not, because the previous-day
    baseline's error is then just the level's increment, which is i.i.d."""
    e = np.zeros(n)
    z = rng.normal(0, sd, n)
    for i in range(1, n):
        e[i] = rho * e[i - 1] + z[i]
    return e


def _ci_width(r):
    return r["delta_ci_high_pp"] - r["delta_ci_low_pp"]


def test_block_bootstrap_widens_the_interval_on_autocorrelated_errors():
    rng = np.random.default_rng(11)
    n = 300
    actual = 100 + rng.normal(0, 5, n)
    model = actual + _ar1(n, 0.9, 4, rng)        # strongly autocorrelated error
    baseline = actual + rng.normal(0, 8, n)
    iid = paired_bootstrap_wape_delta(actual, model, baseline, n_boot=3000, block=1)
    blk = paired_bootstrap_wape_delta(actual, model, baseline, n_boot=3000, block=7)
    assert _ci_width(blk) > 1.2 * _ci_width(iid), \
        "blocks must not understate uncertainty when errors are autocorrelated"


def test_block_bootstrap_does_not_inflate_the_interval_when_errors_are_independent():
    """The counterpart: blocking must not manufacture uncertainty that is not there."""
    rng = np.random.default_rng(11)
    n = 300
    actual = 100 + rng.normal(0, 5, n)
    model = actual + _ar1(n, 0.0, 4, rng)        # rho = 0, i.e. i.i.d.
    baseline = actual + rng.normal(0, 8, n)
    iid = paired_bootstrap_wape_delta(actual, model, baseline, n_boot=3000, block=1)
    blk = paired_bootstrap_wape_delta(actual, model, baseline, n_boot=3000, block=7)
    assert 0.85 < _ci_width(blk) / _ci_width(iid) < 1.15


def test_bootstrap_is_reproducible_for_a_fixed_seed():
    rng = np.random.default_rng(5)
    actual = rng.uniform(50, 150, 100)
    a, b = actual + rng.normal(0, 5, 100), actual + rng.normal(0, 9, 100)
    one = paired_bootstrap_wape_delta(actual, a, b, n_boot=300, seed=42)
    two = paired_bootstrap_wape_delta(actual, a, b, n_boot=300, seed=42)
    assert one == two


def test_bootstrap_blocks_never_cross_a_segment_boundary():
    """val1 and val2 are scored by two separately trained models, so a block spanning the
    boundary would splice predictions from different models into one synthetic run."""
    import sys as _s
    from model2_forecaster.evaluation import _segmented_block_indices
    rng = np.random.default_rng(0)
    segments = np.array(["validation_1"] * 40 + ["validation_2"] * 60)
    for _ in range(200):
        idx = _segmented_block_indices(segments, block=7, rng=rng)
        assert len(idx) == len(segments)
        drawn = segments[idx]
        assert (drawn[:40] == "validation_1").all()
        assert (drawn[40:] == "validation_2").all()


def test_segmented_bootstrap_preserves_each_segment_size():
    rng = np.random.default_rng(1)
    from model2_forecaster.evaluation import _segmented_block_indices
    segments = np.array(["a"] * 25 + ["b"] * 11)
    idx = _segmented_block_indices(segments, block=7, rng=rng)
    drawn = pd.Series(segments[idx]).value_counts()
    assert drawn["a"] == 25 and drawn["b"] == 11
