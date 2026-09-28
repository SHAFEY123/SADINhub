"""Task 4 — frozen sampling allocation. Integer-exact and fully deterministic.

Every allocation here is computed and written to disk BEFORE any row is drawn, and no rule
depends on an engineering label. Inclusion probabilities follow from the allocation, so
freezing the allocation freezes the weights.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

SEVERITY_RANK = {"Critical": 0, "Problematic": 1, "Anomaly": 2, "Review Required": 3}


def award_by_room(counts: np.ndarray, capacity: np.ndarray, target: int,
                  tiebreak: list) -> np.ndarray:
    """Award units one at a time to whoever has the most unused room.

    Ties break on capacity (larger first), then on the supplied key. Deterministic, and it
    always reaches `target` exactly unless capacity runs out.
    """
    counts = counts.astype(int).copy()
    capacity = capacity.astype(int)
    while int(counts.sum()) < target:
        room = capacity - counts
        if room.max() <= 0:
            break
        order = sorted(range(len(room)),
                       key=lambda i: (-room[i], -capacity[i], tiebreak[i]))
        counts[order[0]] += 1
    return counts


def allocate_stratum_a(findings: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Stratum A: Model 1 ELECTRICAL_FAULT findings, stratified by family x severity.

    Integer-exact by construction:
      1. base = floor(total / n_families), capped at each family's own size
      2. award the shortfall one unit at a time to the family with the most unused room
      3. within a family, floor of `cell_floor` per non-empty cell, then the same rule
    """
    a = cfg["stratum_a"]
    total = int(cfg["budget"]["stratum_a"])
    frame = findings.loc[findings["family"].isin(a["families"])
                         & findings["event_class"].eq(a["event_class"])]

    cells = (frame.groupby(["family", "worst_severity"]).size()
             .rename("N_h").reset_index())
    family_n = cells.groupby("family")["N_h"].sum()
    families = sorted(family_n.index)

    base = int(total // len(a["families"]))
    counts = np.array([min(base, int(family_n[f])) for f in families])
    counts = award_by_room(counts, family_n.reindex(families).to_numpy(), total, families)
    family_target = dict(zip(families, counts))

    out = []
    for family, g in cells.groupby("family"):
        g = g.sort_values("worst_severity", key=lambda s: s.map(SEVERITY_RANK)).copy()
        n_h = np.minimum(int(a["cell_floor"]), g["N_h"].to_numpy())
        n_h = award_by_room(n_h, g["N_h"].to_numpy(), family_target[family],
                            list(g["worst_severity"]))
        g["n_h"] = n_h
        g["pi_h"] = g["n_h"] / g["N_h"]
        g["weight"] = 1.0 / g["pi_h"]
        g["is_census"] = g["n_h"] == g["N_h"]
        out.append(g)

    alloc = pd.concat(out, ignore_index=True)
    alloc["stratum"] = "A"
    return alloc.sort_values(
        ["family", "worst_severity"],
        key=lambda s: s.map(SEVERITY_RANK) if s.name == "worst_severity" else s,
        ignore_index=True)


def reference_pool(scores: pd.DataFrame, high_rows: pd.DataFrame, meter: str,
                   cfg: dict) -> pd.DataFrame:
    """Eligible reference days for one meter, under the approved rule.

    Same meter, in that meter's OWN bottom quartile of window_anomaly_pct, and at least
    `reference_min_separation_days` from every high-ranked day of that meter so a reference
    cannot fall inside the same episode.

    The contrast is deliberately WITHIN-METER RELATIVE, not an absolute gap: ZN.10-PB.1 has
    never scored below 0.707 in its whole history, so an absolute 0.40 gap would silently
    drop that meter from the validation altogether.
    """
    b = cfg["stratum_b"]
    pool = scores.loc[scores["meter_label"].eq(meter)]
    if pool.empty:
        return pool
    cut = pool["window_anomaly_pct"].quantile(float(b["reference_quantile"]))
    eligible = pool.loc[pool["window_anomaly_pct"] <= cut].copy()
    if eligible.empty:
        return eligible
    high_days = high_rows.loc[high_rows["meter_label"].eq(meter), "day_saudi"].to_numpy()
    if high_days.size:
        sep = np.array([np.min(np.abs((d - high_days) / np.timedelta64(1, "D")))
                        for d in eligible["day_saudi"].to_numpy()])
        eligible = eligible.loc[sep >= float(b["reference_min_separation_days"])]
    return eligible


def allocate_stratum_b(explained_top: pd.DataFrame, scores: pd.DataFrame,
                       cfg: dict) -> pd.DataFrame:
    """Stratum B: how many high-ranked and reference rows each meter contributes.

    A meter participates only if it can support a within-meter comparison, which means at
    least `min_high_pool` high-ranked rows AND `min_reference_pool` eligible references.
    Nothing here looks at a label.
    """
    b = cfg["stratum_b"]
    rows = []
    for meter, g in explained_top.groupby("meter_label"):
        refs = reference_pool(scores, explained_top, meter, cfg)
        rows.append({"meter_label": meter,
                     "short_label": g["short_label"].iloc[0],
                     "N_high_pool": int(len(g)),
                     "R_reference_pool": int(len(refs))})
    pools = pd.DataFrame(rows).sort_values("meter_label", ignore_index=True)
    pools["eligible"] = ((pools["N_high_pool"] >= int(b["min_high_pool"]))
                         & (pools["R_reference_pool"] >= int(b["min_reference_pool"])))

    eligible = pools.loc[pools["eligible"]].reset_index(drop=True)
    if eligible.empty:
        pools["n_high"] = 0
        pools["n_reference"] = 0
        return pools

    # High rows: floor per meter, cap per meter, remainder by most unused room.
    capacity = np.minimum(eligible["N_high_pool"].to_numpy(), int(b["high_cell_cap"]))
    n_high = np.minimum(int(b["high_cell_floor"]), capacity)
    n_high = award_by_room(n_high, capacity, int(b["high_rows"]),
                           list(eligible["meter_label"]))

    # References: floor per participating meter, remainder proportional to the high
    # allocation, capped by each meter's eligible pool.
    participating = n_high > 0
    ref_capacity = np.where(participating,
                            np.minimum(eligible["R_reference_pool"].to_numpy(),
                                       np.maximum(n_high, 1) * 3), 0)
    n_ref = np.where(participating,
                     np.minimum(int(b["reference_floor"]), ref_capacity), 0)
    n_ref = award_by_room(n_ref, ref_capacity, int(b["reference_rows"]),
                          list(eligible["meter_label"]))

    eligible["n_high"] = n_high
    eligible["n_reference"] = n_ref
    out = pools.merge(eligible[["meter_label", "n_high", "n_reference"]],
                      on="meter_label", how="left")
    out[["n_high", "n_reference"]] = out[["n_high", "n_reference"]].fillna(0).astype(int)
    out["pi_high"] = np.where(out["N_high_pool"] > 0,
                              out["n_high"] / out["N_high_pool"], 0.0)
    out["pi_reference"] = np.where(out["R_reference_pool"] > 0,
                                   out["n_reference"] / out["R_reference_pool"], 0.0)
    out["stratum"] = "B"
    return out


def allocation_report(alloc_a: pd.DataFrame, alloc_b: pd.DataFrame,
                      n_c: int, n_d: int, frame_d: int, cfg: dict) -> pd.DataFrame:
    """One row per stratum: what was requested, what the population can supply, what was
    drawn. A shortfall is recorded and never back-filled from another stratum."""
    budget = cfg["budget"]
    c_cap = int(budget["stratum_c_cap"])
    n_c_drawn = min(n_c, c_cap)
    b_target = int(budget["model3_total"]) - n_c_drawn
    return pd.DataFrame([
        {"stratum": "A", "requested": int(budget["stratum_a"]),
         "available": int(alloc_a["N_h"].sum()),
         "drawn": int(alloc_a["n_h"].sum())},
        {"stratum": "B", "requested": b_target,
         "available": int(alloc_b["N_high_pool"].sum()
                          + alloc_b["R_reference_pool"].sum()),
         "drawn": int(alloc_b["n_high"].sum() + alloc_b["n_reference"].sum())},
        {"stratum": "C", "requested": c_cap, "available": int(n_c),
         "drawn": int(n_c_drawn)},
        {"stratum": "D", "requested": int(budget["stratum_d"]),
         "available": int(frame_d), "drawn": int(n_d)},
    ]).assign(shortfall=lambda d: d["requested"] - d["drawn"])
