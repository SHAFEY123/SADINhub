"""Model 3 — Isolation Forest fitting and scoring. NO MODEL 1 ARTIFACT IS OPENED HERE.

One global forest per scorable Saudi day, trained strictly on the preceding 180 calendar
days and requiring at least 60 distinct observed prior dates, then scoring that day's
meters out of sample.

Three score columns, with different jobs:

    daily_rank_pct      percentile WITHIN one Saudi day. Exactly one meter per day reaches
                        1.0, so it cannot rank across days and must never be used to.
    window_anomaly_pct  empirical percentile of the current-day raw score against THAT
                        forest's own training-score distribution. Comparable across refits,
                        and the PRIMARY historical ranking score.
    window_anomaly_z    deterministic SECONDARY TIE-BREAK ONLY, for equal percentiles and
                        above all for the 1.0 saturation point. It is not a probability,
                        not a confidence, and not an independent anomaly measure.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

SCORE_COLUMNS = ["raw_score", "daily_rank_pct", "window_anomaly_pct", "window_anomaly_z"]


def training_dates(day: pd.Timestamp, observed: np.ndarray, window_days: int) -> np.ndarray:
    """Observed Saudi dates in [day - window_days, day - 1 day]. Distinct DATES."""
    lo = np.datetime64(day) - np.timedelta64(int(window_days), "D")
    return observed[(observed >= lo) & (observed < np.datetime64(day))]


def window_percentile(raw: np.ndarray, train_sorted: np.ndarray) -> np.ndarray:
    """Share of training scores <= each raw score. The `<=` convention is fixed, so a score
    at or above every training row gives exactly 1.0."""
    if train_sorted.size == 0:
        return np.full(raw.shape, np.nan)
    return np.searchsorted(train_sorted, raw, side="right") / float(train_sorted.size)


def _z(raw: np.ndarray, mean: float, std: float) -> np.ndarray:
    """Tie-break only. A zero-variance reference gives 0.0 rather than an infinity."""
    if not np.isfinite(std) or std == 0.0:
        return np.zeros(raw.shape, dtype="float64")
    return (raw - mean) / std


def score_all_days(table: pd.DataFrame, features: list[str], cfg: dict,
                   progress_every: int = 100) -> pd.DataFrame:
    """Fit one forest per scorable Saudi day and score that day's meters out of sample."""
    from sklearn.ensemble import IsolationForest

    p = cfg["isolation_forest"]
    window_days = int(p["train_window_days"])
    min_dates = int(p["min_train_dates"])

    # POSITIONAL indices throughout. table.groupby(...).index returns pandas LABELS, which
    # coincide with positions only for a clean RangeIndex; on any filtered or re-indexed
    # input they do not, and the mismatch silently selects the wrong rows.
    table = table.reset_index(drop=True)

    observed = np.array(sorted(table["day_saudi"].unique()), dtype="datetime64[ns]")
    scorable = sorted(table.loc[table["scorable"], "day_saudi"].unique())

    X_all = np.ascontiguousarray(table[features].to_numpy(dtype="float64"))
    if not np.isfinite(X_all).all():
        raise ValueError("non-finite value in the fitted matrix; refusing to fit")

    positions = np.arange(len(table))
    rows_by_day: dict[pd.Timestamp, np.ndarray] = {
        pd.Timestamp(day): positions[grp]
        for day, grp in table.groupby("day_saudi", sort=True).indices.items()
    }
    # Carry the label columns once rather than slicing the frame inside the loop.
    carry = table[["energy_meter_key", "meter_label", "short_label", "zone_name",
                   "is_zone13", "day_saudi", "readings_reported", "coverage_ratio",
                   "low_coverage_day"]]

    out = []
    for n, day in enumerate(scorable, start=1):
        day = pd.Timestamp(day)
        train_days = training_dates(day, observed, window_days)
        if train_days.size < min_dates:
            continue
        train_idx = np.concatenate(
            [rows_by_day[pd.Timestamp(d)] for d in train_days])
        score_idx = rows_by_day[day]

        forest = IsolationForest(
            n_estimators=int(p["n_estimators"]),
            max_samples=int(p["max_samples"]),
            contamination=p["contamination"],
            random_state=int(p["random_state"]),
            n_jobs=int(p["n_jobs"]),
        ).fit(X_all[train_idx])

        # Same sign convention everywhere: higher means more anomalous.
        train_scores = -forest.score_samples(X_all[train_idx])
        raw = -forest.score_samples(X_all[score_idx])
        train_sorted = np.sort(train_scores)

        frame = carry.take(score_idx).reset_index(drop=True)
        frame["raw_score"] = raw
        # method='max' so the highest score in a day reaches exactly 1.0.
        frame["daily_rank_pct"] = pd.Series(raw).rank(pct=True, method="max").to_numpy()
        frame["window_anomaly_pct"] = window_percentile(raw, train_sorted)
        frame["window_anomaly_z"] = _z(raw, float(train_scores.mean()),
                                       float(train_scores.std(ddof=1)))
        frame["n_train_rows"] = int(train_idx.size)
        frame["n_train_dates"] = int(train_days.size)
        frame["window_start"] = pd.Timestamp(train_days.min())
        frame["window_end"] = pd.Timestamp(train_days.max())
        frame["n_meters_scored_that_day"] = int(score_idx.size)
        frame["train_score_mean"] = float(train_scores.mean())
        frame["train_score_std"] = float(train_scores.std(ddof=1))
        out.append(frame)

        if progress_every and n % progress_every == 0:
            print(f"    scored {n}/{len(scorable)} days ...", flush=True)

    scores = pd.concat(out, ignore_index=True)
    return order(scores, cfg)


