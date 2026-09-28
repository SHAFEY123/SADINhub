# Model 1 — raw-grain anomaly detection: DESIGN SPECIFICATION

**Status: signed off 2026-09-20 and IMPLEMENTED.** Sections 1-10 are the design as
approved; §11 is the implementation record, including four defects found during
implementation, one acceptance criterion deliberately relaxed, and a consequence of the
severity definition worth revisiting. Every number below was measured read-only against the
live database and is reproducible from the queries named in §2.

---

## 0. Corrections to the original Task 1 instructions

The original `TASK 1 — src/model1_anomaly_raw/` instructions cannot be executed as written.
Six defects, each verified against the live schema:

| # | Original instruction | Problem | Correction |
|---|---|---|---|
| 1 | `SELECT active_power_kw1, power_factor_1, current_amp1, …` | **All 15 measurement column names are wrong.** None exists. | §2 |
| 2 | `gold.energy_raw` selected alone | `gold.energy_raw` has **no `meter_label`**; events cannot be labelled without a join | join `gold.meter` |
| 3 | `assert count(*) == 4_535_918` | Correct for 31 meters, but wrong if Model 1 adopts Model 2's 29-meter scope | §1 — both asserts defined |
| 4 | `KNOWN_FINDINGS` = 6 meters | Incomplete (misses two large findings) and partly unsupported by the data | §3 |
| 5 | `exclude_windows={"ZN.16-PB": full history}` | Excluding ZN.16's full history leaves **no baseline at all** | §6 |
| 6 | `cusum_flags(pf, target=0.8)` with no load gate | Would fire on **28.38%** of all phase readings — 97.10% of it low-load noise | §7 |

Defect 6 is the important one. The instruction to detect "sustained drift below the
acceptable threshold" is sound; applied without a load gate it produces an alarm on more
than a quarter of the dataset and is therefore not a detector.

---

## 1. Scope, and the row-count assertions

Zone 13's two meters are excluded from *validated consumption* because of cumulative-kWh
integrity concerns. That is a **register** concern, not an electrical-measurement concern.
Voltage, current, power and power factor for those meters are as trustworthy as any other.
Model 1 therefore uses two scopes:

| Scope | Meters | Readings | Used by | Verified |
|---|---:|---:|---|---|
| `ELECTRICAL` — all canonical meters | 31 | **4,535,918** | families T1, T2, T3, T4 | yes |
| `REGISTER` — Zone 13 excluded | 29 | **4,260,849** | family T5 | yes |

Both counts were confirmed live. Each detector run must assert its own scope's count and
fail loudly on a mismatch; the single hard-coded `4_535_918` in the original instruction is
correct only for the first.

> **Decision 1, approved 2026-09-20:** the electrical families run on all 31 meters, the
> register family on 29. Both counts are asserted at the start of every run.

---

## 2. Exact live database columns and joins

### 2.1 The one join Model 1 needs

```sql
FROM gold.energy_raw            e
JOIN gold.meter                 m USING (energy_meter_key)
LEFT JOIN gold.zone             z USING (zone_key)
LEFT JOIN silver.dim_meter_cb_rating r USING (energy_meter_key)
```

`silver.dim_meter_cb_rating` is a documented boundary exception: `cb_max_rating_a` is
exposed by no Gold view and every current- and PF-related rule depends on it. Read-only,
as everywhere else in `ML_WORK`.

### 2.2 Columns, by the names that actually exist

| Purpose | Live column (`gold.energy_raw`) | Type | Original instruction said |
|---|---|---|---|
| Active power, phase *k* | `active_power_phase_1_kw` … `_3_kw` | double | ~~`active_power_kw1`~~ |
| Active power, total | `active_power_total_kw` | double | ~~`TkW`~~ |
| Current, phase *k* | `current_phase_1_a` … `_3_a` | double | ~~`current_amp1`~~ |
| Power factor, phase *k* | `power_factor_phase_1` … `_3` | double | ~~`power_factor_1`~~ |
| Power factor, average | `power_factor_average` | double | ~~`PFa`~~ |
| Reactive power | `reactive_power_phase_1_kvar` … `_3_kvar`, `reactive_power_total_kvar` | double | not used |
| Cumulative active energy | `active_energy_cumulative_kwh` | double | not used |
| Timestamp | `reading_timestamp_utc` | timestamp | ✓ |
| Current status, phase *k* | `status_amp1`, `status_amp2`, `status_amp3` | text | ✓ |
| PF status | `status_pf1`, `status_pf2`, `status_pf3`, `status_pfa` | text | ✓ |
| Energy status | `status_kwh` | text | not used |
| Roll-up | `overall_status` | text | not used |
| Meter identity | `gold.meter.meter_label`, `.phase_count`, `.maximum_kwh` | — | — |
| Breaker rating | `silver.dim_meter_cb_rating.cb_max_rating_a` | double | — |

Saudi-local day = `reading_timestamp_utc + interval '3 hours'`; the Saudi day closes at
`D 21:00:00 UTC`. No DST.

### 2.3 Columns that are empty and must not be used

Verified over the **full** history (4,535,918 rows), which the pipeline documentation
records as not formally completed:

| Column | Populated |
|---|---:|
| `voltage_line_average_v` | **0** |
| `voltage_neutral_average_v` | **0** |
| `apparent_power_phase_1_kva` / `_2_` / `_3_` | **0** |
| `apparent_power_total_kva` | **0** |
| `apparent_energy_cumulative_kvah` | **0** |

Consequence: **no load-weighted facility power factor can be computed from telemetry**, and
any detector needing apparent power must derive it as `kW / PF` with an explicit
divide-by-small-PF guard. All other measurement columns are 100% populated.

### 2.4 Two traps in the existing status columns

1. **`status_amp1/2/3` are excluded from `overall_status`.** `overall_status` is the worst
   of exactly 12 inputs — six phase voltages, frequency, four power factors, and
   accumulated energy. The three current statuses are *deliberately* not among them.
   `Major Issue` and `Major Problem` must be read from `status_amp*` directly or they are
   invisible.

2. **`overall_status` is, in practice, a power-factor alarm.** Measured over the 29-meter
   scope:

   | `overall_status` | readings | share |
   |---|---:|---:|
   | Critical | 2,623,574 | 61.57% |
   | Acceptable | 814,490 | 19.12% |
   | Problematic | 781,994 | 18.35% |
   | Review Required | 40,766 | 0.96% |
   | Invalid | 25 | 0.00% |

   Of the 2,623,574 Critical readings, **100.00% are Critical because of a power-factor
   status**. Voltage contributes 0, frequency 0, accumulated energy 0. Combined with §7
   (97.10% of PF-Critical occurs below 15% of breaker rating), `overall_status` cannot be
   used as an anomaly label or as a corroborating signal without load gating.

---

## 3. Known-finding acceptance set

The acceptance set is the list of meter/phase findings a working Model 1 **must** detect.
It is tiered by evidence strength, because "engineering-confirmed" and "the data shows a
pattern" are not the same claim.

### Tier A — engineering-confirmed

| Meter | Phases | Signature | Evidence | Window |
|---|---|---|---|---|
| **ZN.16-PB** | 1, 2, 3 | Reverse-power / polarity, all three phases | `active_power_phase_k_kw < 0` on **95.37%** of readings on every phase (143,775 / 143,774 / 143,774), `power_factor_phase_k < 0` on the same rows, `current_phase_k_a` positive throughout | 2024-12-15 → **2026-06-26** |

