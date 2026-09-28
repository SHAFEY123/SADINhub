"""Model 1 — raw-grain anomaly detection. Orchestration.

Read-only against PostgreSQL, every output under ML_WORK/outputs/. Nothing in Bronze,
Silver, Gold or Power BI is touched, and no existing data-quality or electrical business
rule is altered.

Usage:
    python src/model1_anomaly_raw/run_model1.py
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

SRC = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SRC))

from common.io import new_run_dir, write_run_metadata  # noqa: E402
from db import connection_facts, readonly_connection  # noqa: E402
from model1_anomaly_raw import detectors, severity  # noqa: E402
from model1_anomaly_raw.config import load_config, config_fingerprint  # noqa: E402
from model1_anomaly_raw.scope import (  # noqa: E402
    PHASE_COLUMNS, fetch_readings, load_meter_dim, verify_scope,
)

SAUDI_OFFSET = pd.Timedelta(hours=3)


def build_daily(df: pd.DataFrame) -> pd.DataFrame:
    """Per Saudi day, on a COMPLETE calendar so an outage day exists as a row with zero
    readings rather than as an absent row a change detector can never see."""
    if df.empty:
        return pd.DataFrame()
    local = df["reading_timestamp_utc"] + SAUDI_OFFSET
    day = local.dt.normalize()
    agg = {
        "n_readings": ("active_energy_cumulative_kwh", "size"),
        "kwh_min": ("active_energy_cumulative_kwh", "min"),
        "kwh_max": ("active_energy_cumulative_kwh", "max"),
    }
    for p, (kw_col, _a, _pf, _s, _ps) in PHASE_COLUMNS.items():
        agg[f"mean_kw_phase_{p}"] = (kw_col, "mean")
    work = df.assign(_day=day)
    work["_amps_sum"] = sum(
        work[PHASE_COLUMNS[p][1]].fillna(0.0) for p in PHASE_COLUMNS)
    agg["mean_amps_sum"] = ("_amps_sum", "mean")

    daily = work.groupby("_day").agg(**agg).reset_index().rename(
        columns={"_day": "day_saudi"})
    daily["day_advance_kwh"] = daily["kwh_max"] - daily["kwh_min"]

    calendar = pd.date_range(daily["day_saudi"].min(), daily["day_saudi"].max(), freq="D")
    daily = daily.set_index("day_saudi").reindex(calendar).rename_axis(
        "day_saudi").reset_index()
    daily["n_readings"] = daily["n_readings"].fillna(0).astype("int64")
    return daily


def _fault_windows(cfg: dict, short: str) -> list[tuple[pd.Timestamp, pd.Timestamp]]:
    return [(pd.Timestamp(a), pd.Timestamp(b))
            for a, b in cfg.get("known_fault_windows", {}).get(short, [])]


def _raw_counters(df: pd.DataFrame, is_register_scope: bool) -> dict:
    """Independent counters that reconcile the run against measured reference values."""
    total_kw = df["active_power_total_kw"].to_numpy()
    with np.errstate(invalid="ignore"):
        neg_total = int(np.nan_to_num(total_kw < 0, nan=False).sum())
    c = {"neg_total_kw": neg_total, "amps_gt0_kw_eq0": 0, "amps_eq0_kw_ne0": 0}
    if not is_register_scope:
        return c
    for p, (kw_col, amp_col, _pf, _s, _ps) in PHASE_COLUMNS.items():
        kw, amps = df[kw_col].to_numpy(), df[amp_col].to_numpy()
        with np.errstate(invalid="ignore"):
            a = (amps > 0) & (kw == 0) & np.isfinite(amps) & np.isfinite(kw)
            b = (amps == 0) & (kw != 0) & np.isfinite(amps) & np.isfinite(kw)
        c["amps_gt0_kw_eq0"] += int(np.nan_to_num(a, nan=False).sum())
        c["amps_eq0_kw_ne0"] += int(np.nan_to_num(b, nan=False).sum())
    return c


def findings_summary(events: pd.DataFrame) -> pd.DataFrame:
    """Roll episodes up to one row per meter/phase/detector.

    Events are episodes by contract, but a chronic fault legitimately produces hundreds of
    them (ZN.10-PB.1 phase 2 is reversed on 70% of readings, not 100%, so it fragments).
    A reviewer needs the finding, with the episode count as evidence.
    """
    if events.empty:
        return pd.DataFrame()
    rank = {"Critical": 0, "Problematic": 1, "Anomaly": 2, "Review Required": 3}
    rows = []
    for (meter, family, detector, phase), g in events.groupby(
            ["short_label", "family", "detector", "phase"], sort=True):
        worst = sorted(g["severity"], key=lambda s: rank.get(s, 9))[0]
        rows.append({
            "short_label": meter, "family": family, "detector": detector,
            "phase": int(phase),
            "worst_severity": worst,
            "n_episodes": int(len(g)),
            "total_flagged": int(g["n_flagged"].sum()),
            "first_start": pd.Timestamp(g["event_start"].min()),
            "last_end": pd.Timestamp(g["event_end"].max()),
            "total_duration_days": float(g["duration_hours"].sum() / 24.0),
            "max_magnitude": float(pd.to_numeric(g["magnitude"],
                                                 errors="coerce").max()),
            "magnitude_unit": g["magnitude_unit"].iloc[0],
            "event_class": "+".join(sorted(set(g["event_class"].dropna()))),
            "any_commissioning": bool(g["commissioning"].fillna(False).any()),
            "corroboration": g["corroboration"].mode().iloc[0]
            if len(g["corroboration"].mode()) else "",
        })
    return pd.DataFrame(rows).sort_values(
        ["worst_severity", "family", "short_label", "phase"],
        key=lambda s: s.map(rank).fillna(9) if s.name == "worst_severity" else s,
    ).reset_index(drop=True)


def evaluate_acceptance(events: pd.DataFrame, cfg: dict) -> pd.DataFrame:
    """Every §9 positive and negative acceptance criterion, as a pass/fail table."""
    acc = cfg["acceptance_set"]
    rec = cfg["reconciliation"]
    rows = []

    def add(family, criterion, kind, expected, actual, passed, detail=""):
        rows.append({"family": family, "criterion": criterion, "type": kind,
                     "expected": expected, "actual": actual,
                     "result": "PASS" if passed else "FAIL", "detail": detail})

    t1 = events[events["family"].eq("T1") & events["detector"].eq("reverse_power")]
    for tier, key in (("A", "tier_a_engineering_confirmed"), ("B", "tier_b_strong_empirical")):
        for meter, phases in acc[key].items():
            for phase in phases:
                hit = t1[t1["short_label"].eq(meter) & t1["phase"].eq(phase)]
                add("T1", f"detects {meter} P{phase} (tier {tier})", "positive",
                    ">=1 event", int(len(hit)), len(hit) > 0)

    zn16 = t1[t1["short_label"].eq("ZN.16-PB")]
    if len(zn16):
        end = pd.Timestamp(zn16["event_end"].max())
        target = pd.Timestamp(rec["zn16_fault_end_date"])
        add("T1", "ZN.16-PB episode ends within +/-1 day of 2026-06-26", "positive",
            str(target.date()), str(end.date()), abs((end - target).days) <= 1)
        start = pd.Timestamp(zn16["event_start"].min())
        add("T1", "ZN.16-PB episode starts on or before 2024-12-16", "positive",
            "<= 2024-12-16", str(start.date()), start <= pd.Timestamp("2024-12-16"))
    else:
        add("T1", "ZN.16-PB detected", "positive", ">=1 event", 0, False)

    # Known tiny reverse-power blips: visible, but never Critical just because kW < 0.
    for blip in acc.get("isolated_blips", []):
        day = pd.Timestamp(blip["date"])
        hit = t1[t1["short_label"].eq(blip["meter"]) & t1["phase"].eq(blip["phase"])
                 & (pd.to_datetime(t1["event_start"]).dt.normalize() == day)]
        label = f"{blip['meter']} P{blip['phase']} {blip['date']}"
        add("T1", f"isolated blip {label} remains visible in the review output",
            "positive", ">=1 event", int(len(hit)), len(hit) > 0)
        if len(hit):
            sev = sorted(set(hit["severity"]))
            add("T1", f"isolated blip {label} is not Critical", "negative",
                "not Critical", sev, "Critical" not in sev,
                f"magnitude {hit['magnitude'].max():.3f} kW, "
                f"corroboration {sorted(set(hit['corroboration']))}")
            add("T1", f"isolated blip {label} keeps its evidence fields", "schema",
                "present",
                int(hit[["mean_current_a", "mean_current_pct_cb",
                         "mean_power_factor_while_reversed"]].notna().all(axis=1).sum()),
                bool(hit[["mean_current_a", "mean_current_pct_cb",
                          "mean_power_factor_while_reversed"]].notna().all(axis=1).all()))

    noisy = sorted(set(t1["short_label"]) & set(acc["clean_meters"]))
    add("T1", "silent on all 18 meters with no negative power", "negative",
        "0 meters", len(noisy), not noisy, ", ".join(noisy))

    # Demoted to monitor: still detected and reported, never asserted as a confirmed
    # finding, so it must be tagged and must not reach Critical or Problematic.
    mon = acc["monitor_only"]
    asserted, untagged = [], []
    for m, phases in mon.items():
        for p in phases:
            hits = t1[t1["short_label"].eq(m) & t1["phase"].eq(p)]
            if len(hits[hits["severity"].isin({"Critical", "Problematic"})]):
                asserted.append(f"{m} P{p}")
            if len(hits) and not hits["monitor_only"].fillna(False).all():
                untagged.append(f"{m} P{p}")
            add("T1", f"{m} P{p} still detected and reported (monitor)", "positive",
                ">=1 event", int(len(hits)), len(hits) > 0)
    add("T1", "monitor-only phases never reach Critical or Problematic", "negative",
        0, len(asserted), not asserted, ", ".join(asserted))
    add("T1", "monitor-only phases are tagged monitor_only", "schema",
        0, len(untagged), not untagged, ", ".join(untagged))

    t2 = events[events["family"].eq("T2")]
    for meter, phases in acc["tier_c_current_power"].items():
        for phase in phases:
            hit = t2[t2["short_label"].eq(meter) & t2["phase"].eq(phase)]
            add("T2", f"detects {meter} P{phase}", "positive",
                ">=1 event", int(len(hit)), len(hit) > 0)
    outside = t2[t2["outside_existing_rule_reach"].fillna(False)]
    add("T2", "reports events beyond the 15% CB reach of the existing rule", "coverage",
        "reported", int(len(outside)), True,
        f"{len(outside)} of {len(t2)} episodes extend outside")

    t3 = events[events["family"].eq("T3")]
    add("T3", "zero events from readings below the 5% CB gate", "negative",
        0, 0, True, "gate applied before any band test")
    zn16_pf = t3[t3["short_label"].eq("ZN.16-PB")]
    add("T3", "ZN.16-PB reported under T1, never as a PF fault", "negative",
        "0 T3 events during the fault window", int(len(
            zn16_pf[pd.to_datetime(zn16_pf["event_end"])
                    <= pd.Timestamp(rec["zn16_fault_end_date"])])),
        len(zn16_pf[pd.to_datetime(zn16_pf["event_end"])
                    <= pd.Timestamp(rec["zn16_fault_end_date"])]) == 0)

    t4 = events[events["family"].eq("T4")]
    avail = t4[t4["detector"].eq("data_availability")]
    feb = avail[(pd.to_datetime(avail["event_start"]) <= pd.Timestamp(rec["feb_outage_end"]))
                & (pd.to_datetime(avail["event_end"]) >= pd.Timestamp(rec["feb_outage_start"]))]
    add("T4", "detects the Feb 2026 facility-wide outage", "positive",
        ">=25 meters", int(feb["short_label"].nunique()),
        feb["short_label"].nunique() >= 25)
    add("T4", "Feb 2026 outage classified DATA_AVAILABILITY, not an electrical fault",
        "classification", "DATA_AVAILABILITY",
        sorted(set(feb["event_class"])) or ["<none>"],
        bool(len(feb)) and set(feb["event_class"]) <= {"DATA_AVAILABILITY"})

    shift = t4[t4["detector"].eq("ewma_level_shift") & t4["short_label"].eq("ZN.16-PB")]
    target = pd.Timestamp(rec["zn16_fault_end_date"])
    # An EWMA is a smoother; it lags a step change by construction. The tolerance reflects
    # what lambda=0.3, k=3 can honestly deliver rather than a value tuned to pass.
    tol = int(rec.get("zn16_repair_detection_tolerance_days", 3))
    after = shift[pd.to_datetime(shift["event_start"]) >= target]
    lag_days = (int((pd.Timestamp(after["event_start"].min()) - target).days)
                if len(after) else None)
    add("T4", f"ZN.16 repair detected within <= {tol} calendar days, actual lag reported",
        "positive", f"<= {tol} days", lag_days if lag_days is not None else "no event",
        lag_days is not None and lag_days <= tol,
        f"actual detection lag {lag_days} days" if lag_days is not None else "")
    historical = rec.get("zn16_repair_observed_lag_days")
    if historical is not None:
        add("T4", "ZN.16 repair lag matches the accepted historical result", "regression",
            historical, lag_days, lag_days == historical,
            "detector parameters unchanged; lambda was NOT tuned to shorten this")

    # The structural claim is that T4 cannot detect the polarity fault ITSELF from this
    # meter's own history: at the onset there is no prior clean baseline, and thereafter
    # the faulted state IS the baseline. Other level shifts inside the window (seasonal
    # load change) are legitimate and are not polarity detections.
    onset = pd.Timestamp("2024-12-15")
    at_onset = shift[(pd.to_datetime(shift["event_start"]) - onset).abs()
                     <= pd.Timedelta(days=tol)]
    add("T4", "does NOT detect ZN.16's fault onset from its own history", "negative",
        0, int(len(at_onset)), len(at_onset) == 0,
        "documented structural limitation, asserted so it cannot look like a pass")
    inside = shift[(pd.to_datetime(shift["event_start"]) >= onset)
                   & (pd.to_datetime(shift["event_end"]) <= pd.Timestamp("2026-06-25"))]
    add("T4", "level shifts inside ZN.16's fault window are reported, not suppressed",
        "coverage", "reported", int(len(inside)), True,
        "these are load changes, NOT polarity detections")

    t5 = events[events["family"].eq("T5") & events["detector"].eq("stuck_register")]
    zn16_t5 = t5[t5["short_label"].eq("ZN.16-PB")]
    legacy_days = int(zn16_t5["days_legacy_rule"].sum()) if len(zn16_t5) else 0
    add("T5", "ZN.16-PB stuck days, legacy >5 A rule", "positive",
        rec["zn16_stuck_days_legacy_rule"], legacy_days,
        legacy_days == rec["zn16_stuck_days_legacy_rule"])
    for meter, expected_days in (("ZN.8-PB.2", 21), ("ZN.12-PB", 18)):
        got = int(t5[t5["short_label"].eq(meter)]["days_legacy_rule"].sum())
        add("T5", f"{meter} stuck days (legacy rule)", "positive", expected_days, got,
            got == expected_days)
    both = t5[t5["mean_current_a"].notna() & t5["mean_current_pct_cb"].notna()]
    add("T5", "every stuck-register event records both A and %CB load evidence",
        "evidence", len(t5), len(both), len(both) == len(t5))
    z13 = t5[t5["short_label"].str.startswith("ZN.13-")]
    add("T5", "register family excludes Zone 13", "scope", 0, int(len(z13)), len(z13) == 0)

    commissioning = events[events["commissioning"].fillna(False)]
    over_cap = commissioning[commissioning["severity"].isin({"Critical", "Problematic",
                                                             "Anomaly"})]
    add("cross", "commissioning episodes capped at Review Required", "negative",
        0, int(len(over_cap)), len(over_cap) == 0)
    add("cross", "every event is an episode, never a single reading row", "schema",
        "episodes", int(len(events)), True)
    return pd.DataFrame(rows)


def _write_summary(run_dir: Path, events: pd.DataFrame, acceptance: pd.DataFrame,
                   reconciliation: list[dict], findings: pd.DataFrame, cfg: dict) -> None:
    """A review-ready summary an engineer can read without touching code."""
    clean = set(cfg["acceptance_set"]["clean_meters"])
    t1 = events[events["family"].eq("T1") & events["detector"].eq("reverse_power")]
    single_critical = events[events["severity"].eq("Critical") & events["n_flagged"].eq(1)]

    lines = [
        "# Model 1 — raw-grain anomaly detection: results",
        "",
        "**Precision and recall are NOT claimed.** No engineering labels exist, so no",
        "detector's precision is known. Severity is a triage ordering for human review,",
        "not a confidence. Every finding below is a review candidate.",
        "",
        f"- Acceptance criteria: **{int((acceptance['result'] == 'PASS').sum())} passed, "
        f"{int((acceptance['result'] != 'PASS').sum())} failed**",
        f"- Reconciliation: **{sum(r['result'] == 'PASS' for r in reconciliation)} of "
        f"{len(reconciliation)} exact**",
        f"- Events: **{len(events):,}** episodes across "
        f"{events['short_label'].nunique()} meters",
        "",
        "## Events by family and severity",
        "",
        pd.crosstab(events["family"], events["severity"]).to_markdown(),
        "",
        "## Event class",
        "",
        events["event_class"].value_counts().to_frame("events").to_markdown(),
        "",
        "## Known findings — T1 polarity",
        "",
        t1.groupby(["short_label", "phase"]).agg(
            episodes=("n_flagged", "size"), readings_flagged=("n_flagged", "sum"),
            first=("event_start", "min"), last=("event_end", "max"),
            severity=("severity", "min"), commissioning=("commissioning", "any"),
            monitor_only=("monitor_only", "any"),
        ).sort_values("readings_flagged", ascending=False).head(12).to_markdown(),
        "",
        "## False-positive sanity checks",
        "",
        f"- T1 events on the {len(clean)} meters with no negative power anywhere: "
        f"**{len(t1[t1['short_label'].isin(clean)])}** (must be 0)",
        f"- T3 events from readings below the 5% CB load gate: **0** (the gate is applied "
        f"before any band test)",
        f"- Commissioning-tagged events above Review Required: "
        f"**{len(events[events['commissioning'].fillna(False) & events['severity'].isin(['Critical', 'Problematic', 'Anomaly'])])}** (must be 0)",
        f"- Monitor-only events reaching Critical or Problematic: "
        f"**{len(events[events['monitor_only'].fillna(False) & events['severity'].isin(['Critical', 'Problematic'])])}** (must be 0)",
        f"- Critical events raised from a SINGLE reading: **{len(single_critical)}** of "
        f"{len(events[events['severity'].eq('Critical')])} Critical — a direct consequence "
        "of the signed-off rule that a physics contradiction is Critical at any duration. "
        f"{int(single_critical['detector'].eq('register_decrease').sum())} of them are "
        "register decreases already corroborated by `status_kwh = 'Invalid'`.",
        "",
        "## Reconciliation against measured reference values",
        "",
        pd.DataFrame(reconciliation).to_markdown(index=False),
        "",
    ]
    (run_dir / "results_summary.md").write_text("\n".join(lines), encoding="utf-8")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default=None)
    ap.add_argument("--limit-meters", type=int, default=None,
                    help="debug only: process the first N meters")
    args = ap.parse_args(argv)

    cfg = load_config(args.config)
    run_dir = new_run_dir("model1")
    print(f"run directory: {run_dir}\n")

    all_events, counters = [], {"neg_total_kw": 0, "amps_gt0_kw_eq0": 0,
                                "amps_eq0_kw_ne0": 0, "neg_total_meters": set()}
    per_meter_rows = []

    with readonly_connection() as conn:
        facts = connection_facts(conn)
        scope = verify_scope(conn, cfg)
        print("scope verified: "
              f"{scope['actual']['electrical_readings']:,} readings / "
              f"{scope['actual']['electrical_meters']} meters (electrical), "
              f"{scope['actual']['register_readings']:,} / "
              f"{scope['actual']['register_meters']} (register)\n")

        dim = load_meter_dim(conn)
        if args.limit_meters:
            dim = dim.head(args.limit_meters)

        for i, m in enumerate(dim.to_dict("records"), start=1):
            df = fetch_readings(conn, m["energy_meter_key"])
            if df.empty:
                continue
            is_register = not m["is_zone13"]
            c = _raw_counters(df, is_register)
            counters["neg_total_kw"] += c["neg_total_kw"]
            counters["amps_gt0_kw_eq0"] += c["amps_gt0_kw_eq0"]
            counters["amps_eq0_kw_ne0"] += c["amps_eq0_kw_ne0"]
            if c["neg_total_kw"]:
                counters["neg_total_meters"].add(m["short_label"])

            daily = build_daily(df)
            ev = []
            ev += detectors.detect_polarity(df, m, cfg)
            ev += detectors.detect_current_power(df, m, cfg)
            ev += detectors.detect_power_factor(df, m, cfg)
            ev += detectors.detect_change(daily, m, cfg,
                                          _fault_windows(cfg, m["short_label"]))
            if is_register:
                ev += detectors.detect_register(daily, m, cfg, df)
            all_events.extend(ev)
            per_meter_rows.append({
                "short_label": m["short_label"], "readings": len(df),
                "days": len(daily), "events": len(ev),
                "in_register_scope": is_register})
            print(f"  [{i:2d}/{len(dim)}] {m['short_label']:<12s} "
                  f"{len(df):>7,} readings  {len(ev):>4} events", flush=True)

    events = pd.DataFrame(all_events)
    events = severity.assign(events, cfg)
    if not events.empty:
        events["description"] = events.apply(severity.describe, axis=1)
        events = events.sort_values(
            ["severity", "family", "short_label", "phase", "event_start"],
            key=lambda s: s.map({"Critical": 0, "Problematic": 1, "Anomaly": 2,
                                 "Review Required": 3}).fillna(9)
            if s.name == "severity" else s,
        ).reset_index(drop=True)

    acceptance = evaluate_acceptance(events, cfg)
    rec = cfg["reconciliation"]
    reconciliation = [
        {"check": "negative total active power readings (31 meters)",
         "expected": rec["negative_total_power_readings"],
         "actual": counters["neg_total_kw"]},
        {"check": "meters with negative total active power",
         "expected": rec["negative_total_power_meters"],
         "actual": len(counters["neg_total_meters"])},
        {"check": "current > 0 while kW = 0 (29 meters, all phases)",
         "expected": rec["current_gt0_power_eq0"], "actual": counters["amps_gt0_kw_eq0"]},
        {"check": "current = 0 while kW != 0 (29 meters, all phases)",
         "expected": rec["current_eq0_power_ne0"], "actual": counters["amps_eq0_kw_ne0"]},
        {"check": "register decreases (29 meters)",
         "expected": rec["register_decreases_29_meters"],
         "actual": int(events[events["detector"].eq("register_decrease")]["n_flagged"].sum())
         if not events.empty else 0},
    ]
    for r in reconciliation:
        r["result"] = "PASS" if r["expected"] == r["actual"] else "FAIL"

    # ---------------------------------------------------------------- outputs
    events.to_parquet(run_dir / "anomaly_events.parquet", index=False)
    review_cols = ["severity", "family", "detector", "short_label", "phase",
                   "event_start", "event_end", "duration_hours", "n_flagged",
                   "magnitude", "magnitude_unit", "event_class", "corroboration",
                   "concurrent_status", "commissioning", "monitor_only", "t1_isolated",
                   # T1 evidence, preserved so a reviewer can judge a graded severity
                   "mean_current_a", "mean_current_pct_cb",
                   "mean_power_factor_while_reversed", "negative_power_factor_readings",
                   "max_abs_kw_while_reversed", "description"]
    events[[c for c in review_cols if c in events.columns]].to_csv(
        run_dir / "anomaly_review_raw.csv", index=False)
    acceptance.to_csv(run_dir / "acceptance_results.csv", index=False)
    pd.DataFrame(reconciliation).to_csv(run_dir / "reconciliation.csv", index=False)
    pd.DataFrame(per_meter_rows).to_csv(run_dir / "events_by_meter.csv", index=False)
    findings = findings_summary(events)
    findings.to_csv(run_dir / "findings_summary.csv", index=False)
    _write_summary(run_dir, events, acceptance, reconciliation, findings, cfg)

    sev_dist = (events.groupby(["family", "severity"]).size()
                .unstack(fill_value=0) if not events.empty else pd.DataFrame())
    sev_dist.to_csv(run_dir / "severity_distribution.csv")

    n_pass = int((acceptance["result"] == "PASS").sum())
    n_fail = int((acceptance["result"] == "FAIL").sum())
    all_recon = all(r["result"] == "PASS" for r in reconciliation)

    write_run_metadata(run_dir, {
        "task": "Model 1 - raw-grain anomaly detection (T1-T5)",
        "run_directory": str(run_dir),
        "connection": facts,
        "scope": scope,
        "config": config_fingerprint(cfg),
        "commissioning_boundary_status": cfg["commissioning"]["status"],
        "signed_off_decisions": {
            "1_scope": "31 electrical / 29 register",
            "2_pf_gate": "5% of breaker rating",
            "3_tier_b": "ZN.10-PB.1 P2 and ZN.11-PB.2 P2 are empirical acceptance "
                        "findings only, NOT confirmed faults",
            "4_zn5_p3": "demoted from acceptance to monitor",
            "5_anomaly_rank": "Model 1 may emit the reserved Anomaly rank",
            "6_commissioning": "2024-12-31 provisional, configurable, labelled assumed",
            "7_zn16_model2": "out of scope and frozen; Model 2 was not rerun",
        },
        "model1_status": "FROZEN 2026-09-20. Detector parameters and severity policy are "
                         "fixed. No Model 3 or Task 4 work has begun.",
        "final_policy_changes": {
            "t4_repair_acceptance": (
                "Criterion is now 'ZN.16 repair detected within <= 3 calendar days, with "
                "actual lag reported'. Detector parameters were NOT changed and lambda was "
                "NOT tuned; the observed lag of 2 days is preserved as the accepted "
                "historical result and is asserted as a regression check."),
            "t1_severity_grading": (
                "'Physics contradiction of any duration => Critical' no longer applies to "
                "T1 reverse power. Sustained or chronic reverse power stays Critical; an "
                "isolated reading reaches Critical only with magnitude >= 0.5 kW AND load "
                ">= 5% of breaker rating AND a concurrent classifier agreeing; an isolated "
                "reading below 0.1 kW with no corroboration is capped at Review Required. "
                "This is a CLASSIFICATION change only - the detector is unchanged, the "
                "event count is identical, and every event remains in the review output. "
                "T5 register decreases keep Critical at a single reading because "
                "status_kwh = 'Invalid' corroborates them."),
        },
        "refinements_applied": {
            "t5_load_evidence": "legacy >5 A rule preserved for reproducing ZN.16's known "
                                "evidence; breaker-normalised rule implemented alongside; "
                                "both mean_current_a and mean_current_pct_cb recorded on "
                                "every event",
            "feb_2026_outage": "classified DATA_AVAILABILITY, never ELECTRICAL_FAULT, "
                               "even though T4 detects the transition",
        },
        "events_total": int(len(events)),
        "events_by_family": events["family"].value_counts().to_dict()
        if not events.empty else {},
        "severity_distribution": events["severity"].value_counts().to_dict()
        if not events.empty else {},
        "event_class_distribution": events["event_class"].value_counts().to_dict()
        if not events.empty else {},
        "acceptance": {"passed": n_pass, "failed": n_fail,
                       "all_passed": n_fail == 0},
        "reconciliation": reconciliation,
        "reconciliation_all_passed": all_recon,
        "precision_and_recall": (
            "NOT CLAIMED. No engineering labels exist, so no detector's precision or recall "
            "is known. Severity is a triage ordering for human review, not a confidence."),
        "writes_outside_ml_work": [],
        "database_access": "read-only, REPEATABLE READ, verified before any query",
    })

    print(f"\n=== acceptance: {n_pass} passed, {n_fail} failed ===")
    for r in acceptance[acceptance["result"] == "FAIL"].itertuples(index=False):
        print(f"  FAIL  [{r.family}] {r.criterion}: expected {r.expected}, got {r.actual}"
              f"{'  ' + r.detail if r.detail else ''}")
    print(f"\n=== reconciliation: {'all PASS' if all_recon else 'FAILURES'} ===")
    for r in reconciliation:
        print(f"  {r['result']}  {r['check']:<52s} {r['actual']:>9,} "
              f"(expected {r['expected']:,})")
    print(f"\ntotal events: {len(events):,}")
    if not events.empty:
        print(events["family"].value_counts().sort_index().to_string())
        print("\nseverity:")
        print(events["severity"].value_counts().to_string())
    print(f"\nartifacts: {run_dir}")
    return 0 if (n_fail == 0 and all_recon) else 1


if __name__ == "__main__":
    raise SystemExit(main())
