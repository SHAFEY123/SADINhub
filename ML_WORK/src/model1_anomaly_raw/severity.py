"""Severity assignment for Model 1 events.

Severity is a TRIAGE ORDERING FOR HUMAN REVIEW. It is not a probability, a confidence or a
precision estimate: the project has no engineering labels yet, so no detector's precision is
known. Every output carries that caveat.

Three orthogonal axes (design spec section 8.2):

    persistence    transient < 24h | sustained 1-7d | chronic > 7d
    magnitude      minor | moderate | severe, from tertiles fixed within each family
    corroboration  none | partial | full, from the concurrent production classifier

Two overrides sit above the axes: the assumed commissioning window, and the monitor-only
demotion. T1 reverse power is graded separately (see GRADED_REVERSE_POWER): a sustained
reversal stays Critical, while an isolated reading has to earn Critical on magnitude, load
AND corroboration. That is a classification change only - the detector still raises every
one of these events and they all remain in the review output.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from model1_anomaly_raw.config import SEVERITY_RANK

# Physics contradictions that stay Critical at any duration.
#
# T5 keeps that treatment. `stuck_register` requires a complete day of readings under load
# by construction, so a one-"reading" episode is already a whole stuck day. And
# `register_decrease` is the one register condition the production classifier already
# catches, so a single reading arrives corroborated by `status_kwh = 'Invalid'`.
PHYSICS_CONTRADICTIONS = {("T5", "stuck_register"), ("T5", "register_decrease")}

# T1 reverse power is graded instead. A sustained reversal is a fault; a single reading at
# two watts with nothing corroborating it is not the same claim, and calling both Critical
# makes the severity ordering useless for triage. The DETECTOR is unchanged - these events
# are still raised and still visible - only their classification differs.
GRADED_REVERSE_POWER = ("T1", "reverse_power")


def _persistence(hours: float) -> str:
    if not np.isfinite(hours):
        return "transient"
    if hours < 24.0:
        return "transient"
    if hours <= 168.0:
        return "sustained"
    return "chronic"


def _magnitude_bands(events: pd.DataFrame, quantiles: list[float]) -> pd.Series:
    """Tertiles within each family, so a kW deviation is never ranked against a PF shortfall."""
    out = pd.Series("minor", index=events.index, dtype=object)
    for family, g in events.groupby("family"):
        vals = pd.to_numeric(g["magnitude"], errors="coerce")
        finite = vals.dropna()
        if finite.nunique() < 3:
            out.loc[g.index] = np.where(vals.notna(), "moderate", "minor")
            continue
        lo, hi = finite.quantile(quantiles[0]), finite.quantile(quantiles[1])
        band = pd.Series("minor", index=g.index, dtype=object)
        band[vals > lo] = "moderate"
        band[vals > hi] = "severe"
        out.loc[g.index] = band
    return out


def _commissioning(events: pd.DataFrame, boundary: pd.Timestamp) -> pd.Series:
    """An episode ending inside the assumed window whose meter/phase never recurs after it.

    The boundary is an ASSUMPTION derived from the observed data, not an engineering fact:
    every Tier-D transient ends in the last week of December 2024 and none recurs.
    """
    ends = pd.to_datetime(events["event_end"])
    within = ends <= boundary
    last_end = events.assign(_e=ends).groupby(
        ["meter_label", "family", "phase"])["_e"].transform("max")
    return within & (last_end <= boundary)


def assign(events: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Return `events` with persistence, magnitude, severity and commissioning columns."""
    if events.empty:
        for col in ("persistence", "magnitude_band", "severity", "commissioning",
                    "physics_contradiction", "severity_capped_by_commissioning",
                    "monitor_only", "severity_capped_by_monitor_only", "t1_isolated"):
            events[col] = pd.Series(dtype=object)
        return events

    s_cfg = cfg["severity"]
    ev = events.copy()
    ev["persistence"] = [_persistence(h) for h in ev["duration_hours"]]
    ev["magnitude_band"] = _magnitude_bands(ev, s_cfg["magnitude_quantiles"])
    ev["physics_contradiction"] = [
        (f, d) in PHYSICS_CONTRADICTIONS for f, d in zip(ev["family"], ev["detector"])]

    corroborated = ev["corroboration"].isin({"partial", "full"})
    chronic = ev["persistence"].eq("chronic")
    sustained = ev["persistence"].eq("sustained")
    transient = ev["persistence"].eq("transient")
    severe = ev["magnitude_band"].eq("severe")
    minor = ev["magnitude_band"].eq("minor")

    severity = pd.Series("Review Required", index=ev.index, dtype=object)
    # Applied weakest first so the strongest matching rule wins.
    severity[transient | (~corroborated & minor)] = "Review Required"
    severity[sustained | (transient & severe & corroborated)] = "Anomaly"
    severity[chronic | (sustained & severe)] = "Problematic"
    severity[(chronic & severe) | ev["physics_contradiction"]] = "Critical"

    # ---- T1 reverse power: duration, magnitude and corroboration aware
    t1 = (ev["family"].eq(GRADED_REVERSE_POWER[0])
          & ev["detector"].eq(GRADED_REVERSE_POWER[1]))
    if t1.any():
        r = cfg["severity"]["t1_reverse_power"]
        mag = pd.to_numeric(ev.get("magnitude"), errors="coerce")
        load = pd.to_numeric(ev.get("mean_current_pct_cb"), errors="coerce")
        n_flagged = pd.to_numeric(ev["n_flagged"], errors="coerce")

        # "Isolated" means a handful of readings inside a single day, not a reversal that
        # merely happens to be shorter than 24 hours.
        isolated = t1 & transient & (n_flagged <= int(r["isolated_max_readings"]))
        ev["t1_isolated"] = isolated

        meaningful = (mag >= float(r["critical_min_magnitude_kw"])) & \
                     (load >= float(r["critical_min_load_pct_cb"])) & corroborated
        tiny_uncorroborated = (mag < float(r["small_magnitude_kw"])) & ~corroborated

        # Sustained or chronic reverse power stays Critical.
        severity[t1 & ~isolated] = "Critical"
        # An isolated reading is Critical only on real magnitude, real load AND agreement.
        severity[isolated] = "Anomaly"
        severity[isolated & meaningful] = "Critical"
        # Very small and uncorroborated: still reported, never Critical.
        severity[isolated & tiny_uncorroborated] = "Review Required"
    else:
        ev["t1_isolated"] = False

    ev["severity"] = severity

    # Monitor-only meter/phases are watched and reported, but never asserted as a
    # confirmed finding, so they cannot reach the two severities that make that claim.
    # (Decision 4: ZN.5-PB P3 demoted from acceptance to monitor.)
    monitor = pd.Series(False, index=ev.index)
    for meter, phases in cfg["acceptance_set"].get("monitor_only", {}).items():
        for phase in phases:
            monitor |= ev["short_label"].eq(meter) & ev["phase"].eq(phase)
    ev["monitor_only"] = monitor
    asserted = ev["severity"].isin({"Critical", "Problematic"})
    ev["severity_capped_by_monitor_only"] = monitor & asserted
    ev.loc[ev["severity_capped_by_monitor_only"], "severity"] = "Anomaly"

    boundary = pd.Timestamp(cfg["commissioning"]["assumed_boundary_date"])
    ev["commissioning"] = _commissioning(ev, boundary)
    cap = cfg["commissioning"]["severity_cap"]
    too_high = ev["severity"].map(SEVERITY_RANK) > SEVERITY_RANK[cap]
    ev["severity_capped_by_commissioning"] = ev["commissioning"] & too_high
    ev.loc[ev["severity_capped_by_commissioning"], "severity"] = cap
    ev.loc[ev["commissioning"], "event_class"] = cfg["commissioning"]["label"]
    return ev