def order(scores: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Deterministic historical ordering: primary score, then tie-break, then labels.

    The two label fields are what make two runs byte-identical rather than merely
    equivalent.
    """
    r = cfg["ranking"]
    by = [r["primary"], r["tie_break"]] + list(r["final_tie_break"])
    ascending = [False, False] + [True] * len(r["final_tie_break"])
    return scores.sort_values(by, ascending=ascending, kind="mergesort",
                              ignore_index=True)


def top_n(scores: pd.DataFrame, n: int) -> pd.DataFrame:
    """Historical Top-N on window_anomaly_pct, tie-broken by window_anomaly_z."""
    return scores.head(int(n)).copy()


def per_meter_top(scores: pd.DataFrame, k: int) -> pd.DataFrame:
    """Each meter's own most unusual days, so one chronically odd meter cannot monopolise
    the facility list."""
    return (scores.groupby("meter_label", sort=True, group_keys=False)
            .head(int(k)).reset_index(drop=True))


def rank_agreement(a: pd.DataFrame, b: pd.DataFrame, n: int) -> dict:
    """How much two feature sets disagree about the historical Top-N.

    Reported for the Tier 1 vs Tier 1+2 sensitivity analysis. It is a STABILITY measure,
    never a selection criterion.
    """
    key = ["meter_label", "day_saudi"]
    ta = set(map(tuple, a.head(n)[key].to_numpy()))
    tb = set(map(tuple, b.head(n)[key].to_numpy()))
    inter = ta & tb

    merged = a[key + ["window_anomaly_pct"]].merge(
        b[key + ["window_anomaly_pct"]], on=key, suffixes=("_a", "_b"))
    spearman = float(merged["window_anomaly_pct_a"].corr(
        merged["window_anomaly_pct_b"], method="spearman"))
    return {
        "n": int(n),
        "overlap": int(len(inter)),
        "jaccard": float(len(inter) / len(ta | tb)) if (ta | tb) else float("nan"),
        "overlap_pct": float(100 * len(inter) / n),
        "spearman_full_universe": spearman,
        "rows_compared": int(len(merged)),
    }
