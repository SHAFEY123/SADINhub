"""Model 3 — daily feature table, built from raw Gold only.

Reads `gold.energy_raw` + `gold.meter` (+ `gold.zone` and `silver.dim_meter_cb_rating` for
static covariates) and nothing else. **No Task 0A or 0B artifact is read, and no Model 1
artifact is read.** Model 1 is joined only after scoring, into a separate cross-check
artifact.

Everything is a RATE, so reporting cadence cannot dominate the score: the facility's median
cadence moved from 286 to 354 readings/day over the history, and a count feature would
inherit that 23.8% step as an anomaly.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from meters import short_label  # noqa: E402

# One pass over gold.energy_raw. Every counter needed by §4 of the design spec, grouped by
# meter and Saudi date. The 5% load gate is applied inside the aggregate so the gated
# power-factor denominator is computed at source.
DAILY_SQL = """
SELECT m.energy_meter_key,
       m.meter_label,
       z.zone_name,
       r.cb_max_rating_a,
       (e.reading_timestamp_utc + make_interval(hours => %(off)s))::date AS day_saudi,
       count(*) AS readings_reported,

       count(*) FILTER (WHERE e.status_amp1 = 'Major Issue')
         + count(*) FILTER (WHERE e.status_amp2 = 'Major Issue')
         + count(*) FILTER (WHERE e.status_amp3 = 'Major Issue') AS n_major_issue,
       count(*) FILTER (WHERE e.status_amp1 = 'Major Problem')
         + count(*) FILTER (WHERE e.status_amp2 = 'Major Problem')
         + count(*) FILTER (WHERE e.status_amp3 = 'Major Problem') AS n_major_problem,

       count(*) FILTER (WHERE e.current_phase_1_a >= %(gate)s * r.cb_max_rating_a
                          AND e.active_power_phase_1_kw > 0) AS gated_readings_phase_1,
       count(*) FILTER (WHERE e.current_phase_2_a >= %(gate)s * r.cb_max_rating_a
                          AND e.active_power_phase_2_kw > 0) AS gated_readings_phase_2,
       count(*) FILTER (WHERE e.current_phase_3_a >= %(gate)s * r.cb_max_rating_a
                          AND e.active_power_phase_3_kw > 0) AS gated_readings_phase_3,

       count(*) FILTER (WHERE e.current_phase_1_a >= %(gate)s * r.cb_max_rating_a
                          AND e.active_power_phase_1_kw > 0
                          AND e.power_factor_phase_1 >= 0
                          AND e.power_factor_phase_1 < %(pfc)s) AS n_pf_crit_gated_1,
       count(*) FILTER (WHERE e.current_phase_2_a >= %(gate)s * r.cb_max_rating_a
                          AND e.active_power_phase_2_kw > 0
                          AND e.power_factor_phase_2 >= 0
                          AND e.power_factor_phase_2 < %(pfc)s) AS n_pf_crit_gated_2,
       count(*) FILTER (WHERE e.current_phase_3_a >= %(gate)s * r.cb_max_rating_a
                          AND e.active_power_phase_3_kw > 0
                          AND e.power_factor_phase_3 >= 0
                          AND e.power_factor_phase_3 < %(pfc)s) AS n_pf_crit_gated_3,

       count(*) FILTER (WHERE e.status_pf1 = 'Critical') AS n_pf_crit_ungated_1,
       count(*) FILTER (WHERE e.status_pf2 = 'Critical') AS n_pf_crit_ungated_2,
       count(*) FILTER (WHERE e.status_pf3 = 'Critical') AS n_pf_crit_ungated_3,

       count(*) FILTER (WHERE e.active_power_total_kw < 0) AS n_negative_total_kw,
       count(*) FILTER (WHERE e.active_power_phase_1_kw < 0)
         + count(*) FILTER (WHERE e.active_power_phase_2_kw < 0)
         + count(*) FILTER (WHERE e.active_power_phase_3_kw < 0) AS n_negative_phase_kw,

       count(*) FILTER (WHERE e.current_phase_1_a > 0 AND e.active_power_phase_1_kw = 0)
         + count(*) FILTER (WHERE e.current_phase_2_a > 0 AND e.active_power_phase_2_kw = 0)
         + count(*) FILTER (WHERE e.current_phase_3_a > 0 AND e.active_power_phase_3_kw = 0)
           AS n_current_without_power,
       count(*) FILTER (WHERE e.current_phase_1_a = 0 AND e.active_power_phase_1_kw <> 0)
         + count(*) FILTER (WHERE e.current_phase_2_a = 0 AND e.active_power_phase_2_kw <> 0)
         + count(*) FILTER (WHERE e.current_phase_3_a = 0 AND e.active_power_phase_3_kw <> 0)
           AS n_power_without_current,

       count(*) FILTER (WHERE e.status_v1  <> 'Acceptable')
         + count(*) FILTER (WHERE e.status_v2  <> 'Acceptable')
         + count(*) FILTER (WHERE e.status_v3  <> 'Acceptable')
         + count(*) FILTER (WHERE e.status_vn1 <> 'Acceptable')
         + count(*) FILTER (WHERE e.status_vn2 <> 'Acceptable')
         + count(*) FILTER (WHERE e.status_vn3 <> 'Acceptable') AS n_voltage_not_acceptable,
       count(*) FILTER (WHERE e.status_hz <> 'Acceptable') AS n_frequency_not_acceptable,

       avg((coalesce(e.current_phase_1_a, 0) + coalesce(e.current_phase_2_a, 0)
            + coalesce(e.current_phase_3_a, 0)) / 3.0) AS mean_phase_current_a
