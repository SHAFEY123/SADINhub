# SADINhub: Exploratory Data Analysis (EDA) Report
**Energy Intelligence & Predictive Analytics Platform**


## 1. Purpose and Scope

This report explores operational, energy-consumption, and electrical behavior patterns in SADINhub's telemetry data using the current analytical sources `gold.energy_raw` and `gold.energy_consumption_validated`. The Data Assessment Report establishes data-quality limitations and approved exclusions; this EDA focuses on the operational patterns that can be interpreted reliably within those rules.

**In scope:**
- Consumption patterns (daily, hourly, weekday/weekend, seasonal) across the 29 meters included in the validated consumption fact
- Power quality patterns (voltage stability, power factor, reactive power, demand)
- Raw electrical behavior across all 31 canonical energy meters
- Meter-level comparisons to identify which zones drive overall facility behavior
- Cross-referencing patterns against already-known data quality findings (e.g., confirmed wiring faults), where doing so adds insight rather than repeating the Data Assessment Report

**Out of scope for this report:**
- Billing/cost analysis: real billing data and tariff criteria are not yet available (see Data Assessment Report §6 and Data Dictionary §10)
- Forecasting and anomaly-detection modeling: planned as a separate, later project phase (charter Weeks 7-8)
- Water-related data: excluded from this project's scope entirely

**Data quality caveat carried forward from the Data Assessment Report:** `ZN.16-PB` is engineering-confirmed as a wiring/polarity fault. `ZN.5-PB` and `ZN.8-PB.2` remain open candidates with related active-power / power-factor sign abnormalities; their root cause has not been independently confirmed. Findings below distinguish confirmed conditions from candidate patterns rather than treating all three as the same fault.


## 2. Data Overview