def describe(row: pd.Series) -> str:
    """One line an engineer can read without touching code."""
    phase = f"Phase {int(row['phase'])}" if row["phase"] else "meter"
    days = row["duration_hours"] / 24.0
    span = f"{pd.Timestamp(row['event_start']).date()} to {pd.Timestamp(row['event_end']).date()}"
    unit = str(row.get("magnitude_unit", ""))
    mag = row.get("magnitude")
    mag_s = f", {mag:.2f} {unit}" if pd.notna(mag) else ""
    extra = ""
    if row["family"] == "T1":
        bits = []
        if pd.notna(row.get("mean_current_a")):
            bits.append(f"load {row['mean_current_a']:.1f} A")
        if pd.notna(row.get("mean_current_pct_cb")):
            bits.append(f"{row['mean_current_pct_cb']:.1f}% CB")
        if pd.notna(row.get("mean_power_factor_while_reversed")):
            bits.append(f"PF {row['mean_power_factor_while_reversed']:+.3f}")
        if row.get("negative_power_factor_readings"):
            bits.append(f"{int(row['negative_power_factor_readings']):,} negative-PF readings")
        if row.get("t1_isolated"):
            bits.append("ISOLATED")
        extra = (", " + ", ".join(bits)) if bits else ""
    elif row["family"] == "T5" and pd.notna(row.get("mean_current_pct_cb")):
        extra = (f", load {row['mean_current_a']:.1f} A "
                 f"({row['mean_current_pct_cb']:.1f}% CB)")
    elif row["family"] == "T3" and pd.notna(row.get("mean_power_factor")):
        extra = f", mean PF {row['mean_power_factor']:.3f}"
    tag = " [COMMISSIONING, assumed]" if row.get("commissioning") else ""
    status = row.get("concurrent_status") or "none"
    return (f"{row['short_label']} {phase}: {row['detector']} {span} "
            f"({days:.1f} days, {row['n_flagged']:,} flagged){mag_s}{extra}, "
            f"concurrent status={status}, corroboration={row['corroboration']}{tag}")