FROM gold.energy_raw e
JOIN gold.meter m USING (energy_meter_key)
-- zone_key exists on BOTH gold.energy_raw and gold.meter, so USING(zone_key) is ambiguous.
-- gold.meter is the canonical meter dimension, so join the zone through it explicitly.
LEFT JOIN gold.zone z ON z.zone_key = m.zone_key
LEFT JOIN silver.dim_meter_cb_rating r ON r.energy_meter_key = m.energy_meter_key
GROUP BY 1, 2, 3, 4, 5
ORDER BY 2, 5
"""

SCOPE_SQL = "SELECT count(*) AS readings FROM gold.energy_raw"


def fetch_daily_counts(conn, cfg: dict) -> pd.DataFrame:
    params = {"off": int(cfg["saudi"]["utc_offset_hours"]),
              "gate": float(cfg["features"]["pf_gate_pct_cb"]) / 100.0,
              "pfc": float(cfg["features"]["pf_critical_below"])}
    with conn.cursor() as cur:
        cur.execute(DAILY_SQL, params)
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    df = pd.DataFrame(rows, columns=cols)
    df["energy_meter_key"] = df["energy_meter_key"].astype(str)
    df["day_saudi"] = pd.to_datetime(df["day_saudi"])
    for c in df.columns:
        if c.startswith(("n_", "readings_", "gated_")):
            df[c] = df[c].astype("int64")
    for c in ("cb_max_rating_a", "mean_phase_current_a"):
        df[c] = pd.to_numeric(df[c], errors="coerce").astype("float64")
    return df


def _safe_ratio(num: pd.Series, den: pd.Series) -> pd.Series:
    """Zero denominator gives 0.0, never NaN and never a divide warning.

    For the gated power-factor rate this is deliberate and is disambiguated by its
    companion `pf_gate_open_rate_k`: the pair (0.0, 0.0) means "the gate never opened", and
    (0.0, >0) means "the gate opened and power factor was fine".
    """
    num = num.astype("float64")
    den = den.astype("float64")
    out = np.divide(num.to_numpy(), den.to_numpy(),
                    out=np.zeros(len(num), dtype="float64"),
                    where=den.to_numpy() > 0)
    return pd.Series(out, index=num.index)


def build_feature_table(counts: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Turn the daily counters into rates. Nothing here reads Model 1 or Task 0A/0B."""
    f = cfg["features"]
    d = counts.copy()
    d["short_label"] = d["meter_label"].map(short_label)
    d["is_zone13"] = d["meter_label"].str.startswith("ZN.13-")

    r = d["readings_reported"]
    three_r, six_r = 3 * r, 6 * r

    # coverage_ratio: denominator is the FACILITY MEDIAN for that Saudi date, which is
    # data-derived and so absorbs the 286 -> 354 cadence regime change automatically.
    facility_median = d.groupby("day_saudi")["readings_reported"].transform("median")
    d["facility_median_readings"] = facility_median
    d["coverage_ratio"] = _safe_ratio(r, facility_median)
    d["low_coverage_day"] = d["coverage_ratio"] < float(f["low_coverage_ratio"])

    d["major_issue_rate"] = _safe_ratio(d["n_major_issue"], three_r)
    d["major_problem_rate"] = _safe_ratio(d["n_major_problem"], three_r)
    for k in (1, 2, 3):
        d[f"pf_critical_rate_gated_{k}"] = _safe_ratio(
            d[f"n_pf_crit_gated_{k}"], d[f"gated_readings_phase_{k}"])
        d[f"pf_gate_open_rate_{k}"] = _safe_ratio(d[f"gated_readings_phase_{k}"], r)
        d[f"pf_critical_rate_ungated_{k}"] = _safe_ratio(
            d[f"n_pf_crit_ungated_{k}"], r)
    d["negative_total_power_rate"] = _safe_ratio(d["n_negative_total_kw"], r)
    d["negative_phase_power_rate"] = _safe_ratio(d["n_negative_phase_kw"], three_r)
    d["current_without_power_rate"] = _safe_ratio(d["n_current_without_power"], three_r)
    d["power_without_current_rate"] = _safe_ratio(d["n_power_without_current"], three_r)
    d["voltage_not_acceptable_rate"] = _safe_ratio(d["n_voltage_not_acceptable"], six_r)
    d["frequency_not_acceptable_rate"] = _safe_ratio(d["n_frequency_not_acceptable"], r)

    # NOT a rate and NOT clipped: clipping at 100 would erase exactly the overload
    # condition most worth surfacing.
    d["mean_load_pct_cb"] = _safe_ratio(
        d["mean_phase_current_a"], d["cb_max_rating_a"]) * 100.0

    d = add_dev28(d, cfg)
    return d.sort_values(["meter_label", "day_saudi"], ignore_index=True)


