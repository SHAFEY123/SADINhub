"""Model 3, stage 3 — cross-check against the frozen Model 1 output.

This is the ONLY stage that opens a Model 1 artifact, and it runs strictly after all Model 3
scoring is complete. Model 1 never reaches the feature table, the fitted matrix or the
score, so the overlap metric cannot be circular.

What "explained" means, exactly. A Model 3 item is explained only when the SAME
`(meter_label, day_saudi)` carries a Model 1 event that is `ELECTRICAL_FAULT` and not
commissioning. Judged per meter-day, never facility-wide: another meter having an event that
day explains nothing about this one. `COMMISSIONING` and `DATA_AVAILABILITY` events are
still joined and still shown as context, but never count as an explanation — a day whose only
Model 1 event is a telemetry outage is unexplained, because the outage says why data is thin,
not why the electrical behaviour was unusual.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

KEY = ["meter_label", "day_saudi"]


def _merge_flag(left: pd.DataFrame, hits: pd.DataFrame, col: str) -> pd.DataFrame:
    """Left-join a presence flag and force it to a real bool dtype.

    `fillna(False)` on a merged column leaves object dtype, and `~` on an object Series of
    Python bools does INTEGER bitwise negation (True -> -2) rather than logical NOT. The
    explicit astype(bool) is what keeps `~flag` meaning what it reads as.
    """
    out = left.merge(hits, on=KEY, how="left")
    out[col] = out[col].fillna(False).astype(bool)
    return out


def expand_events(events: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """One row per (meter, Saudi day, family) that a Model 1 episode spans."""
    rows = []
    for r in events.itertuples(index=False):
        start = pd.Timestamp(r.event_start).normalize()
        end = pd.Timestamp(r.event_end).normalize()
        for day in pd.date_range(start, end, freq="D"):
            rows.append({
                "meter_label": r.meter_label,
                "day_saudi": day,
                "family": r.family,
                "detector": r.detector,
                "severity": r.severity,
                "event_class": r.event_class,
                "commissioning": bool(r.commissioning),
            })
    return pd.DataFrame(rows).drop_duplicates()


def build_crosscheck(scores: pd.DataFrame, events: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Attach Model 1 context to every scored meter-day, and mark what counts as explained."""
    c = cfg["crosscheck"]
    req = c["explains_requires"]
    daily = expand_events(events, cfg)

    explains = daily.loc[daily["event_class"].eq(req["event_class"])
                         & daily["commissioning"].eq(bool(req["commissioning"]))]

    out = scores.copy()
    # Per family: does THIS meter-day carry an explaining event of that family?
    for fam in c["families"]:
        col = f"m1_{fam.lower()}"
        hit = explains.loc[explains["family"].eq(fam), KEY].drop_duplicates().assign(
            **{col: True})
        out = _merge_flag(out, hit, col)

    out = _merge_flag(out, explains[KEY].drop_duplicates().assign(m1_explains=True),
                      "m1_explains")
    sev = explains.loc[explains["severity"].isin(["Critical", "Problematic"]),
                       KEY].drop_duplicates().assign(m1_critical_or_problematic=True)
    out = _merge_flag(out, sev, "m1_critical_or_problematic")

    # Context only: visible to the reviewer, never an explanation.
    for cls in c["context_only_classes"]:
        col = f"m1_context_{cls.lower()}"
        hit = daily.loc[daily["event_class"].eq(cls), KEY].drop_duplicates().assign(
            **{col: True})
        out = _merge_flag(out, hit, col)

    # Model 1's register family runs on 29 meters only, so for Zone 13 "no T5 event" means
    # T5 did not evaluate that meter, NOT that it found nothing.
    out["m1_register_family_in_scope"] = ~out["is_zone13"]
    return out


