# SADINhub: Data Assessment Report
**Energy Intelligence & Predictive Analytics Platform**

**Source database:** `sadinhub` (PostgreSQL 18)
**Assessment scope:** 31 canonical energy meters, ~19 months (December 2024 – July 2026)
**Analysis grain:** raw reading level (~5-minute native interval), via `silver.fact_energy_readings_snapshot` / `gold.energy_raw`; 4,535,918 reading packets
**Method:** per-metric, per-phase pinpoint analysis. Every finding below identifies the specific measurement, phase, and meter responsible rather than using a single worst-case rollup per reading.

## 1. Executive Summary

This report assesses electrical energy telemetry quality across all 31 canonical meters, checking every classified measurement individually, phase by phase, across the full 4,535,918-reading history.

**Key findings:**

**Current/power mismatch (Amp1/2/3):** Current analysis identified the largest finding in this report, a dominant and previously undocumented current/power measurement inconsistency on `ZN.20-PB.1`. This meter alone accounts for 89.8% of all "power with no matching current" (`Major Issue`) readings and 80.8% of all "current flowing with no matching power" (`Major Problem`) readings across the entire 31-meter fleet. The issue is concentrated on Phase 1 and Phase 3, while Phase 2 is almost entirely spared. See §4.

**Current mismatch scope:** 16 meters exceed the 100-reading current/power inconsistency threshold. Some are confined to a single phase (`ZN.10-PB.1`, `ZN.8-PB.1`, `ZN.7-PB`, `ZN.9-PB`), while others are spread across multiple phases (`ZN.10-PB.2`, `ZN.17-PB`, `ZN.2-PB`). None were previously documented. A further 9 meters register at least one such reading below that threshold, and 6 register none at all; the full 25-meter breakdown and threshold rationale are in §4.7. See §4.

**Power factor:** Under the currently configured thresholds, only 44–45% of power-factor classifications are `Acceptable` on any given phase (PF1 45.4%, PF2 44.0%, PF3 44.5%), with `Critical` rates of 32–38% per phase. This describes classification outcomes, not confirmed electrical operation. The classifier applies PF thresholds at all load levels, and low-load periods physically produce low power factor. Whether PF should be gated below a minimum current, and whether dashboard PF should be load-weighted, are open items (§10). Several meters also show pronounced **phase-asymmetric** PF behaviour, where one phase behaves very differently from the other two on the same meter. Examples include `ZN.10-PB.1` (2.9% Critical on Phase 3 vs. 99.2% on Phase 2), `ZN.11-PB.1` (3.1% on Phase 1 vs. 96.4% on Phase 3), and `ZN.11-PB.2` (0.0% on Phase 3 vs. 92.3% on Phase 2). A full 31-meter breakdown is in §5.1.

**Previously known meters:** `ZN.16-PB`, `ZN.5-PB`, and `ZN.8-PB.2` are characterised more precisely than before. Power factor and active power agree, with reactive power providing supporting context only (§5.4): `ZN.16-PB` shows the abnormality uniformly across all three phases; `ZN.8-PB.2` remains Phase-1-specific; `ZN.5-PB` remains Phase-1-dominant but with additional Phase-3 abnormalities in both power factor (49.0% `Critical`) and current (§4.6). This resolves an open question from the prior assessment. Only `ZN.16-PB` is engineering-confirmed as a wiring/polarity fault; the other two remain candidates corroborated by power factor and active power, not independently confirmed. See §5, §7.

**New anomaly candidate:** `ZN.12-PB` is a strong newly identified Phase-3 anomaly candidate, independently supported by both active-power and power-factor behaviour: 24,136 negative active-power readings and a 95.2% Phase-3 power-factor `Critical` rate, agreeing on the same phase. It has not yet been raised with engineering. See §5.3.

**Voltage and frequency:** The assessed record is effectively clean. Of 31,751,426 voltage/frequency classifications (7 channels × 4,535,918 readings), only 13 are non-Acceptable, approximately 0.000041%: 12 `Critical`, concentrated on `ZN.13-PB.1`, and 1 `Review Required` on `ZN.16-PB`. See §8.

**Accumulated energy:** Overall integrity is strong, with one concentrated exception. There are 63 counter-decrement events out of 4.5 million readings (0.0014%); `ZN.13-PB.1` and `ZN.13-PB.2` together account for 60.3% of them (19 each), while the remaining 29 meters show at most one apiece. See §6.

**Zone 17 coverage:** The confirmed ~201-day telemetry gap remains the most significant coverage issue in the fleet, unchanged from the prior assessment. See §3.

## 2. Methodology

### 2.1 Analysis grain and philosophy

All findings in this report are computed at the raw reading grain (~5-minute native interval), using real reported timestamps, with no bucketing, averaging, or aggregation tables. Every count below can be traced back to specific meters, specific phases, and specific moments in time.

**This report deliberately does not use `overall_status`** (the single worst-case rollup per reading) as an analytical tool. `overall_status` answers "does this reading have a problem," but not "which measurement caused it." This is a real limitation when a reading fails on one metric while every other metric on that same reading is fine. Every finding here instead uses each metric's own individual `status_*` column, so a problem is always attributed to the specific measurement and phase responsible for it. `overall_status` remains available in the data for anyone who wants a quick, non-diagnostic summary view; it is simply not the basis for any finding in this report.

### 2.2 Classification system in use

Five severity tiers, evaluated in strict order (first match wins): `Invalid` → `Critical` → `Review Required` → `Problematic` → `Acceptable`. Full function-level detail is documented in the Data Dictionary; the summary relevant to this report:

- **Voltage, frequency, power factor**: facility-wide fixed thresholds (SACO/SECO standards)
- **Current**: the one measurement with per-meter thresholds, since each panel's circuit breaker rating differs (80A–250A across the fleet). Current also has two additional outcomes that exist **only for this measurement** and are **not** part of the five-tier severity ladder and **do not** feed into `overall_status`:
  - **`Major Problem`**: current is flowing on a phase, but that same phase's active power reads exactly zero
  - **`Major Issue`**: a phase's active power is non-zero, but that same phase's current reads exactly zero. This is electrically inconsistent under normal measurement assumptions and therefore indicative of a measurement, configuration, or instrumentation issue rather than a real operating condition. (Device rounding, measurement resolution, and inter-channel synchronisation could in principle contribute; this has not been ruled out.)
  - A phase where current and power are both zero, or both non-zero, is `Acceptable`. This measurement no longer judges the low-current zone by magnitude, only by whether current and power are mutually consistent in being present or absent
