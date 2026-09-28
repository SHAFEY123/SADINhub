"""Task 4 — draw the sampled rows, carrying an inclusion probability on every one.

Selection is random within each frozen cell, with a fixed seed. The allocation decides HOW
MANY come from each cell; the seed decides WHICH. No selection depends on a label.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from review_loop.allocation import reference_pool

KEY = ["meter_label", "day_saudi"]


def _draw(frame: pd.DataFrame, n: int, seed: int) -> pd.DataFrame:
    """Simple random sample without replacement, deterministic for a given seed."""
    n = int(min(n, len(frame)))
    if n == 0:
        return frame.iloc[:0]
    rng = np.random.default_rng(seed)
    idx = rng.choice(len(frame), size=n, replace=False)
    return frame.iloc[np.sort(idx)]


def sample_stratum_a(findings: pd.DataFrame, alloc: pd.DataFrame,
                     cfg: dict) -> pd.DataFrame:
    """Model 1 findings, stratified by family x severity."""
    a = cfg["stratum_a"]
    seed = int(cfg["seed"]["stratum_a"])
    frame = findings.loc[findings["family"].isin(a["families"])
                         & findings["event_class"].eq(a["event_class"])]
    out = []
    for i, cell in enumerate(alloc.itertuples(index=False)):
        pool = frame.loc[frame["family"].eq(cell.family)
                         & frame["worst_severity"].eq(cell.worst_severity)]
        pool = pool.sort_values(["short_label", "phase", "detector"])
        picked = _draw(pool, cell.n_h, seed + i).copy()
        picked["stratum"] = "A"
        picked["cell"] = f"{cell.family}|{cell.worst_severity}"
        picked["N_h"] = int(cell.N_h)
        picked["n_h"] = int(cell.n_h)
        picked["inclusion_probability"] = float(cell.pi_h)
        picked["design_weight"] = 1.0 / float(cell.pi_h)
        picked["is_census_cell"] = bool(cell.is_census)
        out.append(picked)
    return pd.concat(out, ignore_index=True)


def sample_stratum_b(explained_top: pd.DataFrame, scores: pd.DataFrame,
                     alloc: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """High-ranked rows and their same-meter reference days.

    Both are drawn at random within meter, so every row has a known inclusion probability
    and the reference set is representative of that meter's eligible bottom quartile rather
    than hand-picked.
    """
    seed_high = int(cfg["seed"]["stratum_b_high"])
    seed_ref = int(cfg["seed"]["stratum_b_reference"])
    out = []
    for i, row in enumerate(alloc.loc[alloc["n_high"] > 0].itertuples(index=False)):
        pool = explained_top.loc[explained_top["meter_label"].eq(row.meter_label)]
        pool = pool.sort_values("day_saudi")
        high = _draw(pool, row.n_high, seed_high + i).copy()
        high["stratum"] = "B"
        high["b_role"] = "high_ranked"
        high["cell"] = f"B_high|{row.short_label}"
        high["N_h"] = int(row.N_high_pool)
        high["n_h"] = int(row.n_high)
        high["inclusion_probability"] = float(row.pi_high)
        high["design_weight"] = (1.0 / float(row.pi_high)) if row.pi_high else np.nan
        out.append(high)

        refs_pool = reference_pool(scores, explained_top, row.meter_label, cfg)
        refs_pool = refs_pool.sort_values("day_saudi")
        refs = _draw(refs_pool, row.n_reference, seed_ref + i).copy()
        if len(refs):
            refs["stratum"] = "B"
            refs["b_role"] = "reference"
            refs["cell"] = f"B_reference|{row.short_label}"
            refs["N_h"] = int(row.R_reference_pool)
            refs["n_h"] = int(row.n_reference)
            refs["inclusion_probability"] = float(row.pi_reference)
            refs["design_weight"] = ((1.0 / float(row.pi_reference))
                                     if row.pi_reference else np.nan)
            # The realised rank contrast is RECORDED, never assumed.
            refs["rank_contrast"] = (float(high["window_anomaly_pct"].min())
                                     - refs["window_anomaly_pct"])
            out.append(refs)
    if not out:
        return pd.DataFrame()
    return pd.concat(out, ignore_index=True)


def sample_stratum_c(unexplained: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Census of unexplained Top-100 items, capped. Not a sample, so pi = 1."""
    cap = int(cfg["budget"]["stratum_c_cap"])
    out = unexplained.sort_values(
        ["window_anomaly_pct", "window_anomaly_z"], ascending=False).head(cap).copy()
    out["stratum"] = "C"
    out["b_role"] = ""
    out["cell"] = "C_unexplained"
    out["N_h"] = int(len(unexplained))
    out["n_h"] = int(len(out))
    out["inclusion_probability"] = 1.0
    out["design_weight"] = 1.0
    return out


def sample_stratum_d(unflagged: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Uniform random draw from Model 1's OWN unflagged observed meter-days.

    Not Model 3's warm-up-restricted universe: Model 3's warm-up is a property of Model 3's
    training window and says nothing about what Model 1 did or did not flag.
    """
    n = int(cfg["budget"]["stratum_d"])
    frame = unflagged.sort_values(KEY)
    out = _draw(frame, n, int(cfg["seed"]["stratum_d"])).copy()
    out["stratum"] = "D"
    out["b_role"] = ""
    out["cell"] = "D_control"
    out["N_h"] = int(len(frame))
    out["n_h"] = int(len(out))
    out["inclusion_probability"] = len(out) / len(frame)
    out["design_weight"] = len(frame) / len(out)
    return out