def base_rates(crosscheck: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Base rates over EXACTLY the Model 3 scored universe, never over all meter-days."""
    n = len(crosscheck)
    rows = []
    for fam in cfg["crosscheck"]["families"]:
        col = f"m1_{fam.lower()}"
        rows.append({"population": fam, "column": col,
                     "meter_days_with_event": int(crosscheck[col].sum()),
                     "base_rate_pct": 100 * float(crosscheck[col].mean())})
    for label, col in (("any_family", "m1_explains"),
                       ("critical_or_problematic", "m1_critical_or_problematic")):
        rows.append({"population": label, "column": col,
                     "meter_days_with_event": int(crosscheck[col].sum()),
                     "base_rate_pct": 100 * float(crosscheck[col].mean())})
    out = pd.DataFrame(rows)
    out["scored_universe"] = n
    return out


def overlap_and_lift(crosscheck: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Lift over the base rate, with a permutation null drawn from the same universe.

    Raw overlap is meaningless here: the 'any family' base rate is near 59%, so a random
    top-50 would agree with Model 1 about 59% of the time. Lift of 1.0 is chance.
    """
    c = cfg["crosscheck"]
    rng = np.random.default_rng(int(c["permutation_seed"]))
    n_perm = int(c["n_permutations"])
    universe = len(crosscheck)

    columns = [(f, f"m1_{f.lower()}") for f in c["families"]]
    columns += [("any_family", "m1_explains"),
                ("critical_or_problematic", "m1_critical_or_problematic")]

    rows = []
    for n in cfg["ranking"]["top_n"]:
        top = crosscheck.head(n)
        for label, col in columns:
            flags = crosscheck[col].to_numpy(dtype=bool)
            base = float(flags.mean())
            obs = float(top[col].mean())
            draws = np.array([flags[rng.choice(universe, size=n, replace=False)].mean()
                              for _ in range(n_perm)])
            rows.append({
                "n": n, "population": label,
                "base_rate_pct": 100 * base,
                "overlap_pct": 100 * obs,
                "lift": (obs / base) if base > 0 else float("nan"),
                "null_mean_pct": 100 * float(draws.mean()),
                "null_p95_pct": 100 * float(np.percentile(draws, 95)),
                "observed_above_null_p95": bool(obs > np.percentile(draws, 95)),
                "empirical_p_value": float((draws >= obs).mean()),
            })
    return pd.DataFrame(rows)


def list_c(crosscheck: pd.DataFrame, n: int) -> pd.DataFrame:
    """Top-N entries the SAME meter-day has no non-commissioning electrical event for."""
    top = crosscheck.head(n)
    return top.loc[~top["m1_explains"]].copy()


# --------------------------------------------------------------------------- nulls
#
# The global null (above) samples arbitrary meter-days, so it answers "is this better than
# picking random meter-days anywhere in the facility?". That ignores meter-level prevalence,
# and Model 3's Top-N is heavily concentrated on a handful of meters whose OWN Model 1
# prevalence is near 100%. Under those conditions almost any day drawn from those meters
# would count as explained, so the global null is too permissive.
#
# The meter-preserving null holds the Top-N's meter composition fixed and re-draws only the
# DAYS, which asks the sharper question: given that Model 3 chose these meters in these
# proportions, is its choice of days better than chance?
#
# A block variant additionally preserves short-run temporal dependence, because consecutive
# days within a meter are not independent observations.

def permutation_p(exceedances: int, n_draws: int) -> float:
    """(exceedances + 1) / (B + 1).

    The +1 in both terms counts the observed statistic as one of the possible arrangements,
    so a permutation test can never report p = 0 and claim more certainty than B draws can
    support.
    """
    return (int(exceedances) + 1) / (int(n_draws) + 1)


def observed_run_lengths(top: pd.DataFrame) -> np.ndarray:
    """Lengths of runs of consecutive calendar dates within each meter's selected rows.

    This is what sets the block length: it measures how clustered Model 3's own selections
    actually are, rather than imposing an arbitrary window.
    """
    runs = []
    for _, g in top.groupby("meter_label"):
        days = np.sort(g["day_saudi"].to_numpy())
        run = 1
        for i in range(1, len(days)):
            if (days[i] - days[i - 1]) / np.timedelta64(1, "D") == 1:
                run += 1
            else:
                runs.append(run)
                run = 1
        runs.append(run)
    return np.array(runs) if runs else np.array([1])


def _block_positions(n_rows: int, k: int, block: int, rng) -> np.ndarray:
    """k positions drawn from n_rows, in contiguous blocks of `block` where possible.

    Blocks may overlap and a day may be drawn more than once; that is ordinary moving-block
    bootstrap behaviour and is what preserves local dependence.
    """
    if block <= 1:
        if k <= n_rows:
            return rng.choice(n_rows, size=k, replace=False)
        return rng.integers(0, n_rows, size=k)
    span = max(n_rows - block + 1, 1)
    n_blocks = int(np.ceil(k / block))
    starts = rng.integers(0, span, size=n_blocks)
    idx = np.concatenate([np.arange(s, min(s + block, n_rows)) for s in starts])
    return idx[:k]


def meter_preserving_null(crosscheck: pd.DataFrame, top: pd.DataFrame,
                          columns: list[str], block: int, n_draws: int,
                          rng) -> np.ndarray:
    """Draws with the Top-N's meter composition held fixed. Returns (n_draws, n_columns)."""
    composition = top.groupby("meter_label").size()
    ordered = crosscheck.sort_values(["meter_label", "day_saudi"]).reset_index(drop=True)
    flags = {c: ordered[c].to_numpy(dtype=bool) for c in columns}
    # groupby(...).indices already yields positional numpy arrays, and `ordered` is
    # sorted by (meter_label, day_saudi) so each meter's positions are date-ordered -
    # which is what makes a contiguous block a contiguous stretch of days.
    positions = dict(ordered.groupby("meter_label").indices)

    out = np.empty((n_draws, len(columns)), dtype="float64")
    for b in range(n_draws):
        picks = np.concatenate([
            positions[m][_block_positions(len(positions[m]), int(k), block, rng)]
            for m, k in composition.items()])
        for j, c in enumerate(columns):
            out[b, j] = flags[c][picks].mean()
    return out


def global_null(crosscheck: pd.DataFrame, columns: list[str], n: int,
                n_draws: int, rng) -> np.ndarray:
    """Uniform draws over the whole scored universe. Preserved for comparison."""
    flags = {c: crosscheck[c].to_numpy(dtype=bool) for c in columns}
    universe = len(crosscheck)
    out = np.empty((n_draws, len(columns)), dtype="float64")
    for b in range(n_draws):
        picks = rng.choice(universe, size=n, replace=False)
        for j, c in enumerate(columns):
            out[b, j] = flags[c][picks].mean()
    return out


def compare_nulls(crosscheck: pd.DataFrame, cfg: dict) -> tuple[pd.DataFrame, dict]:
    """Three nulls per family per N, so the effect of each assumption is separable.

        global                  uniform over the scored universe (the original)
        meter_preserving_iid    same meter composition, days drawn independently
        meter_preserving_block  same meter composition, days drawn in blocks

    Comparing the first two isolates how much of the original significance came from WHICH
    METERS were chosen; comparing the last two isolates the effect of temporal dependence.
    """
    c = cfg["crosscheck"]
    B = int(c["n_permutations"])
    columns = [f"m1_{f.lower()}" for f in c["families"]] + [
        "m1_explains", "m1_critical_or_problematic"]
    labels = list(c["families"]) + ["any_family", "critical_or_problematic"]

    rows, meta = [], {}
    for n in cfg["ranking"]["top_n"]:
        top = crosscheck.head(n)
        runs = observed_run_lengths(top)
        block = max(int(round(float(runs.mean()))), 1)
        meta[f"top{n}"] = {
            "n_meters_in_top_n": int(top["meter_label"].nunique()),
            "meter_composition": top.groupby("short_label").size().to_dict(),
            "observed_mean_run_length_days": float(runs.mean()),
            "observed_max_run_length_days": int(runs.max()),
            "block_length_used": block,
        }
        draws = {
            "global": global_null(crosscheck, columns, n, B,
                                  np.random.default_rng(int(c["permutation_seed"]))),
            "meter_preserving_iid": meter_preserving_null(
                crosscheck, top, columns, 1, B,
                np.random.default_rng(int(c["permutation_seed"]) + 1)),
            "meter_preserving_block": meter_preserving_null(
                crosscheck, top, columns, block, B,
                np.random.default_rng(int(c["permutation_seed"]) + 2)),
        }
        for j, (label, col) in enumerate(zip(labels, columns)):
            obs = float(top[col].mean())
            base = float(crosscheck[col].mean())
            row = {"n": n, "population": label,
                   "observed_overlap_pct": 100 * obs,
                   "facility_base_rate_pct": 100 * base,
                   "lift_vs_facility_base": (obs / base) if base > 0 else float("nan"),
                   "block_length": block}
            for name, d in draws.items():
                col_draws = d[:, j]
                exc = int((col_draws >= obs).sum())
                row[f"{name}_mean_pct"] = 100 * float(col_draws.mean())
                row[f"{name}_p95_pct"] = 100 * float(np.percentile(col_draws, 95))
                row[f"{name}_p"] = permutation_p(exc, B)
                row[f"{name}_lift"] = (obs / col_draws.mean()
                                       if col_draws.mean() > 0 else float("nan"))
            rows.append(row)
    return pd.DataFrame(rows), meta
