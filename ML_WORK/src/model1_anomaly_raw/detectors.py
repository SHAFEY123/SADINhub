"""Model 1 detector families T1-T5.

Each family is a separate, independently testable function. Three are deterministic-primary
(T1, T2, T5) and two are statistical (T3's CUSUM layer, T4). Nothing here reads the
database or writes a file; everything takes a frame and returns events.

    T1  polarity / reverse power        deterministic sign test, no baseline
    T2  current vs power inconsistency  deterministic, evaluated beyond the 15% CB gate
    T3  power factor                    band test behind a 5% CB load gate, plus CUSUM
    T4  statistical change / drift      EWMA at day grain, plus data-availability
    T5  register integrity              day grain, two load-evidence rules

A note that matters for T1 and T4. A self-referential baseline cannot detect a fault that
spans its own history: on ZN.16-PB the fault is present on 95.37% of readings across 18 of
19 months, so its own rolling mean IS the faulted state and an EWMA never departs from it.
That is structural, not a tuning problem, and is why polarity is deterministic.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

from model1_anomaly_raw.episodes import collapse, collapse_days
from model1_anomaly_raw.scope import PHASE_COLUMNS


# --------------------------------------------------------------------------- helpers

def merge_gap(cfg: dict, family: str) -> float:
    """Episode merge gap for one family, falling back to the global default."""
    ep = cfg["episodes"]
    return float(ep.get("merge_gap_minutes_by_family", {})
                 .get(family, ep["merge_gap_minutes"]))


def _corroboration(status_values: pd.Series, agreeing: set[str]) -> tuple[str, str]:
    """How far a concurrent production classifier agrees with this episode."""
    if status_values.empty:
        return "none", ""
    hits = status_values.isin(agreeing)
    share = float(hits.mean())
    mode = status_values.mode()
    concurrent = str(mode.iloc[0]) if len(mode) else ""
    if share >= 0.9:
        return "full", concurrent
    if share > 0.0:
        return "partial", concurrent
    return "none", concurrent


def _base_event(meter: dict, family: str, detector: str, phase: int, metric: str,
                episode: dict, grain: str) -> dict:
    return {
        "energy_meter_key": meter["energy_meter_key"],
        "meter_label": meter["meter_label"],
        "short_label": meter["short_label"],
        "zone_name": meter.get("zone_name"),
        "cb_max_rating_a": meter.get("cb_max_rating_a"),
        "family": family,
        "detector": detector,
        "phase": phase,
        "metric": metric,
        "grain": grain,
        "event_start": episode["event_start"],
        "event_end": episode["event_end"],
        "duration_hours": episode["duration_hours"],
        "n_flagged": episode["n_flagged"],
        "evidence_window_rows": episode["evidence_window_rows"],
    }


def cusum(x: np.ndarray, target: float, k_sigma: float, h_sigma: float) -> dict:
    """Two-sided CUSUM for sustained drift rather than single-point noise.

    k and h are expressed in standard deviations of the series, so the same configuration
    is meaningful for meters with very different variability.
    """
    x = np.asarray(x, dtype=float)
    finite = np.isfinite(x)
    out = {"flags": np.zeros(x.size, dtype=bool),
           "direction": np.zeros(x.size, dtype=np.int8),
           "sigma": float("nan")}
    if finite.sum() < 2:
        return out
    sigma = float(np.nanstd(x[finite], ddof=1))
    out["sigma"] = sigma
    if not np.isfinite(sigma) or sigma == 0.0:
        return out

    k, h = k_sigma * sigma, h_sigma * sigma
    pos = neg = 0.0
    flags, direction = out["flags"], out["direction"]
    for i in range(x.size):
        if not finite[i]:
            continue
        dev = x[i] - target
        pos = max(0.0, pos + dev - k)
        neg = max(0.0, neg - dev - k)
        if neg > h:
            flags[i], direction[i] = True, -1
        elif pos > h:
            flags[i], direction[i] = True, 1
    return out


def ewma_flags(x: np.ndarray, lam: float, k: float,
               baseline_window: int, min_baseline: int,
               baseline_mask: np.ndarray | None = None,
               baseline_gap: int = 0) -> dict:
    """EWMA control chart against a trailing baseline the point itself never joins.

    `baseline_mask` marks points that may CONTRIBUTE to the baseline.

    `baseline_gap` holds the baseline back by that many points, which matters more than it
    looks. With a plain trailing window a step change walks into its own reference: on
    ZN.16-PB's repair the baseline standard deviation inflates from 1.5 to 7.2 kW within a
    week of the step, so the control limit outruns the deviation and the change is never
    flagged. Holding the baseline back keeps the pre-change state as the reference for long
    enough to see the step.
    """
    x = np.asarray(x, dtype=float)
    n = x.size
    usable = np.isfinite(x)
    if baseline_mask is None:
        baseline_mask = np.ones(n, dtype=bool)
    contributes = usable & np.asarray(baseline_mask, dtype=bool)

    s = pd.Series(np.where(usable, x, np.nan))
    ewma = s.ewm(alpha=lam, adjust=False, ignore_na=True).mean().to_numpy()

    contrib = pd.Series(np.where(contributes, x, np.nan))
    roll = contrib.rolling(baseline_window, min_periods=min_baseline)
    # shift so a point is never part of the baseline it is judged against
    lag = 1 + int(baseline_gap)
    mean = roll.mean().shift(lag).to_numpy()
    std = roll.std().shift(lag).to_numpy()
    count = roll.count().shift(lag).to_numpy()

    with np.errstate(invalid="ignore"):
        limit = k * std
        deviation = np.abs(ewma - mean)
        flags = usable & np.isfinite(limit) & (count >= min_baseline) & (deviation > limit)
        # A zero-variance baseline gives a zero limit; require a real departure, not noise.
        flags &= np.isfinite(deviation) & (deviation > 0)
    return {"flags": np.nan_to_num(flags, nan=False).astype(bool), "ewma": ewma,
            "baseline_mean": mean, "baseline_std": std, "baseline_n": count,
            "deviation": deviation}


# --------------------------------------------------------------------------- T1

def detect_polarity(df: pd.DataFrame, meter: dict, cfg: dict) -> list[dict]:
    """T1 - energy measured flowing the wrong way.

    Reverse power WITH current present is a physics contradiction, not a statistical
    outlier: the CT sees current but the power comes out negative. No baseline is involved.
    """
    c = cfg["t1_polarity"]
    ep_cfg = cfg["episodes"]
    gap = merge_gap(cfg, "T1")
    cb = meter.get("cb_max_rating_a")
    events = []
    for phase, (kw_col, amp_col, pf_col, amp_status, pf_status) in PHASE_COLUMNS.items():
        kw, amps, pf = df[kw_col].to_numpy(), df[amp_col].to_numpy(), df[pf_col].to_numpy()
        with np.errstate(invalid="ignore"):
            flags = (kw < 0) & (amps > float(c["min_current_a"]))
        flags = np.nan_to_num(flags, nan=False).astype(bool)
        if not flags.any():
            continue

        for ep in collapse(df["reading_timestamp_utc"], flags,
                           gap, ep_cfg["min_episode_readings"]):
            sl = slice(ep["first_index"], ep["last_index"] + 1)
            window_flags = flags[sl]
            kw_win = kw[sl][window_flags]
            pf_win = pf[sl][window_flags]
            amp_win = amps[sl][window_flags]
            corr, concurrent = _corroboration(
                df[pf_status].iloc[sl][window_flags], {"Critical"})
            ev = _base_event(meter, "T1", "reverse_power", phase,
                             "active_power_phase_kw", ep, "reading")
            ev.update({
                "magnitude": float(np.nanmean(np.abs(kw_win))) if kw_win.size else np.nan,
                "magnitude_unit": "mean_kW_while_reversed",
                "event_class": "ELECTRICAL_FAULT",
                "share_of_window_flagged": float(window_flags.mean()),
                # Evidence the severity rule reads, and that a reviewer needs in order to
                # tell a genuine reversal from a two-watt blip.
                "negative_power_factor_readings": int(
                    np.nan_to_num(pf_win < 0, nan=False).sum())
                if c["flag_negative_power_factor"] else 0,
                "mean_power_factor_while_reversed": float(np.nanmean(pf_win))
                if pf_win.size else np.nan,
                "mean_current_a": float(np.nanmean(amp_win)) if amp_win.size else np.nan,
                "mean_current_pct_cb": (float(np.nanmean(amp_win) / cb * 100.0)
                                        if amp_win.size and cb else np.nan),
                "max_abs_kw_while_reversed": float(np.nanmax(np.abs(kw_win)))
                if kw_win.size else np.nan,
                "concurrent_status": concurrent,
                "corroboration": corr,
            })
            events.append(ev)
    return events


# --------------------------------------------------------------------------- T2

def detect_current_power(df: pd.DataFrame, meter: dict, cfg: dict) -> list[dict]:
    """T2 - current and power disagree about whether load exists.

    Literal zero comparisons with no epsilon, matching the production classifier. Unlike
    that classifier, which only operates below 15% of breaker rating, this evaluates
    everywhere and records whether each episode lies inside or outside its reach.
    """
    gate_pct = float(cfg["t2_current_power"]["existing_rule_gate_pct_cb"])
    ep_cfg = cfg["episodes"]
    gap = merge_gap(cfg, "T2")
    cb = meter.get("cb_max_rating_a")
    events = []

    variants = (
        ("current_without_power", lambda a, k: (a > 0) & (k == 0), {"Major Problem"}),
        ("power_without_current", lambda a, k: (a == 0) & (k != 0), {"Major Issue"}),
    )
    for phase, (kw_col, amp_col, _pf, amp_status, _pfs) in PHASE_COLUMNS.items():
        kw, amps = df[kw_col].to_numpy(), df[amp_col].to_numpy()
        for detector, rule, agreeing in variants:
            with np.errstate(invalid="ignore"):
                flags = rule(amps, kw)
            flags = np.nan_to_num(flags, nan=False).astype(bool)
            flags &= np.isfinite(amps) & np.isfinite(kw)
            if not flags.any():
                continue

            load_pct = (amps / cb * 100.0) if cb else np.full(amps.shape, np.nan)
            for ep in collapse(df["reading_timestamp_utc"], flags,
                               gap, ep_cfg["min_episode_readings"]):
                sl = slice(ep["first_index"], ep["last_index"] + 1)
                w = flags[sl]
                pct_win = load_pct[sl][w]
                within = (np.nan_to_num(pct_win < gate_pct, nan=False).mean()
                          if pct_win.size else np.nan)
                corr, concurrent = _corroboration(
                    df[amp_status].iloc[sl][w], agreeing)
                ev = _base_event(meter, "T2", detector, phase,
                                 "current_vs_active_power", ep, "reading")
                ev.update({
                    "magnitude": float(np.nanmean(np.abs(kw[sl][w])))
                    if detector == "power_without_current"
                    else float(np.nanmean(amps[sl][w])),
                    "magnitude_unit": ("mean_kW_without_current"
                                       if detector == "power_without_current"
                                       else "mean_A_without_power"),
                    "event_class": "ELECTRICAL_FAULT",
                    "share_of_window_flagged": float(w.mean()),
                    "mean_load_pct_cb": float(np.nanmean(pct_win))
                    if pct_win.size else np.nan,
                    "share_within_existing_rule_reach": float(within),
                    "outside_existing_rule_reach": bool(
                        np.isfinite(within) and within < 1.0),
                    "concurrent_status": concurrent,
                    "corroboration": corr,
                })
                events.append(ev)
    return events


# --------------------------------------------------------------------------- T3

def detect_power_factor(df: pd.DataFrame, meter: dict, cfg: dict) -> list[dict]:
    """T3 - abnormal reactive demand FOR THE LOAD LEVEL.

    Two things this does that the production classifier does not:

    1. A minimum-load gate at 5% of breaker rating. Ungated, the PF bands fire on 28.38%
       of phase readings and 97.10% of that is low-load magnetising current.
    2. An explicit sign branch. A reversed CT produces PF around -0.8, which the band test
       would report as `Critical` for the wrong reason. Negative PF belongs to T1.
    """
    c = cfg["t3_power_factor"]
    ep_cfg = cfg["episodes"]
    gap = merge_gap(cfg, "T3")
    cb = meter.get("cb_max_rating_a")
    if not cb:
        return []
    gate_a = float(c["min_load_pct_cb"]) / 100.0 * float(cb)
    bands = c["bands"]
    events = []

    for phase, (kw_col, amp_col, pf_col, _amps, pf_status) in PHASE_COLUMNS.items():
        kw, amps, pf = df[kw_col].to_numpy(), df[amp_col].to_numpy(), df[pf_col].to_numpy()
        with np.errstate(invalid="ignore"):
            gated = (amps >= gate_a)
            if c["require_forward_power"]:
                gated &= (kw > 0)
            gated &= np.isfinite(pf)
            reversed_pf = gated & (pf < 0)          # belongs to T1, never to T3
            evaluable = gated & (pf >= 0)
        gated = np.nan_to_num(gated, nan=False).astype(bool)
        evaluable = np.nan_to_num(evaluable, nan=False).astype(bool)
        reversed_pf = np.nan_to_num(reversed_pf, nan=False).astype(bool)
        if not evaluable.any():
            continue

        # ONE episode set, not one per band. Power factor wanders across the 0.6 / 0.78 /
        # 0.8 boundaries constantly, so three separate band detectors shred a single
        # low-PF stretch into thousands of alternating fragments. The band composition is
        # carried as evidence on the episode instead, which is what a reviewer needs.
        with np.errstate(invalid="ignore"):
            flags = evaluable & (pf < bands["review_required"])
        flags = np.nan_to_num(flags, nan=False).astype(bool)
        if flags.any():
            for ep in collapse(df["reading_timestamp_utc"], flags,
                               gap, ep_cfg["min_episode_readings"]):
                sl = slice(ep["first_index"], ep["last_index"] + 1)
                w = flags[sl]
                pf_win, amp_win = pf[sl][w], amps[sl][w]
                n_crit = int((pf_win < bands["critical"]).sum())
                n_prob = int(((pf_win >= bands["critical"])
                              & (pf_win < bands["problematic"])).sum())
                n_rev = int((pf_win >= bands["problematic"]).sum())
                worst = ("Critical" if n_crit else
                         "Problematic" if n_prob else "Review Required")
                corr, concurrent = _corroboration(
                    df[pf_status].iloc[sl][w],
                    {"Critical", "Problematic", "Review Required"})
                ev = _base_event(meter, "T3", "pf_below_acceptable", phase,
                                 "power_factor_phase", ep, "reading")
                ev.update({
                    "magnitude": float(bands["review_required"] - np.nanmean(pf_win)),
                    "magnitude_unit": "mean_PF_shortfall_below_0.8",
                    "event_class": "ELECTRICAL_FAULT",
                    "share_of_window_flagged": float(w.mean()),
                    "mean_power_factor": float(np.nanmean(pf_win)),
                    "min_power_factor": float(np.nanmin(pf_win)),
                    "mean_load_pct_cb": float(np.nanmean(amp_win) / cb * 100.0),
                    "pf_band_worst": worst,
                    "pf_readings_critical": n_crit,
                    "pf_readings_problematic": n_prob,
                    "pf_readings_review_required": n_rev,
                    "gated_readings_evaluated": int(evaluable.sum()),
                    "readings_excluded_low_load": int((~gated).sum()),
                    "readings_excluded_reversed": int(reversed_pf.sum()),
                    "concurrent_status": concurrent,
                    "corroboration": corr,
                })
                events.append(ev)

        # Sustained drift, on the gated series only.
        pos = np.flatnonzero(evaluable)
        if pos.size >= int(c["cusum_min_points"]):
            res = cusum(pf[pos], float(c["cusum_target"]),
                        float(c["cusum_k_sigma"]), float(c["cusum_h_sigma"]))
            # ONE-SIDED, downward only. The CUSUM is two-sided by construction, but a
            # power factor sustained ABOVE 0.8 is healthy operation, not drift. Flagging it
            # reports meters running at PF 0.97 as anomalies.
            drift_down = res["flags"] & (res["direction"] < 0)
            if drift_down.any():
                full = np.zeros(pf.size, dtype=bool)
                full[pos] = drift_down
                for ep in collapse(df["reading_timestamp_utc"], full,
                                   gap, ep_cfg["min_episode_readings"]):
                    sl = slice(ep["first_index"], ep["last_index"] + 1)
                    w = full[sl]
                    pf_win = pf[sl][w]
                    corr, concurrent = _corroboration(
                        df[pf_status].iloc[sl][w],
                        {"Critical", "Problematic", "Review Required"})
                    ev = _base_event(meter, "T3", "pf_cusum_drift", phase,
                                     "power_factor_phase", ep, "reading")
                    ev.update({
                        "magnitude": float(c["cusum_target"] - np.nanmean(pf_win)),
                        "magnitude_unit": "mean_PF_shortfall_below_target",
                        "event_class": "ELECTRICAL_FAULT",
                        "share_of_window_flagged": float(w.mean()),
                        "mean_power_factor": float(np.nanmean(pf_win)),
                        "cusum_sigma": res["sigma"],
                        "gated_readings_evaluated": int(evaluable.sum()),
                        "concurrent_status": concurrent,
                        "corroboration": corr,
                    })
                    events.append(ev)
    return events


# --------------------------------------------------------------------------- T4

def detect_change(daily: pd.DataFrame, meter: dict, cfg: dict,
                  fault_windows: list[tuple[pd.Timestamp, pd.Timestamp]]) -> list[dict]:
    """T4 - has this meter's behaviour changed relative to its own recent past?

    Runs at day grain: both acceptance criteria are day-scale events and a reading-grain
    EWMA over 4.5M rows is slower and noisier for no gain.

    Two sub-detectors with DIFFERENT event classes. A telemetry outage is a
    data-availability event, not an electrical fault, even though the transition into and
    out of it is exactly what a change detector reacts to.
    """
    c = cfg["t4_change"]
    events = []
    if daily.empty:
        return events

    day = daily["day_saudi"]
    clean = np.ones(len(daily), dtype=bool)
    for start, end in fault_windows:
        clean &= ~((day >= start) & (day <= end)).to_numpy()
    # The baseline is deliberately NOT masked. T4 answers "has behaviour changed relative
    # to the recent past", so the comparison must be against whatever immediately preceded
    # the point - including a faulted state, which is exactly how the END of a fault is
    # detected. Masking the fault window starves the baseline and makes the repair
    # invisible. The consequence, that a fault spanning the whole baseline cannot be seen
    # from the meter's own history, is the documented structural limitation and is
    # reported as `self_referential_baseline_unavailable` rather than hidden.
    clean_days = int(clean.sum())
    baseline_unavailable = bool(fault_windows
                                and clean_days < int(c["min_baseline_days"]))

    # --- T4b data availability, first: an outage day must not also be read as a level shift
    counts = daily["n_readings"].to_numpy(dtype=float)
    outage = counts < float(c["min_readings_per_day"])
    for ep in collapse_days(day, outage):
        sl = slice(ep["first_index"], ep["last_index"] + 1)
        ev = _base_event(meter, "T4", "data_availability", 0, "readings_per_day",
                         ep, "day")
        ev.update({
            "magnitude": float(np.nanmean(counts[sl][outage[sl]])),
            "magnitude_unit": "mean_readings_per_day_during_outage",
            "event_class": c["availability_event_class"],
            "share_of_window_flagged": float(outage[sl].mean()),
            "concurrent_status": "",
            "corroboration": "none",
        })
        events.append(ev)

    # --- T4a electrical level shift, per phase, outage days excluded from both sides
    for phase in PHASE_COLUMNS:
        col = f"mean_kw_phase_{phase}"
        if col not in daily:
            continue
        x = daily[col].to_numpy(dtype=float)
        x = np.where(outage, np.nan, x)
        res = ewma_flags(x, float(c["ewma_lambda"]), float(c["ewma_k"]),
                         int(c["baseline_window_days"]), int(c["min_baseline_days"]),
                         baseline_mask=~outage,
                         baseline_gap=int(c.get("baseline_gap_days", 0)))
        flags = res["flags"] & ~outage
        if not flags.any():
            continue
        for ep in collapse_days(day, flags):
            sl = slice(ep["first_index"], ep["last_index"] + 1)
            w = flags[sl]
            inside_fault = bool(any(
                (pd.Timestamp(ep["event_start"]) >= s)
                and (pd.Timestamp(ep["event_end"]) <= e)
                for s, e in fault_windows))
            ev = _base_event(meter, "T4", "ewma_level_shift", phase,
                             "daily_mean_active_power_kw", ep, "day")
            ev.update({
                "magnitude": float(np.nanmean(res["deviation"][sl][w])),
                "magnitude_unit": "mean_kW_departure_from_baseline",
                "event_class": c["electrical_event_class"],
                "share_of_window_flagged": float(w.mean()),
                "baseline_mean_kw": float(np.nanmean(res["baseline_mean"][sl][w])),
                "observed_mean_kw": float(np.nanmean(x[sl][w])),
                "clean_baseline_days_available": clean_days,
                "self_referential_baseline_unavailable": baseline_unavailable,
                "inside_known_fault_window": inside_fault,
                "concurrent_status": "",
                "corroboration": "none",
            })
            events.append(ev)
    return events


# --------------------------------------------------------------------------- T5

def detect_register(daily: pd.DataFrame, meter: dict, cfg: dict,
                    df: pd.DataFrame | None = None) -> list[dict]:
    """T5 - the cumulative register disagrees with the power actually flowing.

    Day grain is mandatory. At reading grain "no advance since the previous reading" is
    true on 49-96% of intervals for HEALTHY meters, because the register ticks in coarse
    steps (the commonest positive increments are 0.4 and 0.5 kWh).

    Two independent load-evidence rules, both evaluated and both recorded:

        legacy_amps  mean summed current > 5 A       reproduces ZN.16's known evidence
        normalized   mean per-phase current >= x% CB generalises across 80-250 A breakers
    """
    c = cfg["t5_register"]
    cb = meter.get("cb_max_rating_a")
    events = []
    if daily.empty:
        return events

    full_day = daily["n_readings"].to_numpy() >= int(c["min_readings_full_day"])
    advance = daily["day_advance_kwh"].to_numpy(dtype=float)
    amps = daily["mean_amps_sum"].to_numpy(dtype=float)
    load_pct = (amps / 3.0 / cb * 100.0) if cb else np.full(amps.shape, np.nan)

    with np.errstate(invalid="ignore"):
        no_advance = full_day & (advance == 0)
        legacy = no_advance & (amps > float(c["min_amps_a"]))
        normalized = no_advance & (load_pct >= float(c["min_load_pct_cb"]))
    legacy = np.nan_to_num(legacy, nan=False).astype(bool)
    normalized = np.nan_to_num(normalized, nan=False).astype(bool)

    trigger = c["trigger"]
    flags = {"either": legacy | normalized,
             "legacy_amps": legacy,
             "normalized": normalized}[trigger]
    if not flags.any():
        # A meter with no stuck days can still have a register that went backwards.
        return _register_decreases(df, meter, cfg)

    for ep in collapse_days(daily["day_saudi"], flags):
        sl = slice(ep["first_index"], ep["last_index"] + 1)
        w = flags[sl]
        rules = []
        if legacy[sl][w].any():
            rules.append("legacy_amps")
        if normalized[sl][w].any():
            rules.append("normalized")
        ev = _base_event(meter, "T5", "stuck_register", 0,
                         "active_energy_cumulative_kwh", ep, "day")
        ev.update({
            "magnitude": float(np.nanmean(amps[sl][w])),
            "magnitude_unit": "mean_summed_current_A_while_register_frozen",
            "event_class": "ELECTRICAL_FAULT",
            "share_of_window_flagged": float(w.mean()),
            # Both load-evidence measures are recorded on every event.
            "mean_current_a": float(np.nanmean(amps[sl][w])),
            "mean_current_pct_cb": float(np.nanmean(load_pct[sl][w])),
            "load_evidence_rules": "+".join(rules),
            "days_legacy_rule": int(legacy[sl][w].sum()),
            "days_normalized_rule": int(normalized[sl][w].sum()),
            "concurrent_status": "",
            "corroboration": "none",
        })
        events.append(ev)

    events.extend(_register_decreases(df, meter, cfg))
    return events


def _register_decreases(df: pd.DataFrame | None, meter: dict, cfg: dict) -> list[dict]:
    """A cumulative register that goes BACKWARDS, at reading grain.

    This cannot be found at day grain: the daily advance is max(kWh) - min(kWh), which is
    non-negative by construction, so a mid-day decrease is invisible there. It is the one
    register condition the production classifier already catches (`status_kwh = 'Invalid'`),
    so Model 1 reports it as corroborated rather than as a new finding.
    """
    if df is None or df.empty:
        return []
    kwh = df["active_energy_cumulative_kwh"].to_numpy(dtype=float)
    prev = np.concatenate(([np.nan], kwh[:-1]))
    with np.errstate(invalid="ignore"):
        flags = kwh < prev
    flags = np.nan_to_num(flags, nan=False).astype(bool)
    if not flags.any():
        return []

    ep_cfg = cfg["episodes"]
    cb = meter.get("cb_max_rating_a")
    amps_sum = sum(df[PHASE_COLUMNS[p][1]].fillna(0.0) for p in PHASE_COLUMNS).to_numpy()
    load_pct = (amps_sum / 3.0 / cb * 100.0) if cb else np.full(amps_sum.shape, np.nan)

    events = []
    for ep in collapse(df["reading_timestamp_utc"], flags,
                       merge_gap(cfg, "T5"), ep_cfg["min_episode_readings"]):
        sl = slice(ep["first_index"], ep["last_index"] + 1)
        w = flags[sl]
        drop = (prev - kwh)[sl][w]
        ev = _base_event(meter, "T5", "register_decrease", 0,
                         "active_energy_cumulative_kwh", ep, "reading")
        ev.update({
            "magnitude": float(np.nanmean(drop)),
            "magnitude_unit": "mean_kWh_decrease",
            "event_class": "ELECTRICAL_FAULT",
            "share_of_window_flagged": float(w.mean()),
            "mean_current_a": float(np.nanmean(amps_sum[sl][w])),
            "mean_current_pct_cb": float(np.nanmean(load_pct[sl][w])),
            "load_evidence_rules": "",
            "concurrent_status": "Invalid",
            "corroboration": "full",
        })
        events.append(ev)
    return events
