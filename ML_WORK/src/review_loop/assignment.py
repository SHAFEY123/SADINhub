"""Task 4 — reviewer assignment. Deterministic, and orthogonal to sampling.

Assignment decides WHO reviews a unit. It does not decide WHICH units are in the sample,
so it cannot change an inclusion probability: the 200 units and their weights are already
frozen, and this module only partitions them.

The contract:

  * all 200 units are covered;
  * about 10% are assigned to BOTH reviewers, for inter-rater agreement;
  * the rest are split between the two;
  * overlap appears in both the finding-level and meter-day sheets;
  * the same `review_id` identifies a double-reviewed unit in both copies;
  * a fixed seed makes the whole thing reproducible.

Assignment is stratified by (sheet, stratum) so neither reviewer receives a skewed mix, and
so the overlap sample spans strata rather than landing entirely in one.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from review_loop.allocation import award_by_room


def _largest_remainder(sizes: np.ndarray, total: int) -> np.ndarray:
    """Proportional split of `total` across `sizes`, resolved by largest remainder.

    Deterministic: ties break on the larger stratum, then on position.
    """
    if sizes.sum() == 0 or total <= 0:
        return np.zeros(len(sizes), dtype=int)
    exact = sizes / sizes.sum() * total
    base = np.floor(exact).astype(int)
    remainder = total - int(base.sum())
    if remainder > 0:
        order = sorted(range(len(sizes)),
                       key=lambda i: (-(exact[i] - base[i]), -sizes[i], i))
        for i in order[:remainder]:
            base[i] += 1
    return np.minimum(base, sizes.astype(int))


def _apply_forced_overlap(groups: pd.DataFrame, a: dict) -> pd.DataFrame:
    """Force named strata into the overlap, holding the TOTAL fixed.

    Stratum C holds the only unexplained Model-3 Top-100 item, so it is double-reviewed as a
    governance check even though proportional allocation would give a single unit none. The
    compensating reduction comes from a named donor stratum, and because the per-group
    permutation is unchanged, the unit demoted is exactly the LAST one that stratum had
    admitted - the most marginal inclusion under the seed already in use.
    """
    forced = list(a.get("force_overlap_strata", []))
    donor = a.get("compensate_overlap_from")
    if not forced:
        return groups
    # A donor that is also a forced stratum would pay for itself: the +1 and the -1 cancel
    # and the forcing is silently undone. Refuse rather than quietly do nothing.
    if donor in forced:
        raise ValueError(
            f"compensate_overlap_from={donor!r} is itself a forced stratum; it would "
            f"cancel its own forcing")

    groups = groups.copy()
    for stratum in forced:
        mask = groups["stratum"].eq(stratum)
        if not mask.any():
            continue
        want = np.minimum(groups.loc[mask, "size"], 1)
        need = int((want - groups.loc[mask, "n_overlap"]).clip(lower=0).sum())
        if need <= 0:
            continue
        groups.loc[mask, "n_overlap"] = np.maximum(
            groups.loc[mask, "n_overlap"], want)
        if donor is None:
            raise ValueError("forcing overlap requires compensate_overlap_from")
        dmask = groups["stratum"].eq(donor)
        available = int(groups.loc[dmask, "n_overlap"].sum())
        if available < need:
            raise ValueError(
                f"donor stratum {donor} has {available} overlap units, cannot release {need}")
        # Take from the largest donor group first; deterministic.
        order = groups.loc[dmask].sort_values(
            ["n_overlap", "size"], ascending=False).index
        left = need
        for idx in order:
            if left <= 0:
                break
            take = min(left, int(groups.at[idx, "n_overlap"]))
            groups.at[idx, "n_overlap"] -= take
            left -= take
    return groups


def assign_reviewers(key: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Return `key` with `assigned_to` and `is_overlap` columns added.

    `assigned_to` is a `+`-joined list, so a double-reviewed unit reads "a+b".
    """
    a = cfg["assignment"]
    reviewers = list(cfg["governance"]["reviewers"])
    if len(reviewers) != 2:
        raise ValueError("the assignment contract is defined for exactly two reviewers")

    target_overlap = int(round(len(key) * float(a["overlap_fraction"])))
    rng = np.random.default_rng(int(a["seed"]))

    # Overlap is allocated across (sheet, stratum) in proportion to size, so it is
    # represented in BOTH sheets rather than concentrated in one.
    groups = (key.groupby(["sheet", "stratum"], sort=True).size()
              .rename("size").reset_index())
    groups["n_overlap"] = _largest_remainder(groups["size"].to_numpy(), target_overlap)
    groups = _apply_forced_overlap(groups, a)

    out = []
    for i, grp in enumerate(groups.itertuples(index=False)):
        block = key.loc[key["sheet"].eq(grp.sheet)
                        & key["stratum"].eq(grp.stratum)].copy()
        block = block.sort_values("review_id").reset_index(drop=True)
        order = rng.permutation(len(block))

        overlap_pos = set(order[: int(grp.n_overlap)].tolist())
        rest = [p for p in order if p not in overlap_pos]
        # Alternate the remainder so each reviewer gets a balanced share of every stratum.
        first = i % 2                       # flip which reviewer starts, per group
        assigned = []
        for pos in range(len(block)):
            if pos in overlap_pos:
                assigned.append("+".join(reviewers))
            else:
                k = rest.index(pos)
                assigned.append(reviewers[(k + first) % 2])
        block["assigned_to"] = assigned
        block["is_overlap"] = block["assigned_to"].str.contains(r"\+", regex=True)
        out.append(block)

    result = pd.concat(out, ignore_index=True)
    if len(result) != len(key):
        raise RuntimeError("assignment lost or duplicated review units")
    return result.sort_values("review_id", ignore_index=True)


