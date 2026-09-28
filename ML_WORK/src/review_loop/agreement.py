"""Task 4 — inter-rater agreement. Built and tested now, RUN LATER.

No engineering label exists yet, so nothing here is executed against real data during the
package build.

Both raw agreement and Cohen's kappa are reported, because they answer different questions
and kappa alone is misleading on a small, skewed sample:

  * raw agreement is the share of double-reviewed units the two reviewers labelled the same.
    It is easy to read and needs no assumption.
  * kappa corrects for agreement expected by chance, which matters when one category
    dominates. But it is unstable at this sample size and can be near zero even at 90% raw
    agreement when almost everything falls in one category - the "kappa paradox".

With roughly 20 double-reviewed units the interval on kappa is very wide, so it is reported
as DIAGNOSTIC: it tells you whether the labelling task is reproducible enough to be worth
estimating from, not what the agreement "really is".
"""
from __future__ import annotations

import numpy as np
import pandas as pd

DIAGNOSTIC_NOTE = (
    "DIAGNOSTIC ONLY. The overlap sample is about 20 units, so both raw agreement and "
    "kappa carry very wide intervals. Use them to judge whether the labelling task is "
    "reproducible, not as a measurement of agreement.")


def cohens_kappa(a: pd.Series, b: pd.Series) -> dict:
    """Cohen's kappa for two raters over the same units.

    Returns the components as well as the statistic, because on a skewed sample the
    components are what explain a surprising kappa.
    """
    a = pd.Series(a).astype(str)
    b = pd.Series(b).astype(str)
    if len(a) != len(b):
        raise ValueError("both raters must label the same units")
    n = len(a)
    if n == 0:
        return {"n": 0, "raw_agreement": float("nan"), "expected_agreement": float("nan"),
                "kappa": float("nan"), "categories": []}

    categories = sorted(set(a) | set(b))
    p_o = float((a.to_numpy() == b.to_numpy()).mean())
    p_e = float(sum((a.eq(c).mean()) * (b.eq(c).mean()) for c in categories))
    kappa = float((p_o - p_e) / (1 - p_e)) if p_e < 1 else float("nan")
    return {"n": int(n), "raw_agreement": p_o, "expected_agreement": p_e,
            "kappa": kappa, "categories": categories}


def bootstrap_kappa_ci(a: pd.Series, b: pd.Series, replicates: int = 10_000,
                       seed: int = 20260926) -> dict:
    """Percentile interval for kappa, so its instability is visible rather than implied."""
    a = pd.Series(a).astype(str).reset_index(drop=True)
    b = pd.Series(b).astype(str).reset_index(drop=True)
    n = len(a)
    if n < 2:
        return {"ci_low": float("nan"), "ci_high": float("nan"), "replicates": 0}
    rng = np.random.default_rng(seed)
    draws = np.empty(replicates, dtype=float)
    for i in range(replicates):
        idx = rng.integers(0, n, size=n)
        draws[i] = cohens_kappa(a.iloc[idx], b.iloc[idx])["kappa"]
    finite = draws[np.isfinite(draws)]
    if finite.size == 0:
        return {"ci_low": float("nan"), "ci_high": float("nan"), "replicates": 0}
    return {"ci_low": float(np.percentile(finite, 2.5)),
            "ci_high": float(np.percentile(finite, 97.5)),
            "replicates": int(finite.size),
            "undefined_replicates": int(replicates - finite.size)}


NOT_ESTIMABLE = (
    "NOT ESTIMABLE - too few double-reviewed pairs. A double review of one or two units is "
    "a governance/quality check that two people looked at it, not an agreement estimate.")


def agreement_report(labels: pd.DataFrame, key: pd.DataFrame,
                     label_columns: dict[str, list[str]],
                     reviewers: list[str], min_pairs: int = 5,
                     by_stratum: bool = False) -> pd.DataFrame:
    """Raw agreement and kappa per sheet and per label column, over overlap units only.

    `labels` is the returned long-form table: review_id, reviewer_id, and one column per
    label field.
    """
    overlap = key.loc[key["is_overlap"], ["review_id", "sheet"]]
    rows = []
    for sheet, columns in label_columns.items():
        ids = overlap.loc[overlap["sheet"].eq(sheet), "review_id"]
        sub = labels.loc[labels["review_id"].isin(ids)]
        for col in columns:
            if col not in sub.columns:
                continue
            wide = sub.pivot_table(index="review_id", columns="reviewer_id",
                                   values=col, aggfunc="first")
            wide = wide.dropna(subset=[r for r in reviewers if r in wide.columns])
            if not set(reviewers) <= set(wide.columns) or wide.empty:
                rows.append({"sheet": sheet, "label": col, "n_overlap": 0,
                             "raw_agreement": float("nan"), "kappa": float("nan"),
                             "note": "no completed overlap pairs"})
                continue
            stat = cohens_kappa(wide[reviewers[0]], wide[reviewers[1]])
            if stat["n"] < int(min_pairs):
                # Report that the pair was reviewed; refuse to dress it as an estimate.
                rows.append({
                    "sheet": sheet, "label": col, "n_overlap": stat["n"],
                    "raw_agreement": stat["raw_agreement"],
                    "expected_agreement": float("nan"),
                    "kappa": float("nan"),
                    "kappa_ci_low": float("nan"), "kappa_ci_high": float("nan"),
                    "n_categories_used": len(stat["categories"]),
                    "note": NOT_ESTIMABLE,
                })
                continue
            ci = bootstrap_kappa_ci(wide[reviewers[0]], wide[reviewers[1]])
            rows.append({
                "sheet": sheet, "label": col, "n_overlap": stat["n"],
                "raw_agreement": stat["raw_agreement"],
                "expected_agreement": stat["expected_agreement"],
                "kappa": stat["kappa"],
                "kappa_ci_low": ci["ci_low"], "kappa_ci_high": ci["ci_high"],
                "n_categories_used": len(stat["categories"]),
                "note": DIAGNOSTIC_NOTE,
            })
    return pd.DataFrame(rows)