def add_dev28(d: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Tier 2: each rate minus that meter's own trailing median. Per-meter CONTEXT without
    per-meter IDENTITY, which an Isolation Forest would isolate on in a single split."""
    f = cfg["features"]
    window, min_periods = int(f["dev28_window_days"]), int(f["dev28_min_periods"])
    d = d.sort_values(["meter_label", "day_saudi"]).copy()
    available = pd.Series(False, index=d.index)
    for col in cfg["features"]["tier2"]:
        base = col[: -len("_dev28")]
        trailing = d.groupby("meter_label")[base].transform(
            lambda s: s.shift(1).rolling(window, min_periods=min_periods).median())
        d[col] = (d[base] - trailing).fillna(0.0)
        available |= trailing.notna()
    d["dev28_available"] = available
    return d


def mark_scorable(d: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Warm-up rule: a Saudi date is scorable only when at least `min_train_dates` DISTINCT
    prior Saudi calendar dates inside the training window carry observed data.

    Distinct DATES, not meter-day rows. Sixty rows could be two calendar dates, which would
    calibrate a forest against essentially one moment.
    """
    p = cfg["isolation_forest"]
    window, min_dates = int(p["train_window_days"]), int(p["min_train_dates"])
    observed = np.array(sorted(d["day_saudi"].unique()), dtype="datetime64[ns]")

    info = []
    for day in observed:
        lo = day - np.timedelta64(window, "D")
        prior = observed[(observed >= lo) & (observed < day)]
        info.append({"day_saudi": pd.Timestamp(day),
                     "distinct_prior_dates": int(prior.size),
                     "scorable_date": bool(prior.size >= min_dates)})
    dates = pd.DataFrame(info)
    out = d.merge(dates, on="day_saudi", how="left")
    out["scorable"] = out["scorable_date"]
    return out.drop(columns=["scorable_date"])


def reconcile(d: pd.DataFrame, cfg: dict, total_readings: int) -> dict:
    """Counts that must hold, checked before anything is fitted."""
    s = cfg["scope"]
    span = pd.date_range(d["day_saudi"].min(), d["day_saudi"].max(), freq="D")
    observed_dates = d["day_saudi"].nunique()

    interior = 0
    for _, sub in d.groupby("meter_label"):
        present = set(sub["day_saudi"])
        lo, hi = sub["day_saudi"].min(), sub["day_saudi"].max()
        interior += sum(1 for x in span if lo <= x <= hi and x not in present)

    scored = d.loc[d["scorable"]]
    checks = {
        "readings_total": {"expected": s["readings"], "actual": int(total_readings)},
        "readings_summed_from_daily": {
            "expected": s["readings"], "actual": int(d["readings_reported"].sum())},
        "meters": {"expected": s["meters"], "actual": int(d["meter_label"].nunique())},
        "meter_days": {"expected": s["expected_meter_days"], "actual": int(len(d))},
        "distinct_saudi_dates": {"expected": s["expected_distinct_dates"],
                                 "actual": int(observed_dates)},
        "scored_meter_days": {"expected": s["expected_scored_meter_days"],
                              "actual": int(len(scored))},
        "first_scorable_date": {
            "expected": s["expected_first_scorable_date"],
            "actual": str(scored["day_saudi"].min().date()) if len(scored) else None},
        "row_key_unique": {
            "expected": True,
            "actual": bool(not d.duplicated(["energy_meter_key", "day_saudi"]).any())},
    }
    for v in checks.values():
        v["result"] = "PASS" if v["expected"] == v["actual"] else "FAIL"
    return {
        "checks": checks,
        "all_passed": all(v["result"] == "PASS" for v in checks.values()),
        "calendar_span_days": int(len(span)),
        "dates_with_no_meter_reporting": int(len(span) - observed_dates),
        "missing_interior_days": int(interior),
        "missing_meter_days_total": int(
            len(span) * d["meter_label"].nunique() - len(d)),
        "warmup_meter_days_excluded": int(len(d) - len(scored)),
        "warmup_dates_excluded": int(
            d.loc[~d["scorable"], "day_saudi"].nunique()),
    }


def validate_ranges(d: pd.DataFrame, cfg: dict) -> dict:
    """Only GENUINE rates are bounded in [0, 1]. The universal constraint is finiteness.

    coverage_ratio exceeds 1 on about a fifth of meter-days because its denominator is the
    facility median; mean_load_pct_cb may exceed 100; *_dev28 may be negative. None of them
    is clipped.
    """
    f = cfg["features"]
    fitted = list(f["tier1"]) + list(f["tier2"])
    out = {"bounded_ok": {}, "unbounded_observed": {}, "non_finite": {}}

    for col in f["bounded_rate_features"]:
        v = d[col]
        out["bounded_ok"][col] = bool((v >= 0).all() and (v <= 1).all())
    for col in list(f["unbounded_features"]) + list(f["tier2"]):
        v = d[col]
        out["unbounded_observed"][col] = {
            "min": float(v.min()), "max": float(v.max()),
            "n_above_1": int((v > 1).sum()), "n_below_0": int((v < 0).sum())}
    for col in fitted:
        bad = int((~np.isfinite(d[col].to_numpy(dtype="float64"))).sum())
        if bad:
            out["non_finite"][col] = bad

    out["all_bounded_rates_in_unit_interval"] = all(out["bounded_ok"].values())
    out["all_fitted_values_finite"] = not out["non_finite"]
    return out