- **Accumulated energy**: only `kWh` is classified; a reading is `Invalid` if the cumulative counter decreased versus that meter's previous reading (counters must only increase)
- **Not classified at all:** Active Power, Apparent Power, Reactive Power, `kVAh`, `kVArh`, and the phase-average convenience columns (`Va`, `Vna`, `Ampa`). The phase-average columns are never populated by any of the 31 meters (§3.2). Raw values for all of these remain fully available; findings in this report involving active power and reactive power are based on their real measured values directly, not a status column.

### 2.3 Terminology

- **"Reading packet"**: one canonical meter × one timestamp, pivoted from Bronze's long-format telemetry.
- **"Telemetry gap"** rather than "outage," unless a physical cause is specifically confirmed.
- **"Wiring/polarity fault"** rather than "hardware fault," reserved for the active-power sign findings in §5.

## 3. Data Volume, Structure & Coverage

### 3.1 Volume

| Metric | Value |
|---|---|
| Raw Bronze telemetry rows | ~109 million |
| Canonical reading packets analyzed | 4,535,918 |
| Canonical energy meters | 31 (32 source records; 1 confirmed Zone 20 duplicate excluded) |
| Native reading interval (typical) | ~301.5s (~286–287 readings/day) |
| Native reading interval (Zone 13) | ~321.17–321.19s (~269 readings/day) — distinct and stable; not yet formally confirmed by engineering as intended |

Volume was validated by five independent methods, all agreeing exactly on 4,535,918: direct counts of the analytical table and both live source views, the sum of per-meter counts. The most rigorous check was the sum of Bronze's own distinct `(device_id, timestamp)` packet counts across all 31 meters, which matched with zero variance on every meter individually.

### 3.2 Confirmed unpopulated measurements (facility-wide)

`Va`, `Vna`, `Ampa`, and the entire apparent-power/apparent-energy family (`kVA1-3`, `TkVA`, `kVAh`) were **not observed for any meter in the validated window.** A distinct-key count per device, run directly against `bronze.telemetries`, returned exactly 24 of the possible 32 keys, uniformly, for every meter reporting in the sampled window. This is consistent with fleet-wide device or configuration behaviour rather than a coverage gap in specific meters.

**Limitation:** the check was run on a sampled window, not the full 19-month history, so it establishes consistent absence within that window rather than proving these keys were never transmitted at any point. Extending the check across the full history would settle this definitively (§10). All downstream columns are `NULL` throughout the analytical layer, so the practical effect on this assessment is unchanged either way.

### 3.3 Coverage

| Meter | Coverage | First Reading (UTC) | Last Reading (UTC) |
|---|---|---|---|
| ZN.17-PB | 57.3% | 2024-12-11 | 2026-07-11 |
| ZN.21-PB | 60.7% | 2024-12-28 | 2026-07-11 |
| ZN.9-PB | 62.2% | 2024-12-10 | 2026-07-11 |
| ZN.20-PB.2 | 63.3% | 2024-12-29 | 2026-07-11 |
| ZN.19-PB.1 | 73.2% | 2024-12-29 | 2026-07-11 |

All five have readings near both the start and end of the period; low coverage reflects internal gaps, not late installation.

**`ZN.17-PB` confirmed telemetry gap:** one major gap, 2025-05-18 04:22:28.966 UTC to 2025-12-05 12:55:30.761 UTC (201.36 days), confirmed by the project team as a known Zone 17 issue (zone-level confirmation; physical mechanism not independently verified). A secondary cluster of ~15 smaller gaps (0.7–14.8 days each) in February–March 2025 suggests a separate, likely intermittent issue, not confirmed.

**Analytical consequence:** because consumption derives from differences between consecutive cumulative-counter readings, this meter's entire counter increase across the 201.36-day gap lands on the first reading after resumption. Under the approved business rule, that cumulative increase is intentionally retained as valid consumption and flagged as a long-gap interval. Total consumption is therefore preserved, but time-bucketed reporting around 2025-12-05 concentrates consumption accumulated during the missing-data period at the resumption timestamp.

The remaining four low-coverage meters have not been individually root-caused (§10).

## 4. Current: Pinpoint Findings

The corrected current/power agreement check (§2.2) produced the largest set of new findings in this assessment. All counts below come directly from the live data and were checked phase by phase across the facility.

### 4.1 Facility-wide distribution, per phase

| Status | Phase 1 | Phase 2 | Phase 3 |
|---|---|---|---|
| Acceptable | 4,501,225 | 4,518,394 | 4,508,492 |
| Major Issue | 30,923 | 128 | 3,018 |
| Major Problem | 3,556 | 17,396 | 24,408 |
| Review Required | 179 | 0 | 0 |
| Problematic | 26 | 0 | 0 |
| Critical | 9 | 0 | 0 |

Each phase's total sums to 4,535,918. `Review Required`/`Problematic`/`Critical` (the upper-margin, near-breaker-limit tier) only occur on Phase 1, and only on one meter (§4.5). Every other severity finding in this section is a `Major Issue`/`Major Problem` sensor-agreement finding.

### 4.2 `ZN.20-PB.1`: the dominant finding

| Phase | Major Issue | Major Problem |
|---|---|---|
| 1 | **27,762** (89.8% of fleet total) | **2,875** (80.8% of fleet total) |
| 2 | 0 | 120 |
| 3 | **2,743** (90.9% of fleet total) | 0 |

`ZN.20-PB.1` alone accounts for the large majority of every current/power mismatch reading across the entire 31-meter facility, concentrated on Phase 1 and Phase 3, while Phase 2 is almost entirely clean. Against this meter's documented reading count, the Phase 1 finding alone represents roughly 19% of its total readings, so this is not an occasional blip. This meter has no prior documentation in any existing report. It represents a persistent Phase-1 and Phase-3 current/power measurement inconsistency requiring electrical and metering investigation. The data establishes the pattern clearly but does not by itself distinguish between a current sensor, CT wiring, device configuration, channel synchronisation, measurement resolution, or another instrumentation cause.

### 4.3 `ZN.10-PB.2`: multi-phase, Phase 3 dominant

