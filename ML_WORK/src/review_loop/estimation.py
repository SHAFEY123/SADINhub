"""Task 4 — the estimator, built and tested now, RUN LATER.

No engineering label exists yet, so nothing here is executed against real data during the
package build. It is implemented and unit-tested so the analysis is fixed before any label
can influence it.

Why not a plain bootstrap. Stratum A contains census cells: T1 is sampled at pi = 1 in all
three of its cells, as is T2 Critical. A census has ZERO sampling variance — we looked at
every unit. A naive with-replacement bootstrap would resample those cells and invent
variability that does not exist, inflating the interval. So:

  * survey-weighted linearisation carries the finite-population correction (1 - f_h), which
    is exactly 0 when f_h = 1;
  * the bootstrap variant holds census cells FIXED across replicates.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

UNSURE = "Unsure"


def weighted_ratio(y: np.ndarray, w: np.ndarray) -> float:
    """The point estimate: sum(w * y) / sum(w)."""
    w = np.asarray(w, dtype=float)
    y = np.asarray(y, dtype=float)
    total = w.sum()
    return float((w * y).sum() / total) if total > 0 else float("nan")


def linearised_variance(df: pd.DataFrame, outcome: str, cell: str = "cell",
                        N: str = "N_h", n: str = "n_h",
                        weight: str = "design_weight") -> dict:
    """Taylor-linearised variance of a ratio estimator under stratified SRSWOR, with FPC.

        Var(R) ~= (1 / (sum w)^2) * sum_h [ N_h^2 * (1 - f_h) / n_h * s2_h ]

    with e_i = y_i - R and s2_h the sample variance of e within cell h. When f_h = 1 the
    term is exactly zero, which is the whole point: a census cell cannot contribute
    sampling variance.
    """
    d = df.dropna(subset=[outcome]).copy()
    if d.empty:
        return {"estimate": float("nan"), "variance": float("nan"),
                "se": float("nan"), "ci_low": float("nan"), "ci_high": float("nan"),
                "n": 0, "census_cells": 0, "singleton_cells": []}

    R = weighted_ratio(d[outcome].to_numpy(), d[weight].to_numpy())
    d["_e"] = d[outcome].to_numpy(dtype=float) - R
    sum_w = float(d[weight].sum())

    total_var, census_cells, singletons = 0.0, 0, []
    for name, g in d.groupby(cell):
        N_h, n_h = float(g[N].iloc[0]), float(len(g))
        f_h = n_h / N_h if N_h > 0 else 1.0
        if f_h >= 1.0:
            census_cells += 1
            continue                       # zero sampling variance, by construction
        if n_h < 2:
            singletons.append(str(name))   # no within-cell variance estimate available
            continue
        s2 = float(g["_e"].var(ddof=1))
        total_var += (N_h ** 2) * (1.0 - f_h) / n_h * s2

    var = total_var / (sum_w ** 2) if sum_w > 0 else float("nan")
    se = float(np.sqrt(var)) if np.isfinite(var) and var >= 0 else float("nan")
    return {"estimate": R, "variance": var, "se": se,
            "ci_low": max(0.0, R - 1.96 * se) if np.isfinite(se) else float("nan"),
            "ci_high": min(1.0, R + 1.96 * se) if np.isfinite(se) else float("nan"),
            "n": int(len(d)), "census_cells": census_cells,
            "singleton_cells": singletons}


def fpc_stratified_bootstrap(df: pd.DataFrame, outcome: str, replicates: int,
                             seed: int, cell: str = "cell", N: str = "N_h",
                             weight: str = "design_weight") -> dict:
    """Stratified bootstrap that respects the finite population.

    Census cells (n_h == N_h) are held FIXED across replicates rather than resampled, so
    they contribute no spurious variability. Non-census cells are resampled with
    replacement and rescaled by sqrt(1 - f_h), the standard finite-population adjustment.
    """
    d = df.dropna(subset=[outcome]).copy()
    if d.empty:
        return {"estimate": float("nan"), "ci_low": float("nan"),
                "ci_high": float("nan"), "replicates": 0}

    rng = np.random.default_rng(seed)
    point = weighted_ratio(d[outcome].to_numpy(), d[weight].to_numpy())
    groups = {name: g for name, g in d.groupby(cell)}

    draws = np.empty(replicates, dtype=float)
    for b in range(replicates):
        ys, ws = [], []
        for g in groups.values():
            n_h, N_h = len(g), float(g[N].iloc[0])
            y = g[outcome].to_numpy(dtype=float)
            w = g[weight].to_numpy(dtype=float)
            if n_h >= N_h or n_h < 2:
                ys.append(y)                      # census, or too small to resample
                ws.append(w)
                continue
            f_h = n_h / N_h
            idx = rng.integers(0, n_h, size=n_h)
            # rescale the deviation from the cell mean by sqrt(1 - f_h)
            centre = y.mean()
            ys.append(centre + np.sqrt(1.0 - f_h) * (y[idx] - centre))
            ws.append(w[idx])
        draws[b] = weighted_ratio(np.concatenate(ys), np.concatenate(ws))

    return {"estimate": point,
            "ci_low": float(np.percentile(draws, 2.5)),
            "ci_high": float(np.percentile(draws, 97.5)),
            "replicates": int(replicates)}


def unsure_sensitivity(df: pd.DataFrame, label: str,
                       weight: str = "design_weight") -> dict:
    """The four required quantities. `Unsure` is never silently discarded.

    The conservative and optimistic bounds bracket the truth whatever the unresolved cases
    turn out to be, so a high Unsure rate widens the reported range rather than quietly
    improving the headline.
    """
    d = df.dropna(subset=[label]).copy()
    w = d[weight].to_numpy(dtype=float)
    is_unsure = d[label].eq(UNSURE).to_numpy()
    is_yes = d[label].eq("Y").to_numpy()

    resolved = d.loc[~is_unsure]
    resolved_est = (weighted_ratio(resolved[label].eq("Y").to_numpy(),
                                   resolved[weight].to_numpy())
                    if len(resolved) else float("nan"))
    return {
        "resolved_case": resolved_est,
        "n_resolved": int(len(resolved)),
        "weighted_unsure_rate": weighted_ratio(is_unsure, w),
        "n_unsure": int(is_unsure.sum()),
        "conservative_all_N": weighted_ratio(is_yes, w),
        "optimistic_all_Y": weighted_ratio(is_yes | is_unsure, w),
        "n_total": int(len(d)),
    }