def assignment_summary(assigned: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Per reviewer and per sheet: how many units, how many of them double-reviewed."""
    reviewers = list(cfg["governance"]["reviewers"])
    rows = []
    for sheet, g in assigned.groupby("sheet", sort=True):
        for r in reviewers:
            mine = g.loc[g["assigned_to"].str.split("+").apply(lambda v: r in v)]
            rows.append({"sheet": sheet, "reviewer": r,
                         "units": int(len(mine)),
                         "sole": int((~mine["is_overlap"]).sum()),
                         "overlap": int(mine["is_overlap"].sum())})
        rows.append({"sheet": sheet, "reviewer": "<total unique>",
                     "units": int(len(g)),
                     "sole": int((~g["is_overlap"]).sum()),
                     "overlap": int(g["is_overlap"].sum())})
    return pd.DataFrame(rows)


def verify(assigned: pd.DataFrame, cfg: dict) -> dict:
    """Every contract term, checked."""
    a = cfg["assignment"]
    reviewers = list(cfg["governance"]["reviewers"])
    target = int(round(len(assigned) * float(a["overlap_fraction"])))
    tolerance = int(a.get("overlap_tolerance", 2))

    per_reviewer = {
        r: int(assigned["assigned_to"].str.split("+").apply(lambda v: r in v).sum())
        for r in reviewers}
    overlap = assigned.loc[assigned["is_overlap"]]
    by_sheet = overlap.groupby("sheet").size().to_dict()

    expected = a.get("expected_overlap_by_stratum")
    by_stratum = overlap.groupby("stratum").size().to_dict()

    checks = {
        "all_units_covered": bool(
            assigned["assigned_to"].str.len().gt(0).all()
            and assigned["review_id"].is_unique),
        "no_unit_unassigned": bool(assigned["assigned_to"].notna().all()),
        "overlap_near_target": bool(abs(len(overlap) - target) <= tolerance),
        "overlap_in_both_sheets": bool(
            set(by_sheet) == set(assigned["sheet"].unique())
            and all(v > 0 for v in by_sheet.values())),
        "not_everything_is_double_reviewed": bool(len(overlap) < len(assigned)),
        "both_reviewers_used": bool(all(v > 0 for v in per_reviewer.values())),
        "workload_balanced": bool(
            abs(per_reviewer[reviewers[0]] - per_reviewer[reviewers[1]])
            <= max(2, int(0.1 * len(assigned)))),
        "forced_strata_are_in_the_overlap": bool(all(
            by_stratum.get(s, 0) >= 1 for s in a.get("force_overlap_strata", []))),
        "overlap_by_stratum_matches_the_frozen_plan": bool(
            expected is None or {k: int(v) for k, v in by_stratum.items()} == expected),
    }
    return {
        "checks": checks,
        "all_passed": all(checks.values()),
        "total_units": int(len(assigned)),
        "target_overlap": target,
        "actual_overlap": int(len(overlap)),
        "overlap_by_sheet": {k: int(v) for k, v in by_sheet.items()},
        "overlap_by_stratum": {k: int(v) for k, v in by_stratum.items()},
        "forced_overlap_strata": list(a.get("force_overlap_strata", [])),
        "compensated_from": a.get("compensate_overlap_from"),
        "units_per_reviewer": per_reviewer,
        "total_assignments": int(
            assigned["assigned_to"].str.split("+").apply(len).sum()),
        "seed": int(a["seed"]),
    }