| Phase | Major Issue | Major Problem |
|---|---|---|
| 1 | 1,360 | 10 |
| 2 | 4 | 2,012 |
| 3 | 0 | **21,970** (90.0% of fleet's Phase 3 Major Problem total) |

Unlike `ZN.20-PB.1`, this meter shows activity on all three phases, with Phase 3 dominant. This pattern differs from `ZN.20-PB.1` and should be investigated separately rather than assumed to share a cause.

### 4.4 Clean, single-phase findings: the most diagnostically useful signatures

| Meter | Affected phase | Count | Other phases |
|---|---|---|---|
| `ZN.10-PB.1` | Phase 2 | 8,822 Major Problem | Essentially zero |
| `ZN.8-PB.1` | Phase 2 | 2,552 Major Problem | Essentially zero |
| `ZN.7-PB` | Phase 1 | 1,341 Major Issue + 644 Major Problem | Essentially zero |
| `ZN.9-PB` | Phase 3 | 655 Major Problem | Essentially zero |

These four show narrow single-phase, single-metric signatures. They provide the cleanest evidence in the current analysis and are likely the easiest to investigate in the field because there is no cross-phase ambiguity to resolve first.

### 4.5 `ZN.1-PB.2`: the sole upper-margin (breaker-proximity) finding

`ZN.1-PB.2` is the only meter in the entire facility that ever registers `Review Required` (179), `Problematic` (26), or `Critical` (9) on current. It has 214 upper-margin classifications in total, all on Phase 1, making it the only meter that runs close to or over its own breaker rating.

**This meter carries two independent findings.** Separately from the breaker-proximity behaviour above, it also registers **223 current/power mismatch readings on Phase 3** (§4.7), placing it above the mismatch threshold as well. The two findings are on different phases and are different in kind: one is a loading condition and the other is a measurement-consistency condition. They should be investigated as separate items rather than assumed related.

### 4.6 Meters with moderate multi-phase or secondary signals

| Meter | Pattern |
|---|---|
| `ZN.2-PB` | Phase 2 dominant (3,122), smaller Phase 3 signal (420), Phase 1 clean |
| `ZN.17-PB` | Spread across all three phases (P1 8, P2 575, P3 453) — the most evenly distributed signal in the fleet |
| `ZN.3-PB.2` | Phase 3 dominant (357), Phases 1/2 negligible (14, 3) |
| `ZN.12-PB` | Phase 3 dominant (260), Phases 1/2 negligible (1, 1) — same phase as its power-factor and active-power findings (§5.3) |
| `ZN.19-PB.2` | Phase 1 only (232), Phases 2/3 essentially clean |
| `ZN.11-PB.2` | Spread across all three phases (P1 167, P2 116, P3 78) |
| `ZN.21-PB` | Phase 2 only (166), Phases 1/3 zero |
| `ZN.5-PB` | Phase 3 (127), small Phase 1 (10) — the Phase 3 signal is previously undocumented and is on a different phase from this meter's known Phase-1 findings (§5) |
| `ZN.14-PB` | Phase 3 only (112), Phases 1/2 negligible |

### 4.7 Summary

**Threshold used:** a meter is individually reported in this section if it exceeds **100 affected readings** (`Major Issue` + `Major Problem` combined, on any single phase). Counts fall away sharply below this line; the meters below it register at most 27 readings on any phase.

25 of the 31 meters register at least one `Major Issue` or `Major Problem` reading. 16 exceed the 100-reading threshold. 6 register none at all.

**Above threshold (16 meters):**

| Meter | Phase 1 | Phase 2 | Phase 3 | Max (phase) |
|---|---|---|---|---|
| `ZN.20-PB.1` | 30,637 | 120 | 2,743 | 30,637 (P1) |
| `ZN.10-PB.2` | 1,370 | 2,016 | 21,970 | 21,970 (P3) |
| `ZN.10-PB.1` | 1 | 8,822 | 0 | 8,822 (P2) |
| `ZN.2-PB` | 0 | 3,122 | 420 | 3,122 (P2) |
| `ZN.8-PB.1` | 0 | 2,552 | 0 | 2,552 (P2) |
| `ZN.7-PB` | 1,985 | 0 | 1 | 1,985 (P1) |
| `ZN.9-PB` | 2 | 0 | 656 | 656 (P3) |
| `ZN.17-PB` | 8 | 575 | 453 | 575 (P2) |
| `ZN.3-PB.2` | 14 | 3 | 357 | 357 (P3) |
| `ZN.12-PB` | 1 | 1 | 260 | 260 (P3) |
| `ZN.19-PB.2` | 232 | 0 | 2 | 232 (P1) |
| `ZN.1-PB.2` | 0 | 6 | 223 | 223 (P3) |
| `ZN.11-PB.2` | 167 | 116 | 78 | 167 (P1) |
| `ZN.21-PB` | 0 | 166 | 0 | 166 (P2) |
| `ZN.5-PB` | 10 | 3 | 127 | 127 (P3) |
| `ZN.14-PB` | 1 | 1 | 112 | 112 (P3) |

**Below threshold but non-zero (9 meters)**: reported for completeness; these counts are low enough to be consistent with isolated occurrences rather than a persistent pattern: `ZN.13-PB.2` (27), `ZN.4-PB.2` (12), `ZN.15-PB.2` (7), `ZN.16-PB` (3), `ZN.13-PB.1` (2), `ZN.18-PB` (1), `ZN.15-PB.1` (1), `ZN.1-PB.1` (1), `ZN.11-PB.1` (1).

**Zero occurrences (6 meters):** `ZN.3-PB.1`, `ZN.4-PB.1`, `ZN.6-PB`, `ZN.8-PB.2`, `ZN.19-PB.1`, `ZN.20-PB.2`.

Every phase column above reconciles to the facility totals in §4.1.

This is a substantial expansion beyond the three meters previously documented for any electrical measurement issue in this facility. The findings split into distinct signatures (dominant multi-phase, narrow single-phase, moderate spread), which is more consistent with several independent causes than with one shared facility-wide condition. No cause is established for any of them by this data alone.

**Note on `ZN.8-PB.2`:** this meter, one of the three previously documented for negative active power, registers only 3 current/power mismatch readings in total. Its documented condition does not manifest in this measurement, which is a useful negative result: the current/power agreement check and the negative-active-power finding detect genuinely different things.

## 5. Power Factor and Active Power: Confirmed and Expanded

### 5.1 Power factor: facility-wide distribution and full per-meter breakdown

A `Critical` power factor status means the reading falls outside the configured acceptable range (below 0.6, or above 1.0). It does not by itself establish a wiring or equipment failure. Everything in this section describes **observed PF behaviour**, not diagnosed causes.

**Facility-wide classification outcomes (see the interpretation caveat below):**

| Phase | Acceptable | Review Required | Problematic | Critical |
|---|---|---|---|---|
| PF1 | 2,060,040 (45.4%) | 86,640 (1.9%) | 889,456 (19.6%) | 1,499,782 (33.1%) |
| PF2 | 1,997,566 (44.0%) | 62,231 (1.4%) | 771,865 (17.0%) | 1,704,256 (37.6%) |
| PF3 | 2,017,078 (44.5%) | 133,067 (2.9%) | 912,100 (20.1%) | 1,473,673 (32.5%) |

Each phase's row sums to 4,535,918. **Under the currently configured thresholds, fewer than half of all power-factor readings classify as `Acceptable` on any phase**, and roughly a third classify as `Critical`.

**Interpretation caveat: this does not by itself establish poor electrical operation.** Power factor is physically low at low load: a lightly-loaded or idling circuit will produce low PF regardless of whether anything is wrong with it. The classifier currently applies PF thresholds at every load level, with no minimum-current gate, so a substantial share of these `Critical` classifications may reflect genuine low-load operating periods rather than a power-quality problem. Two open questions follow directly (§10): whether PF classification should be suppressed below a minimum current or load threshold, and whether any dashboard PF figure should be load-weighted rather than a simple average. Until those are resolved, the figures above should be read as *classifier output*, and any per-meter rate below should be compared against this facility-wide baseline rather than treated as individually alarming.

**Full per-meter breakdown, all 31 meters, sorted by phase spread** (the difference between that meter's highest and lowest phase `Critical` rate). Spread is used as the sort key because it isolates **phase-asymmetric** behaviour, where one phase diverges sharply from the other two on the same meter. This is a different and more diagnostically specific pattern than uniformly elevated PF across all three phases. Neither pattern establishes a cause.

| Meter | PF1 Critical % | PF2 Critical % | PF3 Critical % | Spread (max−min) |
|---|---|---|---|---|
| `ZN.10-PB.1` | 62.5% | 99.2% | 2.9% | 96.3 pts |
| `ZN.11-PB.1` | 3.1% | 82.7% | 96.4% | 93.3 pts |
| `ZN.8-PB.2` | 96.7% | 4.4% | 5.7% | 92.4 pts |
| `ZN.11-PB.2` | 19.2% | 92.3% | 0.0% | 92.3 pts |
| `ZN.12-PB` | 14.4% | 65.8% | 95.2% | 80.8 pts |
| `ZN.3-PB.1` | 0.0% | 12.3% | 76.2% | 76.2 pts |
| `ZN.1-PB.1` | 75.2% | 43.4% | 0.6% | 74.6 pts |
| `ZN.5-PB` | 92.8% | 18.3% | 49.0% | 74.5 pts |
| `ZN.21-PB` | 0.0% | 68.2% | 0.0% | 68.2 pts |
| `ZN.13-PB.1` | 52.5% | 29.1% | 85.2% | 56.1 pts |
| `ZN.20-PB.2` | 0.0% | 42.1% | 0.1% | 42.1 pts |
| `ZN.15-PB.1` | 46.3% | 29.3% | 5.5% | 40.8 pts |
| `ZN.20-PB.1` | 36.6% | 40.0% | 2.0% | 38.0 pts |
| `ZN.13-PB.2` | 18.8% | 37.4% | 54.2% | 35.4 pts |
| `ZN.6-PB` | 34.6% | 9.9% | 42.7% | 32.9 pts |
| `ZN.2-PB` | 16.1% | 45.0% | 21.9% | 28.8 pts |
| `ZN.17-PB` | 34.7% | 6.1% | 21.4% | 28.6 pts |
| `ZN.19-PB.1` | 0.0% | 26.3% | 18.9% | 26.3 pts |
| `ZN.18-PB` | 2.9% | 24.3% | 13.4% | 21.4 pts |
| `ZN.9-PB` | 31.9% | 13.4% | 12.1% | 19.8 pts |
| `ZN.10-PB.2` | 40.4% | 56.6% | 59.6% | 19.2 pts |
| `ZN.4-PB.2` | 40.7% | 23.2% | 34.8% | 17.5 pts |
| `ZN.8-PB.1` | 17.8% | 31.6% | 18.1% | 13.8 pts |
| `ZN.14-PB` | 28.2% | 22.9% | 35.8% | 12.9 pts |
| `ZN.19-PB.2` | 30.7% | 22.2% | 17.8% | 12.9 pts |
| `ZN.15-PB.2` | 34.2% | 45.7% | 46.6% | 12.4 pts |
| `ZN.1-PB.2` | 21.0% | 30.4% | 26.8% | 9.4 pts |
| `ZN.3-PB.2` | 29.7% | 22.5% | 31.4% | 8.9 pts |
| `ZN.7-PB` | 13.8% | 5.7% | 6.6% | 8.1 pts |
| `ZN.4-PB.1` | 1.8% | 6.9% | 3.7% | 5.1 pts |
| `ZN.16-PB` | 96.4% | 96.4% | 96.7% | 0.3 pts |

**Two distinct patterns are visible in this table, and they should not be conflated:**

- **Highly phase-asymmetric** (top of table, spread above ~65 points): `ZN.10-PB.1`, `ZN.11-PB.1`, `ZN.8-PB.2`, `ZN.11-PB.2`, `ZN.12-PB`, `ZN.3-PB.1`, `ZN.1-PB.1`, `ZN.5-PB`, `ZN.21-PB`. On each of these, at least one phase is near-clean while another is severely affected. Because all three phases share the same supply and the same device, a divergence this large is more readily explained by something specific to one phase's measurement or load path than by a general supply condition, but the cause is not established by this data.
- **Uniformly elevated** (bottom of table): `ZN.16-PB` is the extreme case: 96%+ `Critical` on all three phases with only 0.3 points of spread. This is the one meter with an engineering-confirmed wiring/polarity fault (§5.5), and its uniformity is consistent with a whole-meter rather than single-phase condition.

Meters in the middle of the table sit close to the facility-wide baseline and are not individually flagged in this report.

### 5.2 Active power: negative readings, all meters

**A negative active-power reading is not, by itself, evidence of a fault.** For `ZN.16-PB` the wiring/polarity cause is engineering-confirmed (§5.5). For every other meter listed, the distinction between legitimate export/reverse power flow and a wiring/polarity or metering condition **has not been confirmed** and remains an open item (§10). The values below are reported as observed measurements.

| Meter | Negative TkW readings | % of meter's readings | Min TkW | Dominant phase(s), by average |
|---|---|---|---|---|
| `ZN.16-PB` | 143,774 | 95.4% | −40.88 kW | All three (−3.35, −3.75, −1.67) |
| `ZN.8-PB.2` | 78,531 | 49.6% | −17.04 kW | Phase 1 (−4.43; Phases 2/3 positive) |
| `ZN.12-PB` | 24,136 | 15.7% | −5.48 kW | Phase 3 (−0.55; Phases 1/2 positive) |
| `ZN.5-PB` | 12,989 | 8.2% | −1.62 kW | Phase 1 (−0.34; Phases 2/3 positive) |
| `ZN.8-PB.1` | 4,715 | 3.0% | −8.03 kW | Not yet phase-attributed |
| `ZN.17-PB` | 4,468 | 4.6% | −4.02 kW | Not yet phase-attributed |
| `ZN.10-PB.2` | 3,436 | 2.5% | −7.18 kW | Not yet phase-attributed |
| `ZN.15-PB.2` | 3,293 | 2.0% | −16.57 kW | Not yet phase-attributed |
| `ZN.10-PB.1` | 3,108 | 1.9% | −2.96 kW | Not yet phase-attributed |
| `ZN.13-PB.1` | 3,033 | 2.1% | −6.65 kW | Not yet phase-attributed |
| `ZN.11-PB.2` | 1 | 0.0007% | −13.53 kW | Single isolated reading |
| **Total** | **281,484** | — | — | — |

**Reconciliation:** these eleven counts sum to exactly 281,484, matching the facility-wide negative-TkW total. All 31 meters are accounted for; the 20 not listed have zero negative readings. `ZN.11-PB.2`'s single reading is included for completeness; one reading is not a pattern, though its −13.53 kW magnitude is notable for an isolated occurrence and may warrant a timestamp check (§10).

**`ZN.16-PB`'s active-power total count (143,774) matches the prior assessment's figure exactly.** `ZN.8-PB.2`'s current figure (78,531) differs from the prior assessment's (78,673) by 142 readings. What is established: the meter's total reading count is unchanged (158,627, identical to the prior assessment), so the difference is not caused by new data arriving; and a direct database check found 135 readings sitting within 0.01 kW of zero on the negative side. **The 142-reading difference remains to be reconciled.** Near-zero boundary readings are a plausible contributor but do not fully account for it, and the exact cause should be verified against the prior measure's filter definition before either figure is cited as authoritative (§10).

### 5.3 `ZN.12-PB`: a strong newly identified Phase-3 anomaly candidate

Two independent measurements agree on the same phase: active power (§5.2, Phase 3 average −0.55 kW) and power factor (§5.1, Phase 3 `Critical` rate 95.2%). This is not a borderline or single-measurement signal. It is a well-corroborated anomaly on a meter with no prior documentation. **`ZN.12-PB`'s signature is Phase-3-specific, distinguishing it from the Phase-1-dominant pattern of `ZN.5-PB`/`ZN.8-PB.2` and the all-phase pattern of `ZN.16-PB`**, making it a fourth, distinct signature rather than a variant of an existing one. It has not yet been raised with engineering and is not a confirmed fault (§5.5).

### 5.4 Reactive power: supporting context only, not confirmatory evidence

**Important caveat, per direct guidance from the project team: reactive power's sign has no defined "correct" value**: leading and lagging power factor are both legitimate electrical states, and the classification chart reflects this (no alarms are set on reactive power). The pattern below should be read as corroborating context alongside §5.1–5.2, not as independent proof of anything.

| Meter | Phase 1 avg kVAr | Phase 2 avg kVAr | Phase 3 avg kVAr |
|---|---|---|---|
| `ZN.16-PB` | +16.02 | +24.40 | +16.56 |
| `ZN.5-PB` | +3.45 | −31.88 | −14.26 |
| `ZN.8-PB.2` | +20.57 | −15.96 | −9.83 |

Most other meters in the facility show negative reactive power on all three phases; these three meters' positive values on the same phase(s) already identified in §5.1–5.2 are consistent with, but do not independently prove, the same underlying condition.

### 5.5 Confirmation status: only `ZN.16-PB` is an engineering-confirmed fault

| Meter | Affected phase(s) | Confirmation status |
|---|---|---|
| `ZN.16-PB` | All three | **Confirmed** by project engineering team as a wiring/polarity fault (verbal, via project owner). No reverse-power-flow capability, per team confirmation. |
| `ZN.5-PB` | Phase 1 (dominant) + Phase 3 abnormalities | Open — candidate for a related cause, corroborated by power factor and active power, with reactive power providing supporting context only (§5.4) |
| `ZN.8-PB.2` | Phase 1 | Open — same status as `ZN.5-PB` |
| `ZN.12-PB` | Phase 3 | Open — newly identified in this assessment, not yet raised with engineering |

**This resolves an open question from the prior assessment**, and shows the three meters have three different phase footprints rather than one shared signature:

- **`ZN.16-PB`**: uniform across all three phases (PF 96.4%/96.4%/96.7% `Critical`; active power negative on all three).
- **`ZN.8-PB.2`**: Phase-1-specific (PF 96.7% on Phase 1 vs. 4.4%/5.7% on Phases 2/3).
- **`ZN.5-PB`**: Phase-1-dominant with additional Phase-3 abnormalities (PF 92.8% on Phase 1, but also 49.0% on Phase 3; plus a Phase-3 current signal, §4.6).

`ZN.16-PB`'s all-phase pattern means it likely does not share the other two meters' exact root cause despite the similar symptom. `ZN.5-PB`'s Phase-3 behaviour further distinguishes it from `ZN.8-PB.2`.

### 5.6 Data preservation

No correction is applied to any of these four meters' readings. Source fidelity is preserved deliberately, per project decision; each condition is documented here as known.

**Monitoring gap, carried forward from prior assessment and still applicable:** active power carries no status classification (§2.2), so none of these four meters' negative-power conditions produce any status flag. They remain visible only through direct examination of raw values, as done in this section. A dashboard measure on raw `active_power_*_kw` is recommended (§10).

## 6. Accumulated Energy (`kWh`)

| | Count | % of total |
|---|---|---|
| Total readings | 4,535,918 | — |
| Decrements (`status_kwh = Invalid`) | 63 | 0.0014% |

| Meter group | Meters | Decrements |
|---|---|---|
| `ZN.13-PB.1` | 1 | 19 |
| `ZN.13-PB.2` | 1 | 19 |
| Meters with exactly one decrement | 25 | 25 |
| Meters with no decrements (`ZN.17-PB`, `ZN.20-PB.1`, `ZN.20-PB.2`, `ZN.4-PB.2`) | 4 | 0 |
| **Total** | **31** | **63** |

**`ZN.13-PB.1` and `ZN.13-PB.2` together account for 60.3% of every decrement in the facility**, while every other meter shows at most one. This is a real, concentrated signal on the two meters that already carry a documented non-standard configuration (the confirmed "one panel serving two meters" exception; see Data Dictionary §3). Worth investigating whether the shared panel arrangement relates to the elevated decrement rate.

**The isolated single-occurrence decrements require timestamp validation before being interpreted as counter-reset or startup artifacts.** A check of each occurrence against that meter's earliest reading would establish whether these are one-time boundary events or genuine mid-series decrements (§10).

## 7. Cross-Metric Synthesis

The table below shows every meter flagged anywhere in §4–6, with **actual values in every cell** rather than presence/absence marks. A meter appearing with a low number in one column has been measured on that metric and found unremarkable relative to the facility baseline; it does not mean the metric was unexamined.

**PF columns show each phase's `Critical` rate.** These must be read against the facility-wide baseline of 32–38% `Critical` per phase (§5.1); a meter at 30% is at baseline, not elevated. "PF asym." marks the nine meters with phase spread above 65 points (§5.1).

| Meter | Current: max mismatch (phase) | PF1 / PF2 / PF3 `Critical` % | PF asym. | Negative TkW | kWh decrements |
|---|---|---|---|---|---|
| `ZN.20-PB.1` | 30,637 (P1) | 36.6 / 40.0 / 2.0 | — | 0 | 0 |
| `ZN.10-PB.2` | 21,970 (P3) | 40.4 / 56.6 / 59.6 | — | 3,436 | 1 |
| `ZN.10-PB.1` | 8,822 (P2) | 62.5 / 99.2 / 2.9 | **yes** | 3,108 | 1 |
| `ZN.2-PB` | 3,122 (P2) | 16.1 / 45.0 / 21.9 | — | 0 | 1 |
| `ZN.8-PB.1` | 2,552 (P2) | 17.8 / 31.6 / 18.1 | — | 4,715 | 1 |
| `ZN.7-PB` | 1,985 (P1) | 13.8 / 5.7 / 6.6 | — | 0 | 1 |
| `ZN.9-PB` | 656 (P3) | 31.9 / 13.4 / 12.1 | — | 0 | 1 |
| `ZN.17-PB` | 575 (P2) | 34.7 / 6.1 / 21.4 | — | 4,468 | 0 |
| `ZN.3-PB.2` | 357 (P3) | 29.7 / 22.5 / 31.4 | — | 0 | 1 |
| `ZN.12-PB` | 260 (P3) | 14.4 / 65.8 / 95.2 | **yes** | 24,136 | 1 |
| `ZN.19-PB.2` | 232 (P1) | 30.7 / 22.2 / 17.8 | — | 0 | 1 |
| `ZN.1-PB.2` | 223 (P3) + 214 upper-margin (P1) | 21.0 / 30.4 / 26.8 | — | 0 | 1 |
| `ZN.11-PB.2` | 167 (P1) | 19.2 / 92.3 / 0.0 | **yes** | 1 | 1 |
| `ZN.21-PB` | 166 (P2) | 0.0 / 68.2 / 0.0 | **yes** | 0 | 1 |
| `ZN.5-PB` | 127 (P3) | 92.8 / 18.3 / 49.0 | **yes** | 12,989 | 1 |
| `ZN.14-PB` | 112 (P3) | 28.2 / 22.9 / 35.8 | — | 0 | 1 |
| `ZN.16-PB` | 3 (below thresh.) | 96.4 / 96.4 / 96.7 | — (uniform) | 143,774 | 1 |
| `ZN.8-PB.2` | 3 (below thresh.) | 96.7 / 4.4 / 5.7 | **yes** | 78,531 | 1 |
| `ZN.11-PB.1` | 1 (below thresh.) | 3.1 / 82.7 / 96.4 | **yes** | 0 | 1 |
| `ZN.3-PB.1` | 0 | 0.0 / 12.3 / 76.2 | **yes** | 0 | 1 |
| `ZN.1-PB.1` | 1 (below thresh.) | 75.2 / 43.4 / 0.6 | **yes** | 0 | 1 |
| `ZN.15-PB.2` | 7 (below thresh.) | 34.2 / 45.7 / 46.6 | — | 3,293 | 1 |
| `ZN.13-PB.1` | 2 (below thresh.) | 52.5 / 29.1 / 85.2 | — | 3,033 | **19** |
| `ZN.13-PB.2` | 27 (below thresh.) | 18.8 / 37.4 / 54.2 | — | 0 | **19** |

### 7.1 Group overlap: measured, not assumed

Comparing the three finding groups directly:

| Comparison | Overlap | Meters |
|---|---|---|
| Current mismatch (16) ∩ PF asymmetric (9) | **5 of 16** | `ZN.10-PB.1`, `ZN.11-PB.2`, `ZN.12-PB`, `ZN.21-PB`, `ZN.5-PB` |
| Current mismatch (16) ∩ negative TkW (11) | **7 of 16** | `ZN.10-PB.1`, `ZN.10-PB.2`, `ZN.11-PB.2`, `ZN.12-PB`, `ZN.17-PB`, `ZN.5-PB`, `ZN.8-PB.1` |
| PF asymmetric (9) ∩ negative TkW (11) | **5 of 9** | `ZN.10-PB.1`, `ZN.11-PB.2`, `ZN.12-PB`, `ZN.5-PB`, `ZN.8-PB.2` |
| Present in **all three** groups | **4 meters** | `ZN.10-PB.1`, `ZN.11-PB.2`, `ZN.12-PB`, `ZN.5-PB` |
| Union of all three groups | **23 of 31 meters** | — |

**These groups overlap substantially; they are not separate populations.** Seven of the sixteen meters flagged for current/power mismatch also show negative active power, and four meters (`ZN.10-PB.1`, `ZN.11-PB.2`, `ZN.12-PB`, and `ZN.5-PB`) appear in all three finding groups. Taken together the three groups cover 23 of the 31 meters.

**What this does and does not tell us.** The overlap is consistent with shared underlying causes affecting several metrics on the same meters, but it does not establish that. Three caveats apply: the groups have different membership thresholds (a 100-reading count for current, a 65-point spread for PF, any negative value for active power), so overlap is partly an artifact of where those lines were drawn; PF and active power are mathematically related, so co-occurrence between those two is expected rather than independent evidence; and no phase-level alignment has been checked across metrics for most meters. **A formal cross-metric comparison, phase by phase and with consistent thresholds, is required before drawing any conclusion about shared causation** (§10).

**One observation that is well-supported:** the four meters with the largest current findings (`ZN.20-PB.1` (30,637), `ZN.2-PB` (3,122), `ZN.7-PB` (1,985), and `ZN.9-PB` (656)) all have **zero** negative active-power readings. Conversely, the two largest negative-power meters, `ZN.16-PB` (143,774) and `ZN.8-PB.2` (78,531), register only **3 current mismatch readings each**, far below threshold. The extremes of the two distributions do not coincide.

`ZN.12-PB` is the notable exception in the other direction: it ranks third for negative active power (24,136) *and* exceeds the current mismatch threshold (260 on Phase 3) *and* is phase-asymmetric in PF (95.2% `Critical` on Phase 3), with all three findings landing on **the same phase**. It is the single strongest candidate for a shared underlying cause anywhere in this dataset, though that remains unconfirmed (§10).

## 8. Voltage and Frequency: Confirmed Clean

| Measurement | Acceptable | Critical | Review Required |
|---|---|---|---|
| Frequency | 4,535,917 | 1 | 0 |
| Voltage Line, Phase 1 | 4,535,915 | 2 | 1 |
| Voltage Line, Phase 2 | 4,535,916 | 2 | 0 |
| Voltage Line, Phase 3 | 4,535,916 | 2 | 0 |
| Voltage Neutral, Phase 1 | 4,535,916 | 2 | 0 |
| Voltage Neutral, Phase 2 | 4,535,916 | 2 | 0 |
| Voltage Neutral, Phase 3 | 4,535,917 | 1 | 0 |

Across 31,751,426 voltage/frequency classifications (7 channels × 4,535,918 readings), only 13 were non-Acceptable, approximately 0.000041%: 12 `Critical` and 1 `Review Required`.

- The 12 `Critical` classifications are concentrated on **`ZN.13-PB.1`** and occur across two reading packets: 7 flagged measurements at `2024-12-26 18:40:33.523 UTC` and 5 flagged measurements at `2024-12-27 13:32:34.917 UTC`.
- The single `Review Required` classification (Voltage Line, Phase 1) occurs on **`ZN.16-PB`** at `2025-06-02 20:38:08.169 UTC`, not `ZN.13-PB.1`.

The clustering of `ZN.13-PB.1`'s 12 `Critical` classifications into two reading packets establishes that the finding is concentrated in two brief events rather than spread persistently across the history. The common physical cause, if any, remains unverified.

Regardless, the exhaustive per-phase counts above establish that **no persistent out-of-range voltage or frequency pattern was observed in the assessed historical data.** This is a statement about the observed record, not a forward-looking guarantee about supply quality.

## 9. Data Preserved, Not Corrected

Consistent with project policy throughout, no raw values have been modified as a result of any finding in this report. All classification is diagnostic overlay only.

## 10. Open Items & Recommendations

**New, from this assessment:**

1. **Investigate `ZN.20-PB.1` as the highest-priority current/power measurement inconsistency in the facility**: Phase 1 and Phase 3, ~19% of Phase 1 readings affected, no prior documentation. Scope should cover current sensing, CT wiring, device configuration, and channel synchronisation, since the data does not distinguish between these (§4.2).
2. **Investigate `ZN.10-PB.2`'s multi-phase current pattern**, Phase 3 dominant (§4.3).
3. **Raise `ZN.12-PB`'s Phase-3 anomaly with engineering** for assessment alongside the existing `ZN.5-PB`/`ZN.8-PB.2` confirmation request; it is currently a strong candidate, not a confirmed fault (§5.3, §5.5).
4. **Investigate `ZN.5-PB`'s new Phase 3 current signal** and whether it connects to its known Phase 1 active-power/PF fault, or is an independent finding (§4.6).
5. **Investigate `ZN.1-PB.2`'s current levels relative to its own breaker rating**: the only meter in the facility showing this pattern (§4.5).
6. **Investigate Zone 13's elevated `kWh` decrement rate** (60% of the facility total on 2 of 31 meters) in connection with its already-documented shared-panel configuration (§6).
7. **Validate the single-occurrence `kWh` decrements via a timestamp check** before interpreting them as counter-reset or startup artifacts (§6).

**Carried forward, still open:**

8. **Confirm with engineering whether `ZN.5-PB` and `ZN.8-PB.2` share `ZN.16-PB`'s wiring/polarity cause**: corroborated by power factor and active power, with reactive power providing supporting context only (§5.4). Note that the phase footprints differ: `ZN.16-PB` is uniform across all three phases, `ZN.8-PB.2` is Phase-1-specific, and `ZN.5-PB` is Phase-1-dominant with additional Phase-3 abnormalities.
9. **Completed: explicit dashboard monitoring for negative active power is now implemented**, including total and phase-level negative-power views, raw reading evidence, and meter-level drill-through investigation. Active power still carries no status classification (§5.6).
10. **Root-cause the remaining low-coverage meters** (`ZN.21-PB`, `ZN.9-PB`, `ZN.20-PB.2`, `ZN.19-PB.1`) using the same method applied to `ZN.17-PB` (§3.3).
11. **Confirm whether Zone 13's distinct ~321s reading cadence is intended device configuration.**
11a. **Completed: timestamp alignment for `ZN.13-PB.1`'s 12 `Critical` voltage/frequency classifications was checked.** They occur in two reading packets: 7 flagged measurements at `2024-12-26 18:40:33.523 UTC` and 5 at `2024-12-27 13:32:34.917 UTC` (§8).
12. **Collect per-meter `kWh` increment step sizes** to enable a step-size validation tier beyond the current decrement-only check.
13. Consumption across `ZN.17-PB`'s long telemetry gap is intentionally retained under the approved business rule. The remaining caveat is temporal attribution: the accumulated increase across the 201.36-day gap is assigned to the first reading after telemetry resumes on 2025-12-05 (§3.3).
14. **Reconcile the 142-reading difference** in `ZN.8-PB.2`'s negative active-power count against the prior measure's filter definition (§5.2).
15. **Extend the unpopulated-key check across the full 19-month history**, rather than the sampled window, to convert "not observed in window" into a definitive statement (§3.2).
16. **Investigate the phase-asymmetric power-factor group** identified in §5.1 (spread above ~65 points): nine meters where at least one phase is near-clean while another is severely affected.
17. **Decide whether PF classification should be gated below a minimum current or load threshold**, and whether any dashboard PF figure should be load-weighted rather than a simple average. Low-load periods physically produce low PF, so the current facility-wide 44–45% `Acceptable` rate may substantially reflect normal light-load operation rather than a power-quality problem (§5.1).
18. **Confirm, for every meter with negative active power other than `ZN.16-PB`, whether the cause is legitimate export/reverse power flow or a wiring/polarity condition** (§5.2). Reverse-flow capability has been ruled out by the team for `ZN.16-PB` specifically; that confirmation does not extend to the other ten meters.
19. **Run a formal cross-metric comparison, phase by phase and with consistent thresholds, before drawing any conclusion about shared causation** across the current, PF, and active-power finding groups (§7.1).
20. **Capture the authoritative classifier definitions and breaker capacities in the evidence package.** The live database is the source of truth for both: classifier bodies should be captured via `pg_get_functiondef()` output rather than from saved script files, and breaker capacities should be queried from `silver.dim_meter_cb_rating` (and cross-checked against the source engineering record) rather than inferred from any intermediate document. Every current-classification finding in §4 depends on those capacity values being correct, so this should be treated as a prerequisite for citing §4 externally.
21. **Check the timestamp of `ZN.11-PB.2`'s single −13.53 kW reading** (§5.2). An isolated reading of that magnitude may indicate a discrete event worth understanding.

## 11. Evidence Register

| Finding | Evidence | Confirmation source | Status |
|---|---|---|---|
| PF classification outcome: 44–45% `Acceptable` per phase under current thresholds | Full per-phase, per-meter classification counts, all 31 meters | Internal analysis, this session | Classifier output confirmed; electrical interpretation open pending low-load gating decision |
| Current / PF / negative-power finding groups overlap substantially (7 of 16, 5 of 9, 5 of 16; 4 meters in all three) | Direct set comparison, §7.1 | Internal analysis, this session | Overlap measured; shared causation NOT established |
| `ZN.12-PB` shows current, PF, and negative-power findings all on Phase 3 | Three-metric phase alignment, §7.1 | Internal analysis, this session | Strongest shared-cause candidate; unconfirmed |
| Negative active power indicates wiring/polarity fault (meters other than `ZN.16-PB`) | Negative-reading counts, §5.2 | Not obtained — export/reverse-flow not ruled out | Open |
| Authoritative classifier bodies and breaker capacities captured from live database | Not yet performed | — | Open — prerequisite for citing §4 externally |
| Phase-asymmetric PF group (9 meters, spread >65 pts) | Full per-meter three-phase `Critical` rate comparison | Internal analysis, this session | New — cause not identified |
| `ZN.20-PB.1` Phase 1/3 current/power inconsistency | Facility-wide per-phase status breakdown, 89–91% concentration | Internal analysis, this session | New — pattern established, cause not identified, not yet raised with engineering |
| `ZN.10-PB.2` multi-phase current/power inconsistency | Same method | Internal analysis, this session | New — cause not identified |
| `ZN.16-PB` all-phase PF/active-power/reactive-power pattern | Cross-phase, cross-metric agreement | Internal analysis, this session; wiring fault itself confirmed by engineering | Wiring fault confirmed; all-phase extent newly established |
| `ZN.8-PB.2` Phase-1-specific pattern | Cross-phase PF + active-power agreement | Internal analysis, this session | Pattern confirmed; root-cause relation to `ZN.16-PB` still open |
| `ZN.5-PB` Phase-1-dominant with additional Phase-3 abnormalities | Cross-phase PF (92.8% P1, 49.0% P3) + Phase-3 current signal | Internal analysis, this session | Pattern confirmed; differs from `ZN.8-PB.2`; root cause open |
| `ZN.12-PB` Phase-3-specific anomaly | Active power + power factor agreement on same phase | Internal analysis, this session | New — strong candidate, not confirmed, not yet raised with engineering |
| `ZN.5-PB` new Phase 3 current signal | Per-phase current status breakdown | Internal analysis, this session | New |
| Zone 13 elevated `kWh` decrement rate | Per-meter decrement count | Internal analysis, this session | New |
| Voltage/frequency confirmed clean, all phases (13 non-Acceptable of 31,751,426 classifications) | Exhaustive per-phase, per-meter breakdown | Internal analysis, this session | Confirmed with full evidence (previously an unverified claim) |
| `ZN.13-PB.1` voltage/frequency `Critical` classifications are concentrated in two reading packets | Same meter affected across multiple voltage/frequency channels; timestamp alignment completed | Internal analysis, this session | Timing confirmed; common physical cause remains open |
| Zone 17 telemetry gap (201.36 days) | Gap-clustering analysis | Project team | Confirmed (zone-level; mechanism not verified) |
| Volume lossless, Bronze through analytical layer | Five independent counting methods, per-meter Bronze comparison | Internal verification | Confirmed |
| Eight telemetry keys not observed for any meter | Bronze distinct-key count, uniform 24-of-32 across meters reporting in the sampled window | Internal verification | Confirmed within validated window; full-history check outstanding |