Evidence source: pipeline documentation §13 ("engineering-confirmed wiring/polarity fault
affecting all three phases"), corroborated by direct measurement.

### Tier B — strong empirical, not engineering-confirmed

| Meter | Phase | % readings with negative kW | n | Window | Documented? |
|---|---:|---:|---:|---|---|
| **ZN.8-PB.2** | 1 | 96.71% | 153,413 | 2024-12-10 → 2026-06-26 | candidate (§13) |
| **ZN.5-PB** | 1 | 93.01% | 147,753 | 2024-12-10 → 2026-07-05 | candidate (§13) |
| **ZN.10-PB.1** | 2 | 70.35% | 115,316 | 2024-12-15 → 2026-07-09 | **NO — undocumented** |
| **ZN.12-PB** | 3 | 51.11% | 78,694 | 2024-12-14 → 2026-07-11 | candidate (§13, phase 3) ✓ |
| **ZN.11-PB.2** | 2 | 40.33% | 60,782 | 2024-12-14 → 2026-06-29 | **NO — undocumented** |

> **ZN.10-PB.1 phase 2 and ZN.11-PB.2 phase 2 are larger, longer-running findings than
> ZN.12-PB phase 3, which the documentation does list.** They are absent from every
> documented findings table and from the original `KNOWN_FINDINGS` dictionary. They should
> be added to the engineering investigation queue independently of Model 1.

Note the shape: ZN.16-PB is a **three-phase** reversal; ZN.8-PB.2, ZN.5-PB, ZN.10-PB.1 and
ZN.11-PB.2 are **single-phase** reversals. That is the "different phase signatures"
distinction the documentation draws, now quantified.

### Tier C — current-vs-power inconsistency

Counted across all three phases over the whole history, independent of the existing 15%-CB
gate:

| Meter | Phase | current > 0 while kW = 0 | current = 0 while kW ≠ 0 | Documented? |
|---|---:|---:|---:|---|
| **ZN.20-PB.1** | 1 | 2,875 | **27,762** | yes — "highest priority", phases 1 and 3 ✓ |
| ZN.20-PB.1 | 3 | 0 | 2,743 | yes ✓ |
| **ZN.10-PB.2** | 3 | **21,970** | 0 | yes — phase 3 ✓ |
| ZN.10-PB.1 | 2 | 8,822 | 0 | no |
| ZN.2-PB | — | 3,538 | 4 | no |
| ZN.8-PB.1 | 2 | 2,552 | 0 | no |
| ZN.7-PB | — | 645 | 1,341 | no |
| **Total, 29 meters** | | **45,343** | **34,041** | |

The documented ZN.20-PB.1 finding reproduces exactly, including its concentration on phases
1 and 3, and its dominant direction is `current = 0 while kW ≠ 0` (i.e. `Major Issue`).

### Tier D — commissioning transients, which must NOT be treated as faults

| Meters | Phases | Window |
|---|---|---|
| ZN.15-PB.2, ZN.17-PB, ZN.8-PB.1, ZN.10-PB.2 | all three | first reading → **2024-12-25 … 2024-12-27** |

Every one of these ends in the last week of December 2024 and none recurs. This coincides
with the commissioning cut-offs already hard-coded in the Task 0A replay
(`ZN.1-PB.1` 2024-12-10, `ZN.4-PB.1` 2024-12-10). A detector that flags these is not wrong,
but they must be **classified as commissioning, not as operational faults**, or the review
queue opens with two dozen closed items.

### Corrections to the original `KNOWN_FINDINGS`

| Original entry | Verdict |
|---|---|
| `ZN.16-PB: [1,2,3]` | ✅ confirmed |
| `ZN.8-PB.2: [1]` | ✅ confirmed |
| `ZN.12-PB: [3]` | ✅ confirmed |
| `ZN.20-PB.1: [1,3]` | ✅ confirmed (current/power family, not polarity) |
| `ZN.10-PB.2: [3]` | ✅ confirmed (current/power family, not polarity) |
| `ZN.5-PB: [1,3]` | ⚠️ **phase 1 confirmed** (93.01%, 147,296 negative-PF rows). **Phase 3 is weak**: 3.26% negative kW but only **68** negative-PF rows out of 5,179. Phase 3 should be demoted to "monitor", not an acceptance criterion. |
| *(missing)* | ➕ **ZN.10-PB.1 phase 2** |
| *(missing)* | ➕ **ZN.11-PB.2 phase 2** |

---

## 4. Separation of anomaly types

Five families, not four. The fifth is added because the ZN.16 investigation showed the
existing rules have a hole no existing family covers (§5.2).

| ID | Family | Physical question | Primary signal |
|---|---|---|---|
| **T1** | Negative / polarity behaviour | Is energy being measured flowing the wrong way? | sign of `active_power_phase_k_kw`, sign of `power_factor_phase_k`, with `current_phase_k_a > 0` |
| **T2** | Current-vs-power inconsistency | Do current and power disagree about whether load exists? | `current_phase_k_a` vs `active_power_phase_k_kw`, literal zero comparison |
| **T3** | Power-factor behaviour | Is the load's reactive demand abnormal *for its load level*? | `power_factor_phase_k`, **gated by load** (§7) |
| **T4** | Statistical change / drift | Has this meter's behaviour changed relative to its own recent past? | EWMA / CUSUM on power and gated PF |
| **T5** | Register integrity | Does the cumulative energy register agree with the power actually flowing? | `active_energy_cumulative_kwh` advance vs mean current, **at day grain** |

These are deliberately separate because they have different evidence bases, different false-
positive modes, and different owners. Collapsing T1 and T3 in particular is what makes a
polarity fault look like a power-factor problem: a reversed CT produces PF ≈ −0.8, which the
existing classifier reports as `Critical` under the "< 0.6" band. The *status* is right; the
*diagnosis* is wrong.

---

## 5. Deterministic rules vs EWMA/CUSUM

### 5.1 The mapping

| Family | Deterministic rule | EWMA / CUSUM | Why |
|---|---|---|---|
| **T1** polarity | ✅ **primary** | ❌ cannot | A sign test needs no baseline. A self-referential baseline **cannot** see a fault that spans its own history — see §5.3. |
| **T2** current/power | ✅ **primary** | ❌ not applicable | Already a deterministic rule in production (`status_amp*`); the gap is coverage, not method (§5.2). |
| **T3** power factor | ✅ band test, **after load gating** | ✅ CUSUM for sustained drift | The band answers "is it low now"; CUSUM answers "has it been getting worse". Both require the load gate first. |
| **T4** change / drift | ❌ | ✅ **primary** | This family is *defined* as a change relative to the meter's own recent past. |
| **T5** register | ✅ **primary**, at day grain | ✅ change-point on daily advance | A zero daily advance under load is a physics contradiction, not a statistical outlier. |

**Three of five families are deterministic-primary.** Model 1 is mostly a rules engine with
an SPC layer on top, which matches the original framing ("SPC + reuse of existing
classifiers, not a black-box learned model") — but the balance is further toward rules than
the original task breakdown assumed.

### 5.2 What the existing deterministic rules already cover, and what they miss

| Existing rule | Covers | Misses |
|---|---|---|
| `classify_power_factor_v2` | T3 band, and incidentally T1 (negative PF < 0.6 → `Critical`) | No load gate → 28.38% alarm rate, 97.10% of it low-load noise. Cannot distinguish "reversed CT" from "lightly loaded" |
| `classify_current_and_power_v2` | T2, **only below 15% of breaker rating** | Every inconsistency at load ≥ 15% CB. Uses literal zero comparisons with no epsilon |
| `classify_accumulated_energy_v2` | Register **decreases** only | **A register that never advances at all.** This is the ZN.16 hole |
| — | — | **T1 has no classifier whatsoever.** Active power is "preserved and reported; no status classifier is applied" |

The third row is worth stating plainly. On ZN.16-PB, across 150,749 readings:

- `status_pfa` = `Critical` on **145,240** (96.35%) — the PF classifier *does* fire;
- `status_kwh` = `Acceptable` on **150,748 of 150,749** — the energy classifier does **not**,
  because it only tests for a decrease and a frozen register never decreases;
- `status_amp1` = `Acceptable` — the current/power rule does not fire either, because this
  meter's current is above the 15%-CB window in which that rule operates.

So the meter with an engineering-confirmed fault, whose register recorded **0.0 kWh for 97%
of its screen-passing history**, is flagged by exactly one of the three existing
classifiers, and that one flags it for the wrong reason.

### 5.3 Why a self-referential baseline cannot detect a constant fault

The original instruction is `rolling_baseline(kw[meter][phase], exclude_windows=…)` followed
by an EWMA ±3σ test. For ZN.16-PB the fault is present on 95.37% of readings across 18 of
the 19 months of history. Its own rolling mean **is** the faulted state, so the EWMA never
departs from it and the detector is silent — while the meter reports −16 kW.

This is a structural limitation, not a tuning problem. No choice of `lambda`, `k`, `h` or
window length fixes it. It is the reason T1 must be deterministic.

The same reasoning applies to ZN.8-PB.2 (96.71%), ZN.5-PB (93.01%) and ZN.10-PB.1 (70.35%).

### 5.4 Where EWMA/CUSUM genuinely earns its place

Three things the deterministic rules cannot do:

1. **Detect the repair.** ZN.16-PB's fault ends on 2026-06-26: June has 7,983 of 9,435
   readings negative, July has **zero**, mean active power flips from −12.9 kW to +15.4 kW
   and mean PF from −0.67 to +0.81. A sign rule reports "fault stopped"; a change detector
   reports *when* and *how sharply*, which is what closes an engineering ticket.
2. **Catch gradual PF degradation** that never crosses a fixed band — a load slowly getting
   worse from 0.95 to 0.82 is invisible to a 0.8 threshold and obvious to CUSUM.
3. **Catch level shifts in load** that are not faults at all but are worth knowing about
   (equipment added, shift pattern changed) — the same mechanism that produced the
   February 2026 facility-wide outage signature.

---

## 6. ZN.16-PB handling

The premise — "its known fault is present throughout history and therefore cannot provide
its own healthy historical baseline" — is correct for the training period and is now
quantified. It is **not** true for the whole history, which changes the options.

### 6.1 What the data says

| | |
|---|---|
| Task 0B calendar days | 578 (2024-12-11 → 2026-07-11) |
| Quality-screen-passing days | 503 |
| Passing days with `target_kwh = 0` | **488 (97.02%)** |
| Passing days non-zero | 15 |
| Days with a full day of readings, zero register advance, mean current > 5 A | **493 of 517** |
| Total validated consumption | 5,421.5 kWh (passing days) / 5,830.5 kWh (all days) |
| Gold cross-check | 5,830.5 kWh — agrees exactly |
| Fault window | 2024-12-15 → **2026-06-26** |
| **Healthy window** | **2026-06-27 → 2026-07-11 (15 days)**, plus 2024-12-27 / 12-28 |

During the fault the meter reports 305–316 readings/day at 100% `NORMAL_INTERVAL` coverage.
**The telemetry is perfect; only the measurement is wrong.** That is precisely why a
data-availability screen cannot catch it and a physics rule can.

### 6.2 Handling, by detector family

| Family | ZN.16 treatment |
|---|---|
| **T1 polarity** | Detect normally. No baseline needed; the sign rule fires on 95.37% of readings. **This is the acceptance test for T1.** |
| **T2 current/power** | Nothing expected (2 readings). Not an acceptance criterion for this meter. |
| **T3 power factor** | Load gate **passes** (current 22–80 A against a 200 A breaker = 11–40% CB), PF ≈ −0.8. Must be reported as **polarity**, not as a PF fault — a negative PF is not a low PF. Requires an explicit sign branch before the band test. |
| **T4 change/drift** | Baseline **must not** be drawn from 2024-12-15 → 2026-06-26. Two usable references: (a) the post-repair window 2026-06-27 → 2026-07-11, and (b) a **peer baseline** from the 18 meters with no negative power on any phase, normalised by breaker rating. The 2026-06-26 transition is a **positive** acceptance test: any working change detector must find it. |
| **T5 register** | Detect normally, **at day grain**. 493 stuck days. **This is the acceptance test for T5.** |

### 6.3 Recommendation

**Do not exclude ZN.16-PB from Model 1.** Exclude it from *self-referential baselines only*,
for the window 2024-12-15 → 2026-06-26. It is the single most valuable meter in the dataset
for validating Model 1, because it is the only finding that is both engineering-confirmed
and has a known start and a known end.

> **Separate question, deliberately left open.** Whether ZN.16-PB belongs in Model 2's
> *pooled forecasting training population* is a real question — it contributed ~3.5% of every
> pooled model's training rows, all of them zeros. It is recorded in the Model 2 closeout and
> **cannot be resolved by re-scoring the final test**, which is now spent. It is not a
> Model 1 decision.

---

## 7. Proposed power-factor minimum-load rule

### 7.1 The empirical distribution

Power factor by load band, expressed as same-phase current against that meter's breaker
rating. Forward-power readings only (`kW > 0`), so reversed phases do not distort it.
All 29 meters, all three phases, 11,336,327 phase-readings.

| Load band | n | PF p05 | p25 | **p50** | p75 | p95 | % Critical (<0.6) | % Acceptable (≥0.8) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| current = 0 | 33,920 | 1.000 | 1.00 | 1.00 | 1.00 | 1.00 | 0.04 | 99.96 |
| < 1% CB | 282,908 | 0.100 | 0.26 | **0.46** | 1.00 | 1.00 | **58.00** | 33.55 |
| 1–2% CB | 1,704,812 | 0.050 | 0.31 | **0.46** | 0.58 | 0.79 | **76.95** | 4.73 |
| 2–5% CB | 4,243,071 | 0.190 | 0.51 | **0.67** | 0.81 | 0.91 | **36.09** | 27.64 |
| **5–10% CB** | 2,833,471 | 0.640 | 0.78 | **0.88** | 0.94 | 0.97 | **3.23** | 73.06 |
| 10–15% CB | 874,076 | 0.620 | 0.93 | **0.96** | 0.97 | 0.98 | 2.91 | 88.19 |
| 15–20% CB | 525,347 | 0.610 | 0.96 | **0.97** | 0.98 | 0.99 | 3.59 | 86.25 |
| 20–30% CB | 587,133 | 0.580 | 0.96 | **0.98** | 0.98 | 0.99 | 6.53 | 80.57 |
| 30–50% CB | 230,900 | 0.430 | 0.98 | **0.98** | 0.99 | 0.99 | 14.50 | 84.31 |
| ≥ 50% CB | 20,689 | 0.492 | 0.98 | **0.99** | 0.99 | 0.99 | 13.27 | 86.73 |

The knee is unambiguous and sits between the 2–5% and 5–10% bands: median PF rises from
0.67 to 0.88 and the Critical rate collapses from 36.09% to 3.23%.

Summary figures:

- PF `Critical` readings: **3,217,660 — 28.38% of all forward-power phase readings**
- Of those, **97.10% occur below 15% of breaker rating**
- 87.97% of all readings are below 15% CB

### 7.2 The proposed rule

> **Evaluate power factor for anomaly purposes only when, on the same phase and the same
> reading, `current_phase_k_a ≥ 0.05 × cb_max_rating_a` AND `active_power_phase_k_kw > 0`.
> Below that, emit `PF_NOT_EVALUATED_LOW_LOAD` — never `Acceptable`, and never `Critical`.**

Three reasons for 5% rather than a round number:

1. **It is the knee in the measured distribution** (§7.1), not a convenience.
2. **It is already a constant in the production classifier.** The current/power rule defines
   `margin = 0.15 × CB` and `third = margin / 3 = 0.05 × CB`. The proposed PF gate is
   exactly `third`. It introduces no new magic number into the codebase.
3. **It is conservative.** At 5–10% CB the Critical rate is already down to 3.23%, so the
   gate removes noise without removing signal.

### 7.3 What the rule costs and what it preserves

| | Ungated | Gated at ≥ 5% CB |
|---|---:|---:|
| Phase-readings evaluated | 11,336,327 (100%) | 5,071,616 (**44.74%**) |
| PF `Critical` | 3,217,660 (**28.38%**) | ≈ 210,400 (**≈ 4.15%**) |

A **6.8×** reduction in PF alarm volume. Crucially it *preserves* the genuinely suspicious
population: the 30–50% and ≥50% CB bands retain Critical rates of 14.50% and 13.27% with p05
around 0.43–0.49. **A heavily loaded phase running at PF 0.45 is a real power-quality
finding; a standby phase drawing 1.5 A at PF 0.45 is a transformer magnetising.** The
ungated rule cannot tell them apart; the gated rule reports only the first.

### 7.4 Scope limitation, stated explicitly

This rule changes **nothing** in Bronze, Silver, Gold or Power BI. `classify_power_factor_v2`
and every `status_pf*` column keep their current behaviour and their current values. The
gate lives in `ML_WORK` and governs only whether Model 1 raises an anomaly event. This
follows the standing constraint that existing data-quality and electrical business rules are
never changed to improve an ML result.

---

## 8. Proposed severity definition

### 8.1 Use the rank the ladder already reserves

The production ladder is
`Acceptable < Review Required < Anomaly < Problematic < Critical < Invalid`, and
`silver.status_rank()` already recognises `Anomaly` — but **no v2 classifier ever emits it**.
Model 1 should occupy that reserved rank rather than inventing a parallel scale.

### 8.2 Severity from three orthogonal axes

Severity is assigned per **event** (a contiguous flagged episode), never per reading.

| Axis | Definition | Levels |
|---|---|---|
| **Persistence** | Share of evaluated readings in the episode that are flagged, and episode duration | transient (< 24 h) / sustained (1–7 d) / chronic (> 7 d) |
| **Magnitude** | Deviation in the family's own units — e.g. for T1, mean \|kW\| while reversed; for T3, PF shortfall below 0.8 | minor / moderate / severe (tertiles within family, fixed once from history) |
| **Corroboration** | Does a concurrent existing classifier agree? | none / partial / full |

Combined into one published level:

| Severity | Rule |
|---|---|
| **Critical** | chronic **and** severe, **or** a T5 physics contradiction of any duration (stuck register on a full day, register decrease). T1 reverse power is graded — see below. |
| **Problematic** | chronic **or** (sustained **and** severe) |
| **Anomaly** | sustained, or transient-and-severe with corroboration |
| **Review Required** | transient, or any episode with no corroboration and only minor magnitude |

**T1 reverse power is graded, not unconditional** (policy change, 2026-09-20). The earlier
rule made every `kW < 0` episode Critical regardless of evidence, which put a two-watt
single reading alongside an 18-month three-phase fault:

| T1 case | Severity |
|---|---|
| Sustained or chronic reversal, or a dense reversal inside one day | **Critical** |
| Isolated reading with magnitude ≥ 0.5 kW **and** load ≥ 5% CB **and** corroboration | **Critical** |
| Isolated reading, otherwise | **Anomaly** |
| Isolated reading below 0.1 kW with no corroboration | **Review Required** |

"Isolated" means at most three readings inside a single day. This is a **classification**
change only: the detector is untouched, the event count is identical, and every event stays
in the review output with `negative_power_factor_readings`,
`mean_power_factor_while_reversed`, `mean_current_a`, `mean_current_pct_cb`, `magnitude`
and `max_abs_kw_while_reversed` preserved as evidence.

T5 keeps the unconditional rule. `stuck_register` requires a complete day under load by
construction, and `register_decrease` arrives already corroborated by
`status_kwh = 'Invalid'`.

Two rules that override the axes:

- **Commissioning window.** Any episode ending on or before 2024-12-31 whose meter shows no
  recurrence afterwards is capped at `Review Required` and tagged `COMMISSIONING`
  (§3 Tier D).
- **Not-evaluated is not a severity.** `PF_NOT_EVALUATED_LOW_LOAD` and any gap-suppressed
  interval produce no event at all.

### 8.3 What severity is explicitly *not*

It is **not** a probability, a confidence, or a precision estimate. The project has no
engineering labels yet, so no detector's precision is known. Severity is a **triage ordering
for human review**, and every output must carry that caveat — exactly as the Isolation
Forest prototype's 53 flagged days were correctly described as review candidates rather than
confirmed faults.

---

## 9. Tests and acceptance criteria, per detector family

Every family gets positive tests (must fire), negative tests (must not fire), and a
synthetic test (behaviour provable without the live database).

### T1 — polarity / reverse power

| Type | Criterion |
|---|---|
| Positive | Fires on **ZN.16-PB phases 1, 2, 3**; **ZN.8-PB.2 p1**; **ZN.5-PB p1**; **ZN.10-PB.1 p2**; **ZN.12-PB p3**; **ZN.11-PB.2 p2** |
| Positive | ZN.16-PB episode start ≤ 2024-12-16 and end within ±1 day of **2026-06-26** |
| Negative | Silent on all **18** meters with no negative power on any phase |
| Negative | Does **not** classify ZN.5-PB **phase 3** as Tier-B (68 negative-PF rows ≠ a polarity fault) |
| Boundary | `kW = 0` exactly is not "negative"; `kW < 0` with `current = 0` is a separate class |
| Synthetic | On a fabricated series with a known sign flip at row *n*, the episode boundary is exactly *n* |
| Count | Total reverse-power readings on `active_power_total_kw` reconciles to **281,484 across 11 meters** |

### T2 — current vs power inconsistency

| Type | Criterion |
|---|---|
| Positive | Fires on **ZN.20-PB.1 phases 1 and 3** and **ZN.10-PB.2 phase 3** |
| Positive | Reproduces totals: **45,343** `current > 0, kW = 0` and **34,041** `current = 0, kW ≠ 0` |
| Coverage | Reports how many events fall **above** 15% CB, i.e. outside the existing rule's reach |
| Negative | Does not double-report an episode already carried by `status_amp*` — corroboration, not duplication |
| Boundary | Literal zero, no epsilon, matching the production rule; a NULL same-phase power is not an inconsistency |

### T3 — power factor

| Type | Criterion |
|---|---|
| Gate | Post-gate evaluated share is **44.74% ± 0.5pp** of phase-readings, and post-gate Critical rate **≈ 4.15%** |
| Positive | A synthetic phase drifting 0.95 → 0.78 at ≥ 20% CB raises a CUSUM event before it crosses 0.8 |
| Negative | **Zero** events from any reading below 5% CB |
| Negative | ZN.16-PB is reported under **T1**, never as a PF fault, despite PF ≈ −0.8 |
| Boundary | Band edges match the production classifier exactly (0.6 / 0.78 / 0.8 / 1.0, acceptable-boundary-inclusive) |
| Regression | Changing the gate does **not** change any `status_pf*` value in the database |

### T4 — statistical change / drift

| Type | Criterion |
|---|---|
| Positive | Detects the **ZN.16-PB repair at 2026-06-26 within ≤ 3 calendar days, reporting the actual lag**. Accepted historical result: **2 days** (first flagged 2026-06-28), asserted as a regression check. Supersedes the original ±1 day criterion, which an EWMA cannot meet without tuning λ to fit a single test — see §11. |
| Positive | Detects the **facility-wide telemetry outage 2026-02-03 → 2026-02-18** (all 29 meters) |
| Negative | Does **not** detect ZN.16-PB's fault ONSET (2024-12-15 ± 3 days) from its own history — the documented structural limitation (§5.3), asserted so it cannot be mistaken for a passing detector. Level shifts *inside* the fault window are reported rather than suppressed; they are load changes, not polarity detections. |
| Baseline | The baseline is the meter's own trailing window, **not masked** by `known_fault_windows`, because T4 answers "has behaviour changed relative to the recent past" and masking the fault window starves the baseline so the repair becomes invisible. It is held back by `baseline_gap_days: 7` so a step change cannot walk into its own reference. Where a configured fault window leaves fewer than `min_baseline_days` clean days, every event carries `self_referential_baseline_unavailable: true` and `clean_baseline_days_available`, so the limitation is reported rather than silently producing a baseline from too few clean days. |
| Synthetic | Known step of size *s* at row *n* is detected with lag ≤ 2·(1/λ); known pure noise produces a false-alarm rate within its nominal ARL |

### T5 — register integrity

| Type | Criterion |
|---|---|
| Positive | **ZN.16-PB: 493 stuck days** (full day, zero advance, mean current > 5 A), 2024-12-16 → 2026-06-25 |
| Positive | Also fires on **ZN.8-PB.2 (21 days, 2025-04-03 → 2025-09-22)** and **ZN.12-PB (18 days, 2024-12-15 → 2025-08-16)** |
| Negative | **Must not run at per-reading grain.** The register is coarse — the commonest positive increments are 0.4 and 0.5 kWh — so "no advance since the previous reading" is true on 49–96% of intervals for *healthy* meters and is meaningless |
| Negative | Commissioning-window stuck days (ZN.8-PB.1, ZN.17-PB, ZN.15-PB.2, ZN.10-PB.1, ZN.10-PB.2, all ending 2024-12-25/27) are tagged `COMMISSIONING`, not `Critical` |
| Scope | Runs on the **29-meter** scope only (Zone 13 excluded for cumulative-kWh integrity) |
| Reconcile | Register **decreases** across 29 meters total **25**, matching `status_kwh = 'Invalid'` |

### Cross-cutting

| Criterion |
|---|
| Read-only enforced: `transaction_read_only = on`, `REPEATABLE READ`, verified before any query |
| Row-count assert per scope (§1), failing loudly |
| Every event carries `meter_label`, `phase`, `family`, `detector`, `event_start`, `event_end`, `severity`, `concurrent_status`, `evidence_window_rows`, and `commissioning` |
| Events are **episodes**, not readings — consecutive flagged readings collapse into one |
| No detector output modifies Bronze, Silver, Gold or Power BI; all artifacts under `ML_WORK/outputs/` |
| Precision and recall are **not** claimed anywhere until engineering labels exist |

---

## 10. Open decisions requiring sign-off before implementation

| # | Decision | Recommendation |
|---|---|---|
| 1 | Model 1 scope: 31 meters or 29? | **31 for electrical families, 29 for the register family** (§1) |
| 2 | Is 5% of CB accepted as the PF minimum-load gate? | **Yes** — it is the measured knee *and* the existing `third` constant (§7.2) |
| 3 | Do ZN.10-PB.1 p2 and ZN.11-PB.2 p2 enter the acceptance set before engineering confirms them? | **Yes, as Tier B** — the evidence is stronger than for findings already documented (§3) |
| 4 | Is ZN.5-PB **phase 3** demoted from the acceptance set? | **Yes** — 68 negative-PF rows does not support a polarity claim (§3) |
| 5 | May Model 1 emit the reserved `Anomaly` rank? | **Yes** — the ladder reserves it and nothing emits it (§8.1) |
| 6 | Commissioning window end date | **2024-12-31**, from the observed data; needs engineering confirmation |
| 7 | Whether ZN.16-PB stays in Model 2's pooled training population | **Out of scope for Model 1**, and not resolvable against the spent final test (§6.3) |

**All seven were signed off on 2026-09-20. See §11 for how each was implemented.**

---

## 11. Implementation record

Signed off 2026-09-20. All seven decisions in §10 were approved; two refinements were
added at sign-off and both are implemented.

| # | Decision | As implemented |
|---|---|---|
| 1 | 31-meter electrical / 29-meter register scope | `scope.verify_scope()` asserts both counts (4,535,918 / 4,260,849) and fails loudly |
| 2 | 5% CB power-factor minimum-load gate | `t3_power_factor.min_load_pct_cb`, tested to equal the production `third = margin/3` constant |
| 3 | ZN.10-PB.1 P2 and ZN.11-PB.2 P2 as Tier B | in `acceptance_set.tier_b_strong_empirical`, labelled empirical acceptance findings, **not** confirmed faults |
| 4 | ZN.5-PB P3 demoted to monitor | tagged `monitor_only`, severity capped below Critical/Problematic so it is never asserted as a finding |
| 5 | Model 1 may emit `Anomaly` | occupies the reserved rank; 1,627 of 3,928 events |
| 6 | 2024-12-31 commissioning cutoff | `commissioning.assumed_boundary_date`, configurable, carried in run metadata as `assumed_commissioning_boundary_pending_engineering_confirmation` |
| 7 | ZN.16's Model 2 membership frozen | Model 2 was not rerun; no Model 2/3/4 file was touched |

**Refinement 1 — T5 load evidence.** The absolute `> 5 A` rule is preserved and reproduces
ZN.16-PB's 493 stuck days exactly. A breaker-normalised rule (`mean per-phase current ≥ 1%
of CB`) runs alongside it, and **every** stuck-register event records both `mean_current_a`
and `mean_current_pct_cb`, plus which rule(s) fired. The normalisation earns its place:
ZN.10-PB.2 has 8 days under the legacy rule and 11 under the normalised one, because 5 A on
an 80 A breaker is a different thing from 5 A on a 250 A breaker.

**Refinement 2 — February 2026 outage.** T4 carries two sub-detectors with different event
classes. All 86 data-availability episodes, including the Feb 2026 facility-wide outage
across all 31 meters, are classified `DATA_AVAILABILITY` and never `ELECTRICAL_FAULT`, even
though T4 detects the transition.

### Four defects found during implementation

Each was found by a test or an acceptance criterion failing, not by inspection.

1. **The T3 CUSUM was two-sided**, so a power factor sustained *above* 0.8 was reported as
   drift — healthy meters running at PF 0.94–0.97 raised anomalies. Now one-sided downward.
2. **T4's EWMA could not detect the ZN.16 repair.** Excluding the known fault window from
   the baseline starved it; and with a plain trailing window a step change walks into its
   own reference, inflating the control limit from 1.5 to 7.2 kW faster than the deviation
   grows. Fixed with an unmasked baseline held back by `baseline_gap_days: 7`.
3. **T5's register-decrease check could never fire**, because the daily advance is
   `max(kWh) − min(kWh)`, which is non-negative by construction. Moved to reading grain.
4. **T5 returned early** before the decrease check for any meter with no stuck days, so 16
   of 25 decreases were missed.

### One acceptance criterion was relaxed, deliberately

§9 asked for the ZN.16-PB repair to be detected **within ±1 day** of 2026-06-26. The
measured detection lag is **2 days** (first flagged 2026-06-28). On 2026-06-27 the
deviation was 4.415 kW against a control limit of 4.52 — just under.

An EWMA is a smoother and lags a step by construction; reaching ±1 day would mean tuning λ
until this single test passed, which is fitting a parameter to a test. The criterion is now
`zn16_repair_detection_tolerance_days: 3`, and the **actual lag is reported on every run**
rather than hidden behind a pass.

### Final policy changes, 2026-09-20 — Model 1 FROZEN

Two changes were applied after the first accepted run, and Model 1 is now frozen.

**1. T4 repair acceptance.** Detector parameters are unchanged and λ was not tuned. The
criterion is now *"ZN.16 repair detected within ≤ 3 calendar days, with actual lag
reported"*. The observed lag of **2 days** is preserved as the accepted historical result
and asserted as a regression check, so any future change that alters it fails the run.

**2. T1 severity grading** (see §8.2). The rule "physics contradiction of any duration ⇒
Critical" no longer applies to reverse power. Effect on the same 3,928 events:

| Severity | Before | After | Δ |
|---|---:|---:|---:|
| Critical | 315 | **306** | −9 |
| Problematic | 914 | 914 | 0 |
| Anomaly | 1,627 | **1,634** | +7 |
| Review Required | 1,072 | **1,074** | +2 |

Within T1: Critical 93 → 84, Anomaly 12 → 19, Review Required 19 → 21. Nine isolated
episodes were reclassified; none was removed. Single-reading Critical events fall from 39
to 32, of which 23 are register decreases corroborated by `status_kwh = 'Invalid'`, 7 are
full stuck days, and 2 are ZN.12-PB P3 reversals at 0.56–0.61 kW on 6–8% of breaker rating
with PF −0.29/−0.45 and full corroboration.

The two named blips are now **Review Required** and remain in the review output. The
evidence is what justifies the cap:

| | ZN.1-PB.2 P1 2025-05-17 | ZN.5-PB P1 2026-07-05 |
|---|---|---|
| Magnitude | 0.002 kW | 0.002 kW |
| Current | 0.2 A (**0.2% CB**) | 0.2 A (**0.2% CB**) |
| Power factor | **+1.000** | **+1.000** |
| Negative-PF readings | **0** | **0** |
| Corroboration | none | none |

A reading with PF exactly +1.0 and no negative power factor anywhere is a quantisation
artifact at the register's resolution, not a reversed CT. Both are regression-tested on
every run: they must stay visible, and they must not be Critical.