| Item | Detail |
|---|---|
| Source | `gold.energy_consumption_validated` for validated energy consumption; `gold.energy_raw` for raw-grain demand, power factor, voltage, current, and active/reactive-power exploration |
| Time period covered | ~December 2024 – July 2026 (~19 months) |
| Meters analyzed | 31 canonical energy meters overall; validated consumption includes 29 meters because `ZN.13-PB.1` and `ZN.13-PB.2` are excluded from the approved consumption fact |
| Measurement categories analyzed in this report | Active energy consumption (kWh), demand (instantaneous kW), power factor, reactive power (kVAr), voltage (Line-to-Neutral) |
| Timezone convention | All time-of-day and weekday/weekend analysis uses Asia/Riyadh local time, with Friday–Saturday as the weekend (matching the facility's actual work week) |
| Analysis method | Validated consumption uses the approved interval-level fact `gold.energy_consumption_validated`; raw electrical behavior uses `gold.energy_raw`. Weekday/weekend consumption uses Asia/Riyadh local dates with Friday–Saturday as weekend. Long telemetry gaps are retained as valid cumulative consumption and explicitly flagged for time-attribution interpretation. |

**Validated consumption basis:** consumption analysis uses the implemented and reconciled `gold.energy_consumption_validated` fact. Approved long-gap cumulative increases are retained as valid consumption and flagged as `LONG_GAP`; therefore total consumption is preserved, while time-bucketed reporting around a telemetry-resumption timestamp can concentrate consumption accumulated during the missing period. Across the 29 included meters, validated consumption reconciles exactly to the approved cumulative-register baselines.

### 2.1 Methodology Validations and Remaining Limitations

The following methodology checks define how combined and facility-level figures are interpreted:

- **Parent/child meter overlap (verified).** `silver.dim_energy_meter_staging` contains `parent_energy_meter_source_id`. The verification query below returns no rows, so none of the 31 canonical meters has a recorded parent-meter relationship to another canonical meter. This supports combined meter totals with respect to the recorded parent field; physical electrical topology would still require engineering sign-off for independent confirmation.
- **Power factor combination method (verified).** A load-weighted facility PF requires usable apparent-power telemetry. Across all **4,535,918 raw analytical readings** in `gold.energy_raw`, `apparent_power_total_kva` is populated in **0 rows**, and **0 meters** report a non-NULL value. An authoritative load-weighted facility PF therefore cannot be constructed from the available telemetry. The EDA focuses on **phase-level PF behavior and meter-level comparisons**, which are descriptive analytical measures rather than a single electrically load-weighted facility PF.

**Verification query: apparent power availability in the current raw-grain analytical dataset (run and confirmed):**
```sql
SELECT
    COUNT(*) AS total_rows,
    COUNT(apparent_power_total_kva) AS rows_with_tkva,
    COUNT(DISTINCT energy_meter_key)
        FILTER (WHERE apparent_power_total_kva IS NOT NULL) AS meters_reporting_tkva
FROM gold.energy_raw;
```
**Result:** `total_rows = 4,535,918`, `rows_with_tkva = 0`, `meters_reporting_tkva = 0`. Confirmed: no total apparent-power (`TkVA`) value is populated anywhere in the current `gold.energy_raw` analytical dataset.

**Verification query: parent/child overlap check (run and confirmed; no rows returned):**
```sql
SELECT
    m.meter_label AS child_meter,
    m.parent_energy_meter_source_id,
    p.meter_label AS parent_meter_if_canonical
FROM silver.dim_energy_meter_staging m
LEFT JOIN silver.dim_energy_meter_staging p
    ON p.source_energy_meter_id = m.parent_energy_meter_source_id
WHERE m.parent_energy_meter_source_id IS NOT NULL;
```
**Result: 0 rows.** No recorded parent/child relationship exists among the 31 canonical meters. None carries a `parent_energy_meter_source_id` pointing to another canonical meter. This confirms no double-counting through the recorded parent field specifically; full physical-topology sign-off from engineering is the only remaining step to treat combined totals as fully authoritative, but this result substantially de-risks the concern for the purposes of this report.

**PF approach used in this report:** since apparent power is unavailable, the final PF exploration does not present a single electrically load-weighted facility PF. Instead it compares the validated phase-level PF classification rates meter by meter, with particular attention to phase asymmetry. These are descriptive classifier outcomes, not an authoritative facility PF number; low-load periods can physically produce low PF and remain an interpretation caveat.


## 3. Findings

### 3.1 Validated consumption is concentrated in a smaller set of included zones

Validated consumption across the 29 included meters is **2,020,697.5 kWh** over the assessed history. `ZN.13-PB.1` and `ZN.13-PB.2` are deliberately excluded from the validated consumption fact under the approved kWh data-quality rule and are therefore not included in consumption totals or rankings.

Among the included zones, **Zone 19 is the largest validated consumer**: `ZN.19-PB.1` (66,564.0 kWh) plus `ZN.19-PB.2` (179,704.4 kWh) total approximately **246,268.4 kWh**. Zone 4 follows at approximately **205,706.0 kWh** (`ZN.4-PB.1` + `ZN.4-PB.2`). At the meter level, `ZN.19-PB.2` is the largest individual validated consumer at **179,704.4 kWh**.

At the opposite end, `ZN.16-PB` is the lowest included meter at approximately **5,830.5 kWh**. Its low consumption is worth operational review because it is also the one meter with an engineering-confirmed wiring/polarity fault; however, the telemetry alone does **not** prove that its cumulative kWh register or billing consumption is understated.

### 3.2 Weekend consumption is higher than weekday consumption

Using the validated 29-meter consumption fact and Saudi-local calendar dates, average daily consumption is approximately **4,145.1 kWh on weekend days (Friday–Saturday)** versus **3,339.6 kWh on weekdays**. Weekend daily consumption is therefore about **24.1% higher** than weekday consumption in the validated history.

This is worth reviewing because facility usage is often expected to be lower on weekends. It should be reviewed with facility operations to determine whether weekend production, cooling, maintenance, occupancy, or equipment schedules explain the pattern.

### 3.3 Daily active-power profile shows a clear daytime operating cycle

The 24-hour profile uses raw-grain `active_power_total_kw` from `gold.energy_raw`. The average meter active-power profile is lowest overnight, rises steadily through the morning, reaches its highest level around early-to-mid afternoon, and then declines through the evening.

Using Saudi-local clock interpretation of the validated UTC-hour profile, average meter active power is roughly **2.9–3.1 kW around midnight to early morning**, rises above **5 kW by late morning**, and peaks at approximately **5.7 kW around 2 PM**, before falling again through the evening.

The profile shows a clear daytime operating cycle, consistent with higher facility activity during the day.

### 3.4 Monthly consumption trend with a long-gap time-attribution caveat

The validated monthly series shows substantial month-to-month variation under the approved consumption logic.

Key monthly values include:
- **December 2025: 233,631.7 kWh**
- **May 2026: 130,883.4 kWh**
- **June 2026: 183,598.6 kWh**

`ZN.17-PB` has a confirmed **201.36-day telemetry gap** ending on 2025-12-05. Under the approved rule, the cumulative increase across that gap is intentionally retained as valid consumption. The issue is **time attribution**, not an invalid total: consumption accumulated during the missing period is concentrated at the first valid reading after telemetry resumes. December 2025 and any daily/hourly bucket around the resumption timestamp should be interpreted with that caveat.

Year-over-year behavior is mixed rather than uniformly increasing: May 2026 (**130,883.4 kWh**) is below May 2025 (**141,969.9 kWh**), while June 2026 (**183,598.6 kWh**) is above June 2025 (**138,596.4 kWh**).

### 3.5 Voltage and frequency are exceptionally stable in the assessed history

Raw-grain validation shows exceptionally stable voltage and frequency behavior. Across **31,751,426 voltage/frequency classifications** (7 channels × 4,535,918 readings), only **13** were non-Acceptable: 12 `Critical` classifications and 1 `Review Required`.

The 12 `Critical` classifications are concentrated in two `ZN.13-PB.1` reading packets, while the single `Review Required` line-voltage classification occurs on `ZN.16-PB`. No persistent out-of-range voltage or frequency pattern was observed in the assessed history.

### 3.6 Power factor: phase asymmetry is more informative than a single facility average

PF analysis uses phase-level `Critical` classification rates rather than a single facility-wide average. Under the configured thresholds, only about **44–45%** of PF readings classify as `Acceptable` on each phase, while roughly one-third classify as `Critical`. These are classifier outcomes, not proof of poor electrical operation: the PF classifier applies PF thresholds at all load levels, and low-load periods can physically produce low PF.

The more diagnostically useful EDA finding is **phase asymmetry**. Nine meters show a spread above 65 percentage points between their highest and lowest phase `Critical` rates. Examples include:

- `ZN.10-PB.1`: **62.5% / 99.2% / 2.9%**
- `ZN.11-PB.1`: **3.1% / 82.7% / 96.4%**
- `ZN.8-PB.2`: **96.7% / 4.4% / 5.7%**
- `ZN.12-PB`: **14.4% / 65.8% / 95.2%**
- `ZN.5-PB`: **92.8% / 18.3% / 49.0%**

This phase-by-phase pattern is more actionable than a blanket facility-level PF statement. `ZN.16-PB` is different: it is uniformly high-Critical across all three phases (96%+ each) and is the one meter with an engineering-confirmed wiring/polarity fault.

### 3.7 Active-power direction is a major cross-meter pattern; reactive power remains supporting context only

There are **281,484 negative total active-power readings** across 11 meters. The largest concentrations are:

- `ZN.16-PB`: **143,774** negative TkW readings
- `ZN.8-PB.2`: **78,531**
- `ZN.12-PB`: **24,136**
- `ZN.5-PB`: **12,989**

A negative active-power value is not automatically a fault. `ZN.16-PB` is engineering-confirmed as a wiring/polarity fault; for the other meters, legitimate reverse/export flow versus metering/wiring behavior remains unresolved.

Reactive power is treated as **supporting context only**. Its sign can legitimately be positive or negative depending on leading/lagging behavior, and the project does not classify reactive power as a fault condition. It is therefore not used as independent evidence of a PF or wiring fault.

### 3.8 Confirmed versus candidate wiring/polarity patterns

- **`ZN.16-PB`:** engineering-confirmed wiring/polarity fault; abnormal behavior is broad across all three phases.
- **`ZN.8-PB.2`:** open candidate; the dominant pattern is Phase-1-specific.
- **`ZN.5-PB`:** open candidate; Phase 1 is dominant, with additional Phase-3 abnormalities.

A fourth meter, **`ZN.12-PB`**, is a strong newly identified Phase-3 anomaly candidate because negative active power and high PF `Critical` rate align on the same phase. It has not yet been confirmed by engineering.

The EDA supports several distinct phase-specific signatures rather than one proven facility-wide wiring problem.

## 4. Recommendations and Conclusion

### 4.1 Recommendations

1. **Use `gold.energy_consumption_validated` as the authoritative analytical source for consumption EDA.** Zone 13 remains excluded from validated consumption totals and rankings under the approved kWh rule.
2. **Review the higher weekend consumption pattern with facility operations.** Validated average daily consumption is ~4,145.1 kWh on weekends versus ~3,339.6 kWh on weekdays.
3. **Treat `ZN.17-PB`'s 201.36-day gap as a time-attribution limitation**, not as invalid total consumption. Avoid interpreting the resumption-day/month bucket as consumption that physically occurred only at that time.
4. **Investigate the phase-asymmetric PF group rather than making a blanket facility PF-correction recommendation.** Any engineering recommendation should also consider low-load PF behavior before acting on classifier rates.
5. **Continue explicit monitoring of negative active power** and distinguish legitimate reverse/export flow from metering/wiring conditions. Only `ZN.16-PB` is currently confirmed as a wiring/polarity fault.
6. **Raise `ZN.12-PB` with engineering** because its Phase-3 negative active power and PF behavior align on the same phase.
7. **Treat reactive-power sign and magnitude as supporting context, not independent fault evidence**, unless engineering establishes the expected sign/scaling convention.
8. **Resolve Zone 13's kWh integrity exclusion before using Zone 13 in validated consumption rankings or cost conclusions.**

### 4.2 Conclusion

The facility shows a clear daytime operating cycle and exceptionally stable historical voltage/frequency behavior. Validated consumption is **2,020,697.5 kWh across 29 included meters**, with Zone 13 excluded from consumption analysis under the approved kWh rule. Weekend consumption is higher than weekday consumption, and the monthly series shows meaningful variation that should be interpreted with the documented `ZN.17-PB` long-gap time-attribution caveat.

Power-factor behavior is most informative when evaluated phase by phase rather than as one facility average. Negative active power is widespread enough to merit dedicated monitoring but is not automatically a fault. Only `ZN.16-PB` is engineering-confirmed as a wiring/polarity fault; `ZN.5-PB`, `ZN.8-PB.2`, and `ZN.12-PB` remain investigation candidates with distinct phase signatures.

This EDA complements the Data Assessment Report: the Assessment establishes data trust, exclusions, and quality limitations, while this report focuses on the operational patterns supported by the validated consumption and raw-grain electrical data.
