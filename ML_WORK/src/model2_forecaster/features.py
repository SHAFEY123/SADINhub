"""Model 2 — pooled feature table construction. DESIGN AND VALIDATION ONLY, no training.

FORECASTING CONTRACT
    issue time     the close of Saudi day D (D 21:00:00 UTC)
    target         total validated consumption for Saudi day D+1
    therefore      lag_1 for target D+1 is the consumption of day D

Every row is keyed by its TARGET date, with the issue date carried explicitly:

    target_date_saudi = T           the day being forecast
    issue_date_saudi  = T - 1 day   the day whose close the forecast is issued at

CALENDAR INTEGRITY
    Lags are calendar lags, never "previous available observation". The Task 0B profile is a
    complete per-meter calendar (16,704 meter-days including 1,951 explicitly inserted
    missing days), and every shift happens on that complete calendar. So lag_7 is exactly
    seven calendar days earlier even when six of them are missing — in which case the feature
    is null, and the row is excluded. Missing or screened-out consumption is never replaced
    with zero, never interpolated, and never backfilled.

ELIGIBILITY
    A day contributes a value only if it passed the Task 0B quality screen. An ineligible day
    is null everywhere it appears — as a target, as a lag, and inside the rolling window.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

LAGS = (1, 7, 14)
ROLL_WINDOW_DAYS = 7
# Both rolling features require ALL seven previous calendar days to be eligible, so
# "7-day mean" and "7-day std" mean the same thing in every row regardless of how sparse the
# surrounding data is. A partially-filled window would silently become a 3-day or 5-day
# statistic wearing a 7-day name.
ROLL_MEAN_MIN_PERIODS = 7
ROLL_STD_MIN_PERIODS = 7
WEEKEND_DAYS = (4, 5)       # pandas dayofweek: Friday=4, Saturday=5

FEATURE_COLUMNS = [
    "meter_label", "zone_name", "cb_max_rating_a",
    "lag_1", "lag_7", "lag_14", "roll_mean_7", "roll_std_7",
    "weekday", "is_weekend_fri_sat", "day_of_year",
]

SCHEMA = [
    ("energy_meter_key", "str", "key - canonical meter uuid"),
    ("meter_label", "str", "key / categorical - canonical meter label"),
    ("issue_date_saudi", "datetime64[ns]", "key - forecast issued at the close of this day"),
    ("target_date_saudi", "datetime64[ns]", "key - the day being forecast (issue + 1)"),
    ("zone_name", "str", "static categorical - from gold.zone"),
    ("cb_max_rating_a", "float64", "static numeric - silver.dim_meter_cb_rating"),
    ("lag_1", "float64", "eligible kWh on target - 1 calendar day (== issue day)"),
    ("lag_7", "float64", "eligible kWh on target - 7 calendar days"),
    ("lag_14", "float64", "eligible kWh on target - 14 calendar days"),
    ("roll_mean_7", "float64", "mean of eligible kWh over calendar days target-7..target-1"),
    ("roll_std_7", "float64", "sample std of the same window"),
    ("roll_7_n_eligible", "int64", "how many of those 7 calendar days were eligible"),
    ("weekday", "int64", "target date dayofweek, Monday=0"),
    ("is_weekend_fri_sat", "bool", "target date is Friday or Saturday"),
    ("day_of_year", "int64", "target date day of year"),
    ("target_kwh", "float64", "eligible kWh on the target date - the label"),
    ("target_available", "bool", "target date passed the Task 0B screen"),
    ("lags_available", "bool", "lag_1, lag_7 and lag_14 all present"),
    ("rolls_available", "bool", "roll_mean_7 and roll_std_7 both present"),
    ("is_eligible", "bool", "conjunction of the three above - usable as a modelling row"),
]


def eligible_series(profile_meter: pd.DataFrame) -> pd.Series:
    """Consumption indexed by the complete Saudi calendar, null wherever it is not eligible.

    Null covers three distinct situations, all of which must stay null: a missing calendar
    day, a day screened out by Task 0B, and a day whose consumption was itself null.
    """
    s = profile_meter.set_index("reading_date_saudi").sort_index()
    if s.index.has_duplicates:
        raise ValueError("duplicate dates in the daily profile for one meter")
    expected = pd.date_range(s.index.min(), s.index.max(), freq="D")
    if not s.index.equals(expected):
        raise ValueError("the daily profile calendar is not complete for one meter")

    kwh = s["validated_kwh_consumption"].astype("float64")
    return kwh.where(s["passes_quality_screen"].astype(bool), other=np.nan)


def build_meter_features(profile_meter: pd.DataFrame, static: dict) -> pd.DataFrame:
    """Feature rows for one meter, one row per target date on the complete calendar."""
    kwh = eligible_series(profile_meter)
    idx = kwh.index

    out = pd.DataFrame(index=idx)
    out.index.name = "target_date_saudi"

    # Calendar lags. .shift(k) on a complete daily index is a shift of k CALENDAR days,
    # which is the whole reason the profile keeps its missing days.
    for k in LAGS:
        out[f"lag_{k}"] = kwh.shift(k)

    # Rolling window over the 7 calendar days before the target: shift(1) aligns "yesterday"
    # to the target row, then rolling(7) spans target-1 .. target-7.
    prior = kwh.shift(1)
    roll = prior.rolling(ROLL_WINDOW_DAYS, min_periods=1)
    out["roll_mean_7"] = prior.rolling(
        ROLL_WINDOW_DAYS, min_periods=ROLL_MEAN_MIN_PERIODS).mean()
    out["roll_std_7"] = prior.rolling(
        ROLL_WINDOW_DAYS, min_periods=ROLL_STD_MIN_PERIODS).std()
    out["roll_7_n_eligible"] = roll.count().astype("int64")

    out["weekday"] = idx.dayofweek.astype("int64")
    out["is_weekend_fri_sat"] = idx.dayofweek.isin(WEEKEND_DAYS)
    out["day_of_year"] = idx.dayofyear.astype("int64")

    out["target_kwh"] = kwh.to_numpy()

    out["energy_meter_key"] = static["energy_meter_key"]
    out["meter_label"] = static["meter_label"]
    out["zone_name"] = static["zone_name"]
    out["cb_max_rating_a"] = static["cb_max_rating_a"]

    out = out.reset_index()
    out["issue_date_saudi"] = out["target_date_saudi"] - pd.Timedelta(days=1)

    out["target_available"] = out["target_kwh"].notna()
    out["lags_available"] = out[[f"lag_{k}" for k in LAGS]].notna().all(axis=1)
    # A complete rolling window is part of the definition, not merely a non-null result.
    out["rolls_available"] = (
        out[["roll_mean_7", "roll_std_7"]].notna().all(axis=1)
        & (out["roll_7_n_eligible"] == ROLL_WINDOW_DAYS)
    )
    out["is_eligible"] = (
        out["target_available"] & out["lags_available"] & out["rolls_available"])

    return out[[c for c, _, _ in SCHEMA]]


def build_feature_table(profile: pd.DataFrame, meter_static: pd.DataFrame) -> pd.DataFrame:
    """Pooled table across all 29 meters — one flat frame, not 29 separate ones."""
    static_by_key = meter_static.set_index("energy_meter_key").to_dict("index")
    frames = []
    for key, group in profile.groupby("energy_meter_key", sort=True):
        if key not in static_by_key:
            raise KeyError(f"no static covariates for meter {key}")
        s = dict(static_by_key[key], energy_meter_key=key)
        frames.append(build_meter_features(group, s))
    table = pd.concat(frames, ignore_index=True)
    return table.sort_values(
        ["meter_label", "target_date_saudi"], ignore_index=True)


def transformation_counts(profile: pd.DataFrame, table: pd.DataFrame) -> dict:
    """Row counts at each step, so nothing is dropped silently."""
    return {
        "profile_calendar_meter_days": int(len(profile)),
        "profile_passing_quality_screen": int(profile["passes_quality_screen"].sum()),
        "feature_rows_on_complete_calendar": int(len(table)),
        "target_available": int(table["target_available"].sum()),
        "and_lags_available": int((table["target_available"]
                                   & table["lags_available"]).sum()),
        "and_rolls_available": int(table["is_eligible"].sum()),
        "eligible_rows": int(table["is_eligible"].sum()),
        "excluded_target_unavailable": int((~table["target_available"]).sum()),
        "excluded_lags_unavailable": int((table["target_available"]
                                          & ~table["lags_available"]).sum()),
        "excluded_rolls_unavailable": int((table["target_available"]
                                           & table["lags_available"]
                                           & ~table["rolls_available"]).sum()),
        "meters": int(table["meter_label"].nunique()),
    }
