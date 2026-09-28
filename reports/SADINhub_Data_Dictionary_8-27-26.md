SADINhub Data Dictionary
Energy Intelligence & Predictive Analytics Platform

Scope: Electrical energy data only (water-related tables are explicitly out of scope for this project).

*Last updated 2026-08-24: live PostgreSQL metadata extracted and incorporated: production current-classifier overload verified, `overall_status` inputs corrected, object types/keys/indexes confirmed, and formal object/DQ/lineage/column catalogs added. Governance fields are documented only where established; no DAMA-DMBOK or ISO/IEC 11179 compliance is claimed.*


## 1. Architecture Overview

| Layer | Purpose | Location |
| ----------------------- | ------------------------------------------------------------------ | --------------- |
| Bronze                  | Raw source data, restored unchanged from `ssbms.public`            | schema `bronze` |
| Silver                  | Technical normalization, canonical mapping, quality classification | schema `silver` |
| Gold                    | Reporting/BI-facing objects consumed by Power BI                   | schema `gold`   |

**Source volume:** ~107 Bronze tables, ~109M raw telemetry rows, 32 electrical telemetry keys, 31 canonical energy meters, 1 facility.

**Core principle: raw grain, end to end.** The pipeline serves data at its native reading grain (~5 minutes) from Bronze through to Gold. No pre-aggregation is performed in the database; any summarization by hour, day, week, or month happens in the BI layer. This keeps one source of truth, preserves full precision for pinpoint investigation, and means a reported value can always be traced back to a specific meter at a specific timestamp.

**Bronze is never modified.** Silver landing views perform technical normalization only; no trimming, dedup, interpolation, or permanent unit conversion. Canonical business-rule corrections (zone mapping fixes) happen only in Silver staging views.

**Gold contents:**

- `gold.energy_raw`: the raw fact (measured values + quality status), one row per meter per timestamp
- `gold.energy_consumption_validated`: validated interval-level `kWh` consumption derived from the cumulative register; see §10
- `gold.energy_reading_gaps`: reporting-gap evidence derived from consecutive same-meter reading timestamps; see §11
- `gold.meter`, `gold.zone`, `gold.facility`, `gold.billing_account`, `gold.date`: dimensions
- `gold.energy_bill`, `gold.mapping_audit`, `gold.quality_summary`: supporting objects


## 2. Silver Staging: Core Dimensions

### `silver.dim_energy_meter_staging`

One canonical row per reporting device/meter. Joins meter and device metadata, assigns facility/zone/billing relationships, and resolves confirmed mapping exceptions for Zones 03, 13, and 20.

Key columns: `energy_meter_key` (uuid, logical unique key; this is a view, so PostgreSQL does not enforce a primary key), `source_energy_meter_id`, `facility_key`, `zone_key`, `grid_billing_account_key`, `parent_energy_meter_source_id`, `meter_label`, `meter_serial_number`, `phase_count`, `maximum_kwh`, `energy_meter_type_name`, `is_meter_active`, `device_name`, `device_label`, `device_type_name`, `device_category_name`, `is_device_active`, `is_device_online`, `mapping_status`.

`mapping_status` values: `TEAM_CONFIRMED_NAME_CORRECTION` (Zone 03), `TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS` (Zone 13), `VALID`, `REVIEW_NAME_MISMATCH`, `REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH`, `REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED`.

**Note on Zone 20:** the live view excludes one confirmed duplicate mapping via a direct `WHERE NOT (device_id = '9574e049-9fb7-46db-9f8c-b3da0666aea0' AND meter_label = 'ZN.20-PB.2_child__1_ch3pm')`. Retained Zone 20 rows report `mapping_status = 'VALID'`.

**Note on `energy_meter_key`:**** this value is identical to Bronze's `device_id`, verified by joining `bronze.telemetries.device_id` directly to `energy_meter_key` across all 31 meters with exact packet-count matches. No ID remapping occurs between Bronze and Silver.

### `silver.dim_meter_cb_rating`

Per-meter circuit breaker maximum current rating. One row per canonical meter (31 rows).

| Column | Type | Description |
| ------------------------ | ---------------- | ----------------------------------------- |
| `energy_meter_key`       | uuid             | Primary key                               |
| `cb_max_rating_a`        | double precision | That meter's real breaker rating, in amps |
| `updated_at`             | timestamp        | Last modification                         |

Values range from 80A to 250A depending on the panel. This table exists because current classification cannot use a single facility-wide threshold; see §7.3.

No foreign key to `dim_energy_meter_staging`: that object is a view, and PostgreSQL foreign keys can only reference tables. Referential correctness is enforced at load time by joining on `meter_label`.

### `silver.energy_meter_mapping_audit_staging`

Audit trail preserving every candidate source mapping, including excluded ones, with `business_rule_code`, `business_priority`, `canonical_mapping_rank`, `mapping_decision` (`KEEP`/`EXCLUDE`), and `mapping_status`.

### `silver.dim_grid_billing_account_staging`

Billing account dimension. Exposes `breaker_capacity`, `minimal_breaker_capacity`, `maximum_breaker_capacity`, `service_class_fee`, `multiplication_factor`, and configured billing period fields.


## 3. Confirmed Zone Mapping Corrections

| Zone | Issue | Resolution | Status |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------- |
| 03                            | Source device name `ZN.3-PB_child__1_ch3pm` omitted `.1`, mismatching meter label `ZN.3-PB.1_child__1_ch3pm`               | Canonical device name corrected to `ZN.3-PB.1_child__1_ch3pm`     | `TEAM_CONFIRMED_NAME_CORRECTION`                |
| 13                            | Device `ZN.13-PB.1_child__2_ch3pm` legitimately maps to meter `ZN.13-PB.2_child__1_ch3pm` — one panel serving two meters   | Kept as deliberate exception                                      | `TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS` |
| 20                            | Duplicate/crossed mapping: device `ZN.20-PB.1_child__1_ch3pm` incorrectly also mapped to meter `ZN.20-PB.2_child__1_ch3pm` | Duplicate excluded; genuine PB1→PB1 and PB2→PB2 mappings retained | `VALID` (retained rows)                         |

All corrections occur in Silver staging only; Bronze and Silver landing views are unaffected.

**Note:** Zone 13 also appears separately in §10 for an unrelated reason: a kWh data-quality exclusion, not a mapping issue. The two are independent facts about Zone 13.


## 4. Reporting Cadence

- **Nominal/contractual assumption:** 300 seconds, 288 readings/day
- **Most meters:** ~301.5 seconds, ~286–287 readings/day
- **Zone 13 meters:** ~321.17–321.19 seconds, ~269 readings/day. This is a distinct, stable cadence, intentionally not normalized, since it reflects genuine device behavior

Reading timestamps carry real sub-second precision (e.g. `00:04:31.016`) and are never rounded or bucketed. Gaps in reporting appear as genuinely absent rows.


## 5. `silver.fact_energy_readings_staging`

The central analytical fact. **Grain:** one canonical meter × one telemetry timestamp. Pivots the long-format telemetry stream (`silver.telemetries_landing`, joined to `telemetries_dictionaries_landing` and `dim_energy_meter_staging`) into named columns.

32 telemetry keys across 9 classification groups:

| Category | Keys | Notes |
| ------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| Voltage (Line-to-Line)    | `V1,V2,V3,Va` → `voltage_line_1_v...average_v`                         | ~380–420V typical                                                                                            |
| Voltage (Line-to-Neutral) | `Vn1,Vn2,Vn3,Vna` → `voltage_neutral_1_v...average_v`                  | ~215–245V typical                                                                                            |
| Current                   | `Amp1,Amp2,Amp3,Ampa` → `current_phase_1_a...average_a`                |                                                                                                               |
| Frequency                 | `Hz` → `frequency_hz`                                                  |                                                                                                               |
| Power Factor              | `PF1,PF2,PF3,PFa` → `power_factor_phase_1...average`                   |                                                                                                               |
| Active Power              | `kW1,kW2,kW3,TkW` → `active_power_phase_1_kw...total_kw`               | Instantaneous, not cumulative                                                                                 |
| Apparent Power            | `kVA1,kVA2,kVA3,TkVA` → `apparent_power_phase_1_kva...total_kva`       |                                                                                                               |
| Reactive Power            | `kVAr1,kVAr2,kVAr3,TkVAr` → `reactive_power_phase_1_kvar...total_kvar` | Any sign allowed (leading/lagging)                                                                            |
| Accumulated Energy        | `kWh, kVAh, kVArh` → `*_energy_cumulative_*`                           | Cumulative counters — never differenced in this view (a downstream table does perform differencing — see §10) |

Also includes `date_key`, `time_key`, `reading_timestamp_utc`, `reading_timestamp_saudi`/`reading_date_saudi` (Asia/Riyadh, Friday–Saturday weekend), `source_measurement_row_count`, `populated_measurement_count`, `duplicate_measurement_row_count`, and derived phase-imbalance diagnostics.

### 5.1 Confirmed unpopulated measurements (facility-wide)

Eight of the 32 keys were **not observed for any of the 31 meters in the validated Bronze sample/window**: `Va`, `Vna`, `Ampa`, and the entire apparent-power/apparent-energy family (`kVA1`, `kVA2`, `kVA3`, `TkVA`, `kVAh`).

Verified at the Bronze level: a distinct-key count per meter in the validated sample/window returned exactly 24 keys for every meter, with none reporting more. This is consistent with fleet-wide meter hardware/firmware behavior rather than a coverage problem in specific meters. The downstream columns are `NULL` throughout the analytical layer and are excluded from classification (§7.2). The check has not yet been extended across the full 19-month Bronze history, so this wording deliberately does not claim that the keys were never transmitted at any point.


## 6. Reference: Bronze source structure

`bronze.telemetries` is long-format: one row per individual measurement, not per reading:

| Column | Type | Description |
| ------------------------------------ | ------- | ------------------------------------------------------ |
| `device_id`                          | uuid    | Matches `energy_meter_key` (§2)                        |
| `key_id`                             | bigint  | Which measurement this row holds                       |
| `timestamp`                          | bigint  | Epoch milliseconds                                     |
| `bool`, `dbl`, `json`, `long`, `str` | various | Typed value columns; electrical measurements use `dbl` |

One "reading packet" is therefore a unique `(device_id, timestamp)` pair spanning ~24 rows. Silver's pivot reshapes these into one wide row per packet.


## 7. Classification System

### 7.1 Severity tiers

Five tiers, in increasing severity:

`Acceptable` < `Review Required` < `Problematic` < `Critical` < `Invalid`

**Evaluation order: first match wins:**

`Invalid` → `Critical` → `Review Required` → `Problematic` → `Acceptable`

Current also has two diagnostic outcomes outside this five-tier ladder: `Major Issue` and `Major Problem` (§7.3). They identify current/active-power consistency mismatches and do not elevate `overall_status`.

This order matters: several tiers have mathematically overlapping conditions, and the order resolves which label applies. `Invalid` is checked first so a corrupt or missing reading is never mislabeled as merely out-of-range. `Review Required` is checked before `Problematic` so the narrower, less severe band is carved out of the wider one rather than being swallowed by it.

`silver.status_rank(status)` currently recognizes `Acceptable`=1, `Review Required`=2, `Anomaly`=3, `Problematic`=4, `Critical`=5, and `Invalid`=6 (0 for unrecognized text). The current v2 classifiers documented below do not emit `Anomaly`, but the ranking utility retains support for that label. `silver.worst_status(VARIADIC statuses)` filters `NULL` inputs before ranking and returns the highest-ranked remaining status; if every input is `NULL`, it returns `NULL`.

### 7.2 What is classified, and what is not

**Classified:** Voltage (Line-to-Line and Line-to-Neutral, phases 1–3), Current (phases 1–3), Frequency, Power Factor (phases 1–3 and average), Accumulated active energy (`kWh`).

**Not classified:**

| Category | Reason |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Active Power (`kW1-3`, `TkW`)       | Project decision — no classification required                                                                                                                          |
| Apparent Power (`kVA1-3`, `TkVA`)   | Project decision; also never populated (§5.1)                                                                                                                          |
| Reactive Power (`kVAr1-3`, `TkVAr`) | Project decision — no alarms set, both leading and lagging PF are valid                                                                                                |
| Accumulated `kVAh`, `kVArh`         | Belong to the unclassified apparent/reactive families                                                                                                                  |
| `Va`, `Vna`, `Ampa`                 | Never populated by any meter (§5.1) — classifying an always-`NULL` value would make `overall_status` permanently `Invalid` for reasons unrelated to any real condition |

Raw measured values for all of the above remain fully available throughout the pipeline. Only their *status evaluation* is omitted.

### 7.3 Current: authoritative production logic

Current is the only classified measurement whose threshold depends on the individual meter's circuit-breaker rating. `silver.dim_meter_cb_rating` stores one `cb_max_rating_a` value per canonical meter.

**Authoritative production call:** the live `silver.fact_energy_readings_flagged` view calls the three-argument overload:

```sql
silver.classify_current_v2(current_value, cb_max_rating_a, same_phase_active_power_kw)
```

A separate two-argument overload, `classify_current_v2(value, cb_max)`, also exists in the database, but the current flagged analytical view does **not** call it. The three-argument overload is therefore the production rule for `status_amp1`, `status_amp2`, and `status_amp3`.

Given breaker rating `CB`:

```text
margin = 0.15 × CB
third  = margin ÷ 3
```

The production function evaluates in this exact order:

| Order | Condition | Result |
|---:|---|---|
| 1 | current or breaker rating is `NULL` | `Invalid` |
| 2 | current `< 0` | `Invalid` |
| 3 | current `> CB` | `Critical` |
| 4 | current `> CB − third` | `Problematic` |
| 5 | current `> CB − margin` | `Review Required` |
| 6 | current `< margin` and current = 0 and same-phase kW = 0 | `Acceptable` |
| 7 | current `< margin` and current > 0 and same-phase kW = 0 | `Major Problem` |
| 8 | current `< margin` and current = 0 and same-phase kW <> 0 | `Major Issue` |
| 9 | remaining lower-fringe cases | `Acceptable` |
| 10 | remaining middle-range cases | `Acceptable` |

**Important scope of the current/power consistency check:** `Major Issue` / `Major Problem` are evaluated only inside the lower fringe (`current < 15% of CB`). They are not global comparisons applied at every current magnitude.

**Zero semantics:** the production function uses literal numeric comparisons (`= 0`, `<> 0`, `> 0`). No epsilon/tolerance band is applied. If `phase_kw` is `NULL`, none of the equality/inequality branches against zero evaluate true, so the lower-fringe fallback is `Acceptable`.

**Boundary behavior from the live function:**
- exactly `CB` → `Problematic` (only `> CB` is `Critical`)
- exactly `CB − third` → `Review Required` (the `Problematic` test is strict `>`)
- exactly `CB − margin` → `Acceptable` (the `Review Required` test is strict `>`)
- exactly `margin` → `Acceptable`
- current `< 0` → `Invalid`, not `Critical`

The validated facility results show breaker-proximity statuses only on Phase 1 of `ZN.1-PB.2` (179 `Review Required`, 26 `Problematic`, 9 `Critical`). The much larger current finding set comes from `Major Issue` / `Major Problem` lower-fringe consistency outcomes.

### 7.4 Function reference

All functions live in schema `silver`.

| Function | Signature | Bands |
| -------------------------------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `classify_voltage_line_v2`       | `(value)`             | Min/Max 360–440V · Acceptable 380–420V · Review Required 371.2–380 and 420–428.8 (2% of Max either side) · Problematic 360–371.2 and 428.8–440 · Critical outside 360–440 · Invalid on `NULL`                                                        |
| `classify_voltage_neutral_v2`    | `(value)`             | Min/Max 207–253V · Acceptable 215–245V · Review Required 209.94–215 and 245–250.06 (2% of Max) · Problematic 207–209.94 and 250.06–253 · Critical outside 207–253 · Invalid on `NULL`                                                                |
| `classify_current_v2` | `(value, cb_max)` | Two-argument overload present in the live database; applies breaker-relative low/high bands but is **not called by the current `fact_energy_readings_flagged` view**. |
| `classify_current_v2` | `(value, cb_max, phase_kw)` | **Production overload used by `fact_energy_readings_flagged`**. Applies upper breaker-margin rules plus lower-fringe same-phase current/kW consistency logic; see §7.3. |
| `classify_frequency_v2`          | `(value)`             | Min/Max 59–61Hz · Acceptable 59.3–60.5Hz · Problematic 59–59.3 and 60.5–61 · Critical outside 59–61 · Invalid on `NULL`. No Review Required tier for this metric.                                                                                    |
| `classify_power_factor_v2`       | `(value)`             | Min/Max 0.6–1 · Acceptable 0.8–1 · Review Required 0.78–0.8 · Problematic 0.6–0.78 · Critical `< 0.6` or `> 1` · Invalid on `NULL`. Acceptable Max equals Max, so there is no upper Review Required or Problematic band.                             |
| `classify_accumulated_energy_v2` | `(value, prev_value)` | `kWh` only. `Invalid` if the reading is lower than that meter's previous reading — a cumulative counter must never decrease. `Acceptable` if it increased or stayed flat, including the first-ever reading for a meter (nothing to compare against). |

**Accumulated energy: how the comparison works.** `classify_accumulated_energy_v2` is the only classifier requiring a previous value. `silver.fact_energy_readings_flagged` supplies it via `LAG(active_energy_cumulative_kwh) OVER (PARTITION BY energy_meter_key ORDER BY reading_timestamp_utc)`. The `PARTITION BY` is essential: each meter is compared only against its own prior reading, never against a different meter's, regardless of how rows are physically ordered.

Each meter increments its `kWh` counter by its own fixed step (e.g. 0.4 on one meter, 0.5 on another), and the step size varies across the fleet. Because per-meter step values are not yet catalogued, the current check validates direction only; the counter must not go backward. A future refinement could add step-size validation (flagging an increment that is neither zero nor that meter's expected step) once those values are collected.


## 8. `silver.fact_energy_readings_flagged`

Row-level status classification view at the raw reading grain.

**Columns:** identity fields (`energy_meter_key`, `source_energy_meter_id`, `facility_key`, `zone_key`, `grid_billing_account_key`, `date_key`, `time_key`, `source_timestamp_ms`, `reading_timestamp_utc`, `reading_timestamp_saudi`, `reading_date_saudi`), then:

`status_vn1`, `status_vn2`, `status_vn3`, `status_v1`, `status_v2`, `status_v3`, `status_amp1`, `status_amp2`, `status_amp3`, `status_hz`, `status_pf1`, `status_pf2`, `status_pf3`, `status_pfa`, `status_kwh`, and `overall_status`.

This view is **status-only**; it does not carry the underlying measured values. It joins `silver.dim_meter_cb_rating` to obtain each meter's breaker rating for current classification (§7.3), evaluates same-phase current/active-power consistency for `status_amp1`/`status_amp2`/`status_amp3`, and computes `LAG()` for accumulated energy's decrement check (§7.4).

**A note on `overall_status`:** the live view calls `worst_status()` across **12 inputs only**: the six voltage statuses, frequency, PF1/PF2/PF3/PFa, and kWh. `status_amp1`, `status_amp2`, and `status_amp3` are excluded entirely from the `overall_status` array. Therefore **no current status**, including `Major Issue`, `Major Problem`, `Review Required`, `Problematic`, `Critical`, or `Invalid`, can change `overall_status`. Current must be analyzed through its individual phase status columns.


## 9. `silver.fact_energy_readings_snapshot`

A stored table (not a view) joining measured values to their quality status; the analytical table Gold serves.

**Built from:** `silver.fact_energy_readings_staging` (measured values) `JOIN silver.fact_energy_readings_flagged` (status) on `energy_meter_key` + `reading_timestamp_utc`.

**Primary key:** `(energy_meter_key, reading_timestamp_utc)`

**Why a stored table rather than a view:** `fact_energy_readings_flagged` recomputes the full Bronze pivot, classification, and window functions on every query. Materializing the result once means Power BI reads a plain indexed table instead of triggering that recomputation on every refresh.

**Refresh method:** full rebuild (`DROP TABLE ... CASCADE` then reload), not incremental. Accumulated energy's decrement check depends on each reading's true predecessor; an incremental filter would compare the first new reading against the wrong prior value at the boundary. A full rebuild avoids that risk entirely, at the cost of reprocessing the full history each time (~1–1.5 hours at current volume).

**Important:** the `CASCADE` also drops `gold.energy_raw`, which must be explicitly recreated after every rebuild:

```sql
CREATE OR REPLACE VIEW gold.energy_raw AS
SELECT * FROM silver.fact_energy_readings_snapshot;

```

**Current volume:** 4,535,918 rows, cross-validated by five independent methods: Bronze distinct-packet counts per meter (all 31 matching exactly), direct row counts against both source views, per-meter reading counts, status-distribution totals, and duplicate/null-identity checks (zero of each).

Consumption (differenced `kWh`) is calculated downstream of this table in the implemented and validated `silver.fact_energy_consumption_validated` table; see §10.


## 10. `silver.fact_energy_consumption_validated` (Consumption Calculation)

**Status: implemented, validated, exposed through Gold, and used by Power BI.**

**Purpose:** `classify_accumulated_energy_v2` (§7.4) checks only whether the cumulative `kWh` counter decreased. `silver.fact_energy_consumption_validated` converts the cumulative register into interval-level consumption while preserving the raw source values in `silver.fact_energy_readings_snapshot`.

**Source:** `silver.fact_energy_readings_snapshot`, joined to `silver.dim_energy_meter_staging` for the canonical `meter_label`.

### 10.1 Implemented validation rules

The current implementation applies these rules in sequence:

- **Zone 13 exclusion:** `ZN.13-PB.1` and `ZN.13-PB.2` are excluded from validated consumption. This is a kWh data-quality/business-rule exclusion and is independent of the Zone 13 mapping exception in §3.
- **`ZN.1-PB.1` startup exclusion:** readings before `2024-12-10 17:16:15.655 UTC` are ignored; the approved valid baseline begins at `46.5 kWh`.
- **`ZN.4-PB.1` startup exclusion:** readings before `2024-12-10 21:46:39.010 UTC` are ignored; the approved valid baseline begins at `150.4 kWh`.
- **Isolated low bad reading:** when a reading drops below the prior value and the following reading returns to or above the prior level, the isolated low point is ignored and consumption bridges between the surrounding valid readings.
- **Isolated high spike:** when a reading spikes above both its prior and following values and the following value recovers to or above the prior level, the spike is ignored and consumption bridges between the surrounding valid readings.
- **Normal increase:** validated consumption is the current valid cumulative `kWh` minus the previous valid cumulative `kWh`.
- **Flat counter:** contributes `0 kWh`.
- **Remaining decrement after validation:** not counted as validated consumption.
- **Long gap:** a valid-to-valid interval of at least 15 minutes is labeled `LONG_GAP`. The cumulative increase across that gap is intentionally **included** in validated consumption under the approved business rule.

**Rule precedence:** meter-level exclusions and startup cutoffs are applied first; isolated low/high bad points are removed before the valid-reading sequence is differenced; the validated delta is then evaluated. If the remaining valid-to-valid delta is negative, it is not counted as consumption. Only a non-negative valid interval is subsequently labeled `LONG_GAP` when its elapsed time is at least 15 minutes; otherwise it is `NORMAL_INTERVAL`. Therefore an unresolved decrement takes precedence over the long-gap label for consumption purposes.

Long gaps therefore affect **time attribution**, not the validity of the total: the accumulated increase is assigned to the first valid reading after telemetry resumes.

### 10.2 Key reporting columns

Key columns used by the reporting layer include:

- `energy_meter_key`
- `meter_label`
- `reading_timestamp_utc`
- `reading_date_saudi`
- `active_energy_cumulative_kwh`
- `validated_kwh_consumption`
- `interval_quality`

Observed `interval_quality` values in the validated dataset are `FIRST_VALID_READING`, `IGNORED_READING`, `LONG_GAP`, and `NORMAL_INTERVAL`.

### 10.3 Validated volume and reconciliation

| Metric | Validated result |
|---|---:|
| Rows | 4,260,849 |
| Included meters | 29 |
| Total validated consumption | 2,020,697.5 kWh |
| `FIRST_VALID_READING` rows | 29 |
| `IGNORED_READING` rows | 28 |
| `LONG_GAP` rows | 875 |
| `LONG_GAP` consumption | 354,242.5 kWh |
| `NORMAL_INTERVAL` rows | 4,259,917 |
| `NORMAL_INTERVAL` consumption | 1,666,455.0 kWh |

All 29 included meters were reconciled individually against the approved cumulative-register baseline and final register value. Every meter returned a reconciliation difference of exactly `0.000000`.

**Validation result:** no residual reset-induced overcount or undercount was observed in the validated dataset. This reconciliation is the empirical check that the implemented isolated-point logic is sufficient for the 29 included meters in the assessed history; a more elaborate high-water-mark/reset model is therefore not required for the current validated dataset.

The Silver table and `gold.energy_consumption_validated` were also cross-checked directly and match exactly on row count, meter count, and total validated consumption. The underlying PostgreSQL double-precision sum is `2,020,697.4999726608 kWh`; reporting documentation rounds this to `2,020,697.5 kWh` to avoid implying false measurement precision.

### 10.4 Gold / Power BI integration

`gold.energy_consumption_validated` exposes this table to Power BI.

Power BI uses:

```dax
Total Validated Consumption kWh =
SUM('gold energy_consumption_validated'[validated_kwh_consumption])
```

The consumption fact has an active many-to-one relationship to `gold.meter` on `energy_meter_key`. Direct relationships from the consumption fact to zone, facility, and billing account remain inactive to avoid ambiguous duplicate filter paths, and there is no direct fact-to-fact relationship to `gold.energy_raw`.

Monthly reporting uses a Power BI `Reading Month UTC` calculated column derived from `reading_timestamp_utc`. Weekday/weekend reporting uses `reading_date_saudi`, with Friday and Saturday classified as weekend.

## 11. Gold Reporting Objects

### 11.1 `gold.energy_raw`

The primary raw-reading Gold fact. A plain passthrough view over `silver.fact_energy_readings_snapshot`; no logic, no filtering, no aggregation.

**Power BI model requirements:**

1. **`reading_date`** **calculated column:** `reading_timestamp_utc` carries a full timestamp with sub-second precision, while `gold.date[calendar_date]` holds date-only values. These cannot relate directly, so a date-only column is derived: 
   ```dax
   reading_date = DATE(YEAR('gold energy_raw'[reading_timestamp_utc]), MONTH('gold energy_raw'[reading_timestamp_utc]), DAY('gold energy_raw'[reading_timestamp_utc]))

   ```
2. **`meter_label`** **calculated column:** surfaces the readable meter name (e.g. `ZN.16-PB_child__1_ch3pm`) alongside raw readings: 
   ```dax
   meter_label = RELATED('gold meter'[meter_label])

   ```
3. **Two active relationships:** `energy_meter_key` → `gold.meter` and `reading_date` → `gold.date[calendar_date]`, both Many-to-one, Single cross-filter direction
4. **Relationships that must stay inactive:** `facility_key` → `gold.facility`, `zone_key` → `gold.zone`, `grid_billing_account_key` → `gold.billing_account`, `energy_meter_key` → `gold.quality_summary`. The meter-hub relationship already reaches zone, facility, and billing account through `gold.meter`'s own hierarchy; activating these direct links creates an ambiguous duplicate path that Power BI rejects. When activating the meter relationship, deactivate these first; Power BI enforces this ordering.

### 11.2 `gold.energy_consumption_validated`

Gold view over `silver.fact_energy_consumption_validated` (§10). This is the reporting source for validated energy-consumption totals, per-meter consumption, monthly consumption, and weekday/weekend consumption analysis.

**Current validated volume:** 4,260,849 rows across 29 included meters, totaling 2,020,697.5 kWh.

**Power BI relationship:** active many-to-one from `energy_meter_key` to `gold.meter[energy_meter_key]`, single direction. Direct zone/facility/billing relationships remain inactive to avoid ambiguous paths. There is no direct relationship to `gold.energy_raw`.

### 11.3 `gold.energy_reading_gaps`

Physical Gold reporting table for telemetry coverage gaps.

**Definition:** for each meter, consecutive readings are ordered by `reading_timestamp_utc`; an interval is recorded as a gap when the elapsed time is at least 900 seconds (15 minutes).

Key reporting fields include `meter_label`, the previous and current reading timestamps, `gap_minutes`, and `gap_days`.

**Refresh / staleness behavior:** PostgreSQL metadata confirms this object is a physical table, not a view. The catalog extract does not contain its build procedure, scheduler, or refresh ownership, so those operational details remain **not formally documented**. Because it stores derived gap rows rather than evaluating a live view, it must be refreshed when the underlying reading history changes if the gap analysis is to remain current.

The largest validated gap is `ZN.17-PB`: `2025-05-18 04:22:28.966 UTC` → `2025-12-05 12:55:30.761 UTC`, equal to 289,953.03 minutes / 201.36 days.

## 12. Billing Objects (Not Yet Integrated)

Present in the schema but not yet connected to consumption analysis, pending real billing data and criteria:

- `silver.grid_billing_accounts_landing`, `grid_billing_accounts_service_classes_landing`, `grid_billing_accounts_types_landing`
- `silver.tariff_categories_landing`: a candidate source not yet incorporated into the star schema
- `silver.energy_bills_tracking_landing`, `silver.fact_energy_bill_staging`: a source-aligned bill tracking/comparison fact (grain: one tracked bill per billing period per grid billing account), exposing billed versus system-estimated consumption/cost and variances

Not a tariff-calculation engine; no verified tier, time-of-use, VAT, or demand-charge formula exists yet.


## 13. Out of Scope

All water-related tables (`water_bill*`, `water_grid_*`, `water_tank*`, `water_meter_units_landing`) are excluded from this project's analysis per project scope.


## 14. Governance & Documentation Status

This dictionary is **informed by common enterprise metadata-management practices** (including concepts commonly associated with DAMA-DMBOK and ISO/IEC 11179), but it does **not** claim formal compliance or certification against either framework.

Only governance facts established in the project evidence are populated below. Organizational assignments or policies that have not been formally confirmed are deliberately shown as `TBD / not formally defined` rather than inferred.

| Governance item | Current documented state |
|---|---|
| Data domain | Electrical Energy Telemetry |
| Project scope | SADINhub Energy Intelligence & Predictive Analytics Platform; water data excluded |
| System of record for raw telemetry | PostgreSQL Bronze layer / source-restored telemetry |
| Analytical platform | PostgreSQL 18 + Power BI |
| Downstream consumers | Power BI dashboard; analytics/assessment workflows |
| Data owner | TBD / not formally assigned in project evidence |
| Data steward | TBD / not formally assigned in project evidence |
| Technical owner | TBD / not formally assigned in project evidence |
| Refresh SLA | TBD / not formally defined |
| Retention policy | TBD / not formally defined |
| Security / sensitivity classification | TBD / not formally assessed |
| Formal approval status | Project technical documentation; formal enterprise approval not evidenced |
| Technical validation status | Validated for the documented assessment scope |
| Metadata extraction date | 2026-08-24 |
| Catalog identity | `(schema_name, object_name, column_name)` |


## 15. Technical Object Registry

Object type and size below come directly from the live PostgreSQL catalog at extraction time. View size is shown as `0 bytes` because the view itself stores no rows.

| Schema | Object | Type | Catalog size | Comment / purpose |
| --- | --- | --- | --- | --- |
| bronze | energy_meters | table | 144 kB |  |
| bronze | telemetries | table | 12 GB |  |
| bronze | telemetries_dictionaries | table | 40 kB |  |
| gold | billing_account | view | 0 bytes |  |
| gold | date | view | 0 bytes |  |
| gold | energy_bill | view | 0 bytes |  |
| gold | energy_consumption_validated | view | 0 bytes |  |
| gold | energy_raw | view | 0 bytes |  |
| gold | energy_reading_gaps | table | 136 kB |  |
| gold | facility | view | 0 bytes |  |
| gold | mapping_audit | view | 0 bytes |  |
| gold | meter | view | 0 bytes |  |
| gold | quality_summary | view | 0 bytes |  |
| gold | zone | view | 0 bytes |  |
| silver | dim_energy_meter_staging | view | 0 bytes | Canonical energy-meter/device dimension. One row per reporting device; duplicate source mappings remain flagged. |
| silver | dim_grid_billing_account_staging | view | 0 bytes | Grid billing-account dimension enriched with account type and service class. |
| silver | dim_meter_cb_rating | table | 24 kB |  |
| silver | energy_meter_mapping_audit_staging | view | 0 bytes |  |
| silver | fact_energy_consumption_validated | table | 1221 MB |  |
| silver | fact_energy_readings_flagged | view | 0 bytes |  |
| silver | fact_energy_readings_snapshot | table | 2287 MB |  |
| silver | fact_energy_readings_staging | view | 0 bytes | Main project fact. One energy meter per telemetry timestamp with electrical measures pivoted into business-readable columns. |

## 16. Formal Data-Quality Rule Registry

These rule IDs organize logic that already exists in the pipeline; they do not create new thresholds or change the live database behavior.

| Rule ID | Rule name | Scope | Authoritative logic / definition | Primary outputs | Status |
| --- | --- | --- | --- | --- | --- |
| DQ-MAP-001 | Canonical meter mapping | Meter/device mapping | Canonical ranking plus confirmed Zone 03/13/20 business rules. | Mapping/audit fields | Implemented |
| DQ-PACKET-001 | Telemetry packet completeness diagnostics | Reading packet | Counts source rows, distinct populated keys, and duplicate measurement rows per meter×timestamp. | source_measurement_row_count, populated_measurement_count, duplicate_measurement_row_count | Implemented diagnostic |
| DQ-VL-001 | Line voltage classification | V1/V2/V3 | Critical <360 or >440; Acceptable 380–420; Review 371.2–<380 or >420–428.8; remaining in-range values Problematic; NULL Invalid. | status_v1/status_v2/status_v3 | Implemented |
| DQ-VN-001 | Line-to-neutral voltage classification | Vn1/Vn2/Vn3 | Critical <207 or >253; Acceptable 215–245; Review 209.94–<215 or >245–250.06; remaining in-range values Problematic; NULL Invalid. | status_vn1/status_vn2/status_vn3 | Implemented |
| DQ-FREQ-001 | Frequency classification | Hz | Critical <59 or >61; Acceptable 59.3–60.5; remaining 59–61 values Problematic; NULL Invalid. | status_hz | Implemented |
| DQ-PF-001 | Power-factor classification | PF1/PF2/PF3/PFa | Critical <0.6 or >1; Acceptable 0.8–1; Review 0.78–<0.8; remaining 0.6–<0.78 Problematic; NULL Invalid. | status_pf1/status_pf2/status_pf3/status_pfa | Implemented |
| DQ-CUR-001 | Per-meter current + same-phase power consistency | Amp1/Amp2/Amp3 + kW1/kW2/kW3 + breaker rating | Production 3-argument classifier; exact order and strict boundaries documented in §7.3. | status_amp1/status_amp2/status_amp3 | Implemented |
| DQ-KWH-001 | Cumulative active-energy direction | kWh | Invalid when current cumulative kWh < previous same-meter kWh; first reading and non-decreasing values Acceptable. | status_kwh | Implemented |
| DQ-CONS-001 | Validated interval consumption | Cumulative kWh | Approved exclusions, isolated-point cleaning, valid-to-valid differencing, decrement suppression, and long-gap inclusion. | validated_kwh_consumption, consumption_cleaning_status, interval_quality | Implemented + reconciled |
| DQ-GAP-001 | Telemetry coverage gap | Reading timestamps | Physical gap rows for same-meter elapsed intervals ≥900 seconds (15 minutes). | gap_seconds/minutes/hours/days | Implemented |
| DQ-IMB-CUR-001 | Current imbalance diagnostic | Amp1/Amp2/Amp3 | 3-phase average/spread/imbalance computed when all phases are present and absolute average current >0.1A. | current_* imbalance fields | Implemented diagnostic |
| DQ-IMB-VOLT-001 | Voltage imbalance diagnostic | V1/V2/V3 | 3-phase average/spread/imbalance computed when all phases are present and absolute average voltage >1.0V. | voltage_* imbalance fields | Implemented diagnostic |

### 16.1 Status-ranking utility

The live `silver.status_rank()` function recognizes:

`Acceptable` (1) < `Review Required` (2) < `Anomaly` (3) < `Problematic` (4) < `Critical` (5) < `Invalid` (6).

`Anomaly` remains supported by the ranking utility even though the current v2 classifiers extracted on 2026-08-24 do not emit it. Unrecognized text ranks `0`.

`overall_status` is **not** a rollup of every `status_*` column. The current live view explicitly excludes `status_amp1`, `status_amp2`, and `status_amp3`.


## 17. Data Lineage Registry

| Target object | Primary source(s) | Transformation / lineage |
| --- | --- | --- |
| silver.dim_energy_meter_staging | Silver landing meter/device/unit/type/category views | Joins source metadata, applies Zone 03 name correction, Zone 13 confirmed exception, Zone 20 duplicate exclusion, and canonical ranking. |
| silver.energy_meter_mapping_audit_staging | Silver landing meter/device/unit views | Preserves all candidate mappings and records business rule, rank, KEEP/EXCLUDE decision, and mapping status. |
| silver.dim_grid_billing_account_staging | Silver billing-account/type/service-class landing views | Enriches billing account with type, service class, capacities, fee and billing-period configuration. |
| silver.fact_energy_readings_staging | silver.telemetries_landing + telemetries_dictionaries_landing + dim_energy_meter_staging | Filters the 32 electrical telemetry keys, converts epoch-ms to UTC/Saudi timestamps, pivots long telemetry to one meter×timestamp row, and derives imbalance diagnostics. |
| silver.fact_energy_readings_flagged | fact_energy_readings_staging + dim_meter_cb_rating | Applies voltage/current/frequency/PF/kWh classifiers. kWh uses meter-partitioned LAG. Current uses the 3-argument classifier overload. |
| silver.fact_energy_readings_snapshot | fact_energy_readings_staging + fact_energy_readings_flagged | Stored raw-grain analytical snapshot combining measurements and status columns. |
| silver.fact_energy_consumption_validated | fact_energy_readings_snapshot + dim_energy_meter_staging | Applies approved cumulative-kWh cleaning/differencing rules and interval-quality classification. |
| gold.energy_raw | silver.fact_energy_readings_snapshot | Pass-through reporting view; no additional SQL transformation. |
| gold.energy_consumption_validated | silver.fact_energy_consumption_validated | Pass-through reporting view exposing 15 BI-facing consumption fields. |
| gold.meter | silver.dim_energy_meter_staging | Pass-through reporting dimension. |
| gold.billing_account | silver.dim_grid_billing_account_staging | Pass-through reporting dimension. |
| gold.mapping_audit | silver.energy_meter_mapping_audit_staging | Pass-through reporting audit view. |
| gold.energy_reading_gaps | Consecutive meter readings from analytical reading history | Physical derived table containing intervals ≥15 minutes; exact build/refresh procedure is not captured by the supplied PostgreSQL catalog metadata. |

## 18. Physical Keys, Constraints & Indexes

Views do not carry enforced PostgreSQL primary/foreign-key constraints. The following are the physical constraints confirmed in the extracted object scope; column nullability is recorded separately in §19.

| Object | Constraint type | Constraint name | Definition |
| --- | --- | --- | --- |
| bronze.energy_meters | PRIMARY KEY | energy_meters_pkey | PRIMARY KEY (id) |
| bronze.energy_meters | CHECK | energy_meters_maximum_kwh_check | maximum_kwh > 0 |
| bronze.energy_meters | CHECK | energy_meters_phase_check | phase > 0 |
| bronze.energy_meters | FOREIGN KEY | energy_meters_created_by_fkey | created_by → bronze.users(id) |
| bronze.energy_meters | FOREIGN KEY | energy_meters_device_id_fkey | device_id → bronze.device(id) |
| bronze.energy_meters | FOREIGN KEY | energy_meters_facility_id_fkey | facility_id → bronze.facilities(id) |
| bronze.energy_meters | FOREIGN KEY | energy_meters_grid_billing_account_id_fkey | grid_billing_account_id → bronze.grid_billing_accounts(id) |
| bronze.energy_meters | FOREIGN KEY | energy_meters_parent_id_fkey | parent_id → bronze.energy_meters(id) |
| bronze.energy_meters | FOREIGN KEY | energy_meters_type_id_fkey | type_id → bronze.energy_meters_types(id) |
| bronze.energy_meters | FOREIGN KEY | energy_meters_unit_id_fkey | unit_id → bronze.units(id) |
| bronze.telemetries | PRIMARY KEY | telemetries_pkey | PRIMARY KEY (device_id, key_id, "timestamp") |
| bronze.telemetries_dictionaries | PRIMARY KEY | telemetries_dictionaries_pkey | PRIMARY KEY (id) |
| silver.dim_meter_cb_rating | PRIMARY KEY | dim_meter_cb_rating_pkey | PRIMARY KEY (energy_meter_key) |
| silver.fact_energy_readings_snapshot | PRIMARY KEY | pk_energy_readings_snapshot | PRIMARY KEY (energy_meter_key, reading_timestamp_utc) |

### 18.1 Confirmed indexes

| Object | Index name | Definition |
| --- | --- | --- |
| bronze.energy_meters | energy_meters_pkey | UNIQUE btree(id) |
| bronze.energy_meters | energymeter_created_by | btree(created_by) |
| bronze.energy_meters | energymeter_device_id | btree(device_id) |
| bronze.energy_meters | energymeter_facility_id | btree(facility_id) |
| bronze.energy_meters | energymeter_grid_billing_account_id | btree(grid_billing_account_id) |
| bronze.energy_meters | energymeter_parent_id | btree(parent_id) |
| bronze.energy_meters | energymeter_type_id | btree(type_id) |
| bronze.energy_meters | energymeter_unit_id | btree(unit_id) |
| bronze.telemetries | telemetries_pkey | UNIQUE btree(device_id, key_id, "timestamp") |
| bronze.telemetries_dictionaries | telemetries_dictionaries_pkey | UNIQUE btree(id) |
| bronze.telemetries_dictionaries | telemetrydictionaries_key | UNIQUE btree(key) |
| silver.dim_meter_cb_rating | dim_meter_cb_rating_pkey | UNIQUE btree(energy_meter_key) |
| silver.fact_energy_consumption_validated | idx_consumption_date | btree(reading_date_saudi) |
| silver.fact_energy_consumption_validated | idx_consumption_meter_label | btree(meter_label) |
| silver.fact_energy_consumption_validated | idx_consumption_meter_time | btree(energy_meter_key, reading_timestamp_utc) |
| silver.fact_energy_readings_snapshot | pk_energy_readings_snapshot | UNIQUE btree(energy_meter_key, reading_timestamp_utc) |

**Consumption-table note:** `silver.fact_energy_consumption_validated` has three confirmed non-unique indexes but no primary-key constraint in the extracted metadata. Its `(energy_meter_key, reading_timestamp_utc)` pair is indexed, but the database does not enforce uniqueness on that pair through a PK/UNIQUE constraint in the supplied catalog output.


## 19. Complete Column-Level Catalog

**Catalog key:** `(schema, object, column)`. The same column name may have different grain, nullability, constraints, or semantics in different objects, so column name alone is not treated as a unique identifier.

`Nullable` and PostgreSQL data type come directly from `information_schema.columns`. `Key` and `Indexed` are based on the extracted physical constraints/indexes in scope. Business definitions, units, lineage, and DQ mappings describe the already-documented SADINhub pipeline and do not override the physical database metadata.


### 19.1 `bronze.energy_meters`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | id | uuid | NO | gen_random_uuid() | PK | Yes | — | Id. | Source-system Bronze field; no analytical transformation. | — |
| 2 | facility_id | uuid | NO | — | — | Yes | — | Facility id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 3 | grid_billing_account_id | uuid | NO | — | — | Yes | — | Grid billing account id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 4 | device_id | uuid | NO | — | — | Yes | — | Device id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 5 | phase | integer | NO | — | — | No/Not shown | — | Phase. | Source-system Bronze field; no analytical transformation. | — |
| 6 | parent_id | uuid | YES | — | — | Yes | — | Parent id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 7 | maximum_kwh | integer | NO | — | — | No/Not shown | kWh | Maximum kwh. | Source-system Bronze field; no analytical transformation. | — |
| 8 | type_id | uuid | NO | — | — | Yes | — | Type id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 9 | unit_id | uuid | NO | — | — | Yes | — | Unit id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 10 | active | boolean | NO | true | — | No/Not shown | — | Active. | Source-system Bronze field; no analytical transformation. | — |
| 11 | created_by | uuid | NO | — | — | Yes | — | Created by. | Source-system Bronze field; no analytical transformation. | — |
| 12 | created_on | timestamp with time zone | NO | now() | — | No/Not shown | — | Created on. | Source-system Bronze field; no analytical transformation. | — |
| 13 | meter_sn | character varying | YES | — | — | No/Not shown | — | Meter sn. | Source-system Bronze field; no analytical transformation. | — |
| 14 | meter_label | character varying | YES | — | — | No/Not shown | — | Canonical human-readable meter label. | Source-system Bronze field; no analytical transformation. | — |

### 19.2 `bronze.telemetries`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | device_id | uuid | NO | — | PK | Yes | — | Device id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 2 | key_id | bigint | NO | nextval('bronze.key_id_seq'::regclass) | PK | Yes | — | Key id identifier. | Source-system Bronze field; no analytical transformation. | — |
| 3 | timestamp | bigint | NO | — | PK | Yes | — | Timestamp. | Source-system Bronze field; no analytical transformation. | — |
| 4 | bool | boolean | YES | — | — | No/Not shown | — | Bool. | Source-system Bronze field; no analytical transformation. | — |
| 5 | dbl | double precision | YES | — | — | No/Not shown | — | Dbl. | Source-system Bronze field; no analytical transformation. | — |
| 6 | json | json | YES | — | — | No/Not shown | — | Json. | Source-system Bronze field; no analytical transformation. | — |
| 7 | long | bigint | YES | — | — | No/Not shown | — | Long. | Source-system Bronze field; no analytical transformation. | — |
| 8 | str | character varying | YES | — | — | No/Not shown | — | Str. | Source-system Bronze field; no analytical transformation. | — |

### 19.3 `bronze.telemetries_dictionaries`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | id | bigint | NO | nextval('bronze.id_seq'::regclass) | PK | Yes | — | Id. | Source-system Bronze field; no analytical transformation. | — |
| 2 | key | character varying | NO | — | — | Yes | — | Key. | Source-system Bronze field; no analytical transformation. | — |
| 3 | created_on | timestamp without time zone | NO | now() | — | No/Not shown | — | Created on. | Source-system Bronze field; no analytical transformation. | — |

### 19.4 `gold.billing_account`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Pass-through from `silver.dim_grid_billing_account_staging.grid_billing_account_key`. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.dim_grid_billing_account_staging.facility_key`. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.dim_grid_billing_account_staging.zone_key`. | — |
| 4 | account_label | text | YES | — | — | No/Not shown | — | Account label. | Pass-through from `silver.dim_grid_billing_account_staging.account_label`. | — |
| 5 | account_number | text | YES | — | — | No/Not shown | — | Account number. | Pass-through from `silver.dim_grid_billing_account_staging.account_number`. | — |
| 6 | meter_serial_number | text | YES | — | — | No/Not shown | — | Meter serial number. | Pass-through from `silver.dim_grid_billing_account_staging.meter_serial_number`. | — |
| 7 | account_type_key | uuid | YES | — | — | No/Not shown | — | Account type key identifier. | Pass-through from `silver.dim_grid_billing_account_staging.account_type_key`. | — |
| 8 | account_type_name | text | YES | — | — | No/Not shown | — | Account type name. | Pass-through from `silver.dim_grid_billing_account_staging.account_type_name`. | — |
| 9 | service_class_key | uuid | YES | — | — | No/Not shown | — | Service class key identifier. | Pass-through from `silver.dim_grid_billing_account_staging.service_class_key`. | — |
| 10 | service_class_name | text | YES | — | — | No/Not shown | — | Service class name. | Pass-through from `silver.dim_grid_billing_account_staging.service_class_name`. | — |
| 11 | breaker_capacity | integer | YES | — | — | No/Not shown | — | Breaker capacity. | Pass-through from `silver.dim_grid_billing_account_staging.breaker_capacity`. | — |
| 12 | minimal_breaker_capacity | integer | YES | — | — | No/Not shown | — | Minimal breaker capacity. | Pass-through from `silver.dim_grid_billing_account_staging.minimal_breaker_capacity`. | — |
| 13 | maximum_breaker_capacity | integer | YES | — | — | No/Not shown | — | Maximum breaker capacity. | Pass-through from `silver.dim_grid_billing_account_staging.maximum_breaker_capacity`. | — |
| 14 | service_class_fee | integer | YES | — | — | No/Not shown | — | Service class fee. | Pass-through from `silver.dim_grid_billing_account_staging.service_class_fee`. | — |
| 15 | multiplication_factor | integer | YES | — | — | No/Not shown | — | Multiplication factor. | Pass-through from `silver.dim_grid_billing_account_staging.multiplication_factor`. | — |
| 16 | start_period | timestamp with time zone | YES | — | — | No/Not shown | — | Start period. | Pass-through from `silver.dim_grid_billing_account_staging.start_period`. | — |
| 17 | end_period | timestamp with time zone | YES | — | — | No/Not shown | — | End period. | Pass-through from `silver.dim_grid_billing_account_staging.end_period`. | — |
| 18 | configured_billing_days | integer | YES | — | — | No/Not shown | — | Configured billing days. | Pass-through from `silver.dim_grid_billing_account_staging.configured_billing_days`. | — |
| 19 | source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Source created at. | Pass-through from `silver.dim_grid_billing_account_staging.source_created_at`. | — |

### 19.5 `gold.date`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | date_key | integer | YES | — | — | No/Not shown | — | Calendar date surrogate/key in YYYYMMDD-style integer form. | Pass-through from `silver.dim_date_staging.date_key`. | — |
| 2 | calendar_date | date | YES | — | — | No/Not shown | — | Calendar date. | Pass-through from `silver.dim_date_staging.calendar_date`. | — |
| 3 | calendar_year | integer | YES | — | — | No/Not shown | — | Calendar year. | Pass-through from `silver.dim_date_staging.calendar_year`. | — |
| 4 | calendar_quarter | integer | YES | — | — | No/Not shown | — | Calendar quarter. | Pass-through from `silver.dim_date_staging.calendar_quarter`. | — |
| 5 | month_number | integer | YES | — | — | No/Not shown | — | Month number. | Pass-through from `silver.dim_date_staging.month_number`. | — |
| 6 | month_name | text | YES | — | — | No/Not shown | — | Month name. | Pass-through from `silver.dim_date_staging.month_name`. | — |
| 7 | month_short_name | text | YES | — | — | No/Not shown | — | Month short name. | Pass-through from `silver.dim_date_staging.month_short_name`. | — |
| 8 | week_of_year | integer | YES | — | — | No/Not shown | — | Week of year. | Pass-through from `silver.dim_date_staging.week_of_year`. | — |
| 9 | iso_day_of_week | integer | YES | — | — | No/Not shown | — | Iso day of week. | Pass-through from `silver.dim_date_staging.iso_day_of_week`. | — |
| 10 | day_name | text | YES | — | — | No/Not shown | — | Day name. | Pass-through from `silver.dim_date_staging.day_name`. | — |
| 11 | day_short_name | text | YES | — | — | No/Not shown | — | Day short name. | Pass-through from `silver.dim_date_staging.day_short_name`. | — |
| 12 | day_of_month | integer | YES | — | — | No/Not shown | — | Day of month. | Pass-through from `silver.dim_date_staging.day_of_month`. | — |
| 13 | day_of_year | integer | YES | — | — | No/Not shown | — | Day of year. | Pass-through from `silver.dim_date_staging.day_of_year`. | — |
| 14 | is_weekend | boolean | YES | — | — | No/Not shown | — | Is weekend flag. | Pass-through from `silver.dim_date_staging.is_weekend`. | — |
| 15 | month_start_date | date | YES | — | — | No/Not shown | — | Month start date. | Pass-through from `silver.dim_date_staging.month_start_date`. | — |
| 16 | month_end_date | date | YES | — | — | No/Not shown | — | Month end date. | Pass-through from `silver.dim_date_staging.month_end_date`. | — |
| 17 | quarter_start_date | date | YES | — | — | No/Not shown | — | Quarter start date. | Pass-through from `silver.dim_date_staging.quarter_start_date`. | — |
| 18 | year_start_date | date | YES | — | — | No/Not shown | — | Year start date. | Pass-through from `silver.dim_date_staging.year_start_date`. | — |

### 19.6 `gold.energy_bill`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_bill_key | uuid | YES | — | — | No/Not shown | — | Energy bill key identifier. | Pass-through from `silver.fact_energy_bill_staging.energy_bill_key`. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.fact_energy_bill_staging.facility_key`. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.fact_energy_bill_staging.zone_key`. | — |
| 4 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Pass-through from `silver.fact_energy_bill_staging.grid_billing_account_key`. | — |
| 5 | start_date_key | integer | YES | — | — | No/Not shown | — | Start date key identifier. | Pass-through from `silver.fact_energy_bill_staging.start_date_key`. | — |
| 6 | end_date_key | integer | YES | — | — | No/Not shown | — | End date key identifier. | Pass-through from `silver.fact_energy_bill_staging.end_date_key`. | — |
| 7 | start_period | timestamp with time zone | YES | — | — | No/Not shown | — | Start period. | Pass-through from `silver.fact_energy_bill_staging.start_period`. | — |
| 8 | end_period | timestamp with time zone | YES | — | — | No/Not shown | — | End period. | Pass-through from `silver.fact_energy_bill_staging.end_period`. | — |
| 9 | calculated_billing_days | integer | YES | — | — | No/Not shown | — | Calculated billing days. | Pass-through from `silver.fact_energy_bill_staging.calculated_billing_days`. | — |
| 10 | invoice_number | text | YES | — | — | No/Not shown | — | Invoice number. | Pass-through from `silver.fact_energy_bill_staging.invoice_number`. | — |
| 11 | beginning_reading | numeric | YES | — | — | No/Not shown | — | Beginning reading. | Pass-through from `silver.fact_energy_bill_staging.beginning_reading`. | — |
| 12 | ending_reading | numeric | YES | — | — | No/Not shown | — | Ending reading. | Pass-through from `silver.fact_energy_bill_staging.ending_reading`. | — |
| 13 | billed_consumption_kwh | numeric | YES | — | — | No/Not shown | kWh | Billed consumption kwh. | Pass-through from `silver.fact_energy_bill_staging.billed_consumption_kwh`. | — |
| 14 | billed_cost | numeric | YES | — | — | No/Not shown | — | Billed cost. | Pass-through from `silver.fact_energy_bill_staging.billed_cost`. | — |
| 15 | system_beginning_reading | numeric | YES | — | — | No/Not shown | — | System beginning reading. | Pass-through from `silver.fact_energy_bill_staging.system_beginning_reading`. | — |
| 16 | system_ending_reading | numeric | YES | — | — | No/Not shown | — | System ending reading. | Pass-through from `silver.fact_energy_bill_staging.system_ending_reading`. | — |
| 17 | system_consumption_kwh | numeric | YES | — | — | No/Not shown | kWh | System consumption kwh. | Pass-through from `silver.fact_energy_bill_staging.system_consumption_kwh`. | — |
| 18 | system_estimated_cost | numeric | YES | — | — | No/Not shown | — | System estimated cost. | Pass-through from `silver.fact_energy_bill_staging.system_estimated_cost`. | — |
| 19 | consumption_variance_kwh | numeric | YES | — | — | No/Not shown | kWh | Consumption variance kwh. | Pass-through from `silver.fact_energy_bill_staging.consumption_variance_kwh`. | — |
| 20 | cost_variance | numeric | YES | — | — | No/Not shown | — | Cost variance. | Pass-through from `silver.fact_energy_bill_staging.cost_variance`. | — |
| 21 | consumption_variance_percent | numeric | YES | — | — | No/Not shown | % | Consumption variance percent. | Pass-through from `silver.fact_energy_bill_staging.consumption_variance_percent`. | — |
| 22 | comparing_with_last_bill | text | YES | — | — | No/Not shown | — | Comparing with last bill. | Pass-through from `silver.fact_energy_bill_staging.comparing_with_last_bill`. | — |
| 23 | comparing_with_grid_bill | text | YES | — | — | No/Not shown | — | Comparing with grid bill. | Pass-through from `silver.fact_energy_bill_staging.comparing_with_grid_bill`. | — |
| 24 | system_reading_timestamp_utc | timestamp without time zone | YES | — | — | No/Not shown | UTC timestamp | System reading timestamp utc. | Pass-through from `silver.fact_energy_bill_staging.system_reading_timestamp_utc`. | — |
| 25 | source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Source created at. | Pass-through from `silver.fact_energy_bill_staging.source_created_at`. | — |

### 19.7 `gold.energy_consumption_validated`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Pass-through from `silver.fact_energy_consumption_validated.energy_meter_key`. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.fact_energy_consumption_validated.facility_key`. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.fact_energy_consumption_validated.zone_key`. | — |
| 4 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Pass-through from `silver.fact_energy_consumption_validated.grid_billing_account_key`. | — |
| 5 | meter_label | text | YES | — | — | No/Not shown | — | Canonical human-readable meter label. | Pass-through from `silver.fact_energy_consumption_validated.meter_label`. | — |
| 6 | reading_timestamp_utc | timestamp without time zone | YES | — | — | No/Not shown | UTC timestamp | Telemetry reading timestamp in UTC at native source precision. | Pass-through from `silver.fact_energy_consumption_validated.reading_timestamp_utc`. | — |
| 7 | reading_timestamp_saudi | timestamp without time zone | YES | — | — | No/Not shown | Asia/Riyadh timestamp | Telemetry reading timestamp converted to Asia/Riyadh local time. | Pass-through from `silver.fact_energy_consumption_validated.reading_timestamp_saudi`. | — |
| 8 | reading_date_saudi | date | YES | — | — | No/Not shown | — | Saudi-local calendar date derived from the telemetry timestamp. | Pass-through from `silver.fact_energy_consumption_validated.reading_date_saudi`. | — |
| 9 | active_energy_cumulative_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative active-energy register reported by the meter. | Pass-through from `silver.fact_energy_consumption_validated.active_energy_cumulative_kwh`. | DQ-KWH-001 |
| 10 | previous_valid_timestamp | timestamp without time zone | YES | — | — | No/Not shown | — | Timestamp of the preceding reading retained as valid for consumption differencing. | Pass-through from `silver.fact_energy_consumption_validated.previous_valid_timestamp`. | DQ-CONS-001 |
| 11 | previous_valid_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative kWh value of the preceding retained valid reading. | Pass-through from `silver.fact_energy_consumption_validated.previous_valid_kwh`. | DQ-CONS-001 |
| 12 | validated_kwh_consumption | double precision | YES | — | — | No/Not shown | — | Validated interval energy consumption derived from cumulative kWh. | Pass-through from `silver.fact_energy_consumption_validated.validated_kwh_consumption`. | DQ-CONS-001 |
| 13 | consumption_cleaning_status | text | YES | — | — | No/Not shown | — | Consumption-cleaning decision/status assigned to the reading. | Pass-through from `silver.fact_energy_consumption_validated.consumption_cleaning_status`. | DQ-CONS-001 |
| 14 | interval_quality | text | YES | — | — | No/Not shown | — | Quality class assigned to the validated consumption interval. | Pass-through from `silver.fact_energy_consumption_validated.interval_quality`. | DQ-CONS-001 |
| 15 | gap_minutes | numeric | YES | — | — | No/Not shown | minutes | Elapsed minutes between relevant consecutive valid/readings. | Pass-through from `silver.fact_energy_consumption_validated.gap_minutes`. | DQ-GAP-001 |

### 19.8 `gold.energy_raw`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Pass-through from `silver.fact_energy_readings_snapshot.energy_meter_key`. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.fact_energy_readings_snapshot.facility_key`. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.fact_energy_readings_snapshot.zone_key`. | — |
| 4 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Pass-through from `silver.fact_energy_readings_snapshot.grid_billing_account_key`. | — |
| 5 | reading_timestamp_utc | timestamp without time zone | YES | — | — | No/Not shown | UTC timestamp | Telemetry reading timestamp in UTC at native source precision. | Pass-through from `silver.fact_energy_readings_snapshot.reading_timestamp_utc`. | — |
| 6 | active_energy_cumulative_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative active-energy register reported by the meter. | Pass-through from `silver.fact_energy_readings_snapshot.active_energy_cumulative_kwh`. | DQ-KWH-001 |
| 7 | reactive_energy_cumulative_kvarh | double precision | YES | — | — | No/Not shown | kVArh | Electrical measurement pivoted from Bronze telemetry key `kVArh`. | Pass-through from `silver.fact_energy_readings_snapshot.reactive_energy_cumulative_kvarh`. | — |
| 8 | apparent_energy_cumulative_kvah | double precision | YES | — | — | No/Not shown | kVAh | Electrical measurement pivoted from Bronze telemetry key `kVAh`. | Pass-through from `silver.fact_energy_readings_snapshot.apparent_energy_cumulative_kvah`. | — |
| 9 | voltage_neutral_1_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn1`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_neutral_1_v`. | DQ-VN-001 |
| 10 | voltage_neutral_2_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn2`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_neutral_2_v`. | DQ-VN-001 |
| 11 | voltage_neutral_3_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn3`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_neutral_3_v`. | DQ-VN-001 |
| 12 | voltage_neutral_average_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vna`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_neutral_average_v`. | DQ-VN-001 |
| 13 | voltage_line_1_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V1`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_line_1_v`. | DQ-VL-001 |
| 14 | voltage_line_2_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V2`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_line_2_v`. | DQ-VL-001 |
| 15 | voltage_line_3_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V3`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_line_3_v`. | DQ-VL-001 |
| 16 | voltage_line_average_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Va`. | Pass-through from `silver.fact_energy_readings_snapshot.voltage_line_average_v`. | DQ-VL-001 |
| 17 | current_phase_1_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp1`. | Pass-through from `silver.fact_energy_readings_snapshot.current_phase_1_a`. | DQ-CUR-001 |
| 18 | current_phase_2_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp2`. | Pass-through from `silver.fact_energy_readings_snapshot.current_phase_2_a`. | DQ-CUR-001 |
| 19 | current_phase_3_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp3`. | Pass-through from `silver.fact_energy_readings_snapshot.current_phase_3_a`. | DQ-CUR-001 |
| 20 | frequency_hz | double precision | YES | — | — | No/Not shown | Hz | Electrical measurement pivoted from Bronze telemetry key `Hz`. | Pass-through from `silver.fact_energy_readings_snapshot.frequency_hz`. | DQ-FREQ-001 |
| 21 | power_factor_phase_1 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF1`. | Pass-through from `silver.fact_energy_readings_snapshot.power_factor_phase_1`. | DQ-PF-001 |
| 22 | power_factor_phase_2 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF2`. | Pass-through from `silver.fact_energy_readings_snapshot.power_factor_phase_2`. | DQ-PF-001 |
| 23 | power_factor_phase_3 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF3`. | Pass-through from `silver.fact_energy_readings_snapshot.power_factor_phase_3`. | DQ-PF-001 |
| 24 | power_factor_average | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PFa`. | Pass-through from `silver.fact_energy_readings_snapshot.power_factor_average`. | DQ-PF-001 |
| 25 | active_power_phase_1_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW1`. | Pass-through from `silver.fact_energy_readings_snapshot.active_power_phase_1_kw`. | — |
| 26 | active_power_phase_2_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW2`. | Pass-through from `silver.fact_energy_readings_snapshot.active_power_phase_2_kw`. | — |
| 27 | active_power_phase_3_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW3`. | Pass-through from `silver.fact_energy_readings_snapshot.active_power_phase_3_kw`. | — |
| 28 | active_power_total_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `TkW`. | Pass-through from `silver.fact_energy_readings_snapshot.active_power_total_kw`. | — |
| 29 | apparent_power_phase_1_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA1`. | Pass-through from `silver.fact_energy_readings_snapshot.apparent_power_phase_1_kva`. | — |
| 30 | apparent_power_phase_2_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA2`. | Pass-through from `silver.fact_energy_readings_snapshot.apparent_power_phase_2_kva`. | — |
| 31 | apparent_power_phase_3_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA3`. | Pass-through from `silver.fact_energy_readings_snapshot.apparent_power_phase_3_kva`. | — |
| 32 | apparent_power_total_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `TkVA`. | Pass-through from `silver.fact_energy_readings_snapshot.apparent_power_total_kva`. | — |
| 33 | reactive_power_phase_1_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr1`. | Pass-through from `silver.fact_energy_readings_snapshot.reactive_power_phase_1_kvar`. | — |
| 34 | reactive_power_phase_2_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr2`. | Pass-through from `silver.fact_energy_readings_snapshot.reactive_power_phase_2_kvar`. | — |
| 35 | reactive_power_phase_3_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr3`. | Pass-through from `silver.fact_energy_readings_snapshot.reactive_power_phase_3_kvar`. | — |
| 36 | reactive_power_total_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `TkVAr`. | Pass-through from `silver.fact_energy_readings_snapshot.reactive_power_total_kvar`. | — |
| 37 | status_vn1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 line-to-neutral voltage. | Pass-through from `silver.fact_energy_readings_snapshot.status_vn1`. | DQ-VN-001 |
| 38 | status_vn2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 line-to-neutral voltage. | Pass-through from `silver.fact_energy_readings_snapshot.status_vn2`. | DQ-VN-001 |
| 39 | status_vn3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 line-to-neutral voltage. | Pass-through from `silver.fact_energy_readings_snapshot.status_vn3`. | DQ-VN-001 |
| 40 | status_v1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 line voltage. | Pass-through from `silver.fact_energy_readings_snapshot.status_v1`. | DQ-VL-001 |
| 41 | status_v2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 line voltage. | Pass-through from `silver.fact_energy_readings_snapshot.status_v2`. | DQ-VL-001 |
| 42 | status_v3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 line voltage. | Pass-through from `silver.fact_energy_readings_snapshot.status_v3`. | DQ-VL-001 |
| 43 | status_amp1 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 1. | Pass-through from `silver.fact_energy_readings_snapshot.status_amp1`. | DQ-CUR-001 |
| 44 | status_amp2 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 2. | Pass-through from `silver.fact_energy_readings_snapshot.status_amp2`. | DQ-CUR-001 |
| 45 | status_amp3 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 3. | Pass-through from `silver.fact_energy_readings_snapshot.status_amp3`. | DQ-CUR-001 |
| 46 | status_hz | text | YES | — | — | No/Not shown | Hz | DQ status for frequency. | Pass-through from `silver.fact_energy_readings_snapshot.status_hz`. | DQ-FREQ-001 |
| 47 | status_pf1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 power factor. | Pass-through from `silver.fact_energy_readings_snapshot.status_pf1`. | DQ-PF-001 |
| 48 | status_pf2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 power factor. | Pass-through from `silver.fact_energy_readings_snapshot.status_pf2`. | DQ-PF-001 |
| 49 | status_pf3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 power factor. | Pass-through from `silver.fact_energy_readings_snapshot.status_pf3`. | DQ-PF-001 |
| 50 | status_pfa | text | YES | — | — | No/Not shown | — | DQ status for average power factor. | Pass-through from `silver.fact_energy_readings_snapshot.status_pfa`. | DQ-PF-001 |
| 51 | status_kwh | text | YES | — | — | No/Not shown | kWh | DQ status for cumulative active-energy direction. | Pass-through from `silver.fact_energy_readings_snapshot.status_kwh`. | DQ-KWH-001 |
| 52 | overall_status | text | YES | — | — | No/Not shown | — | Worst status across the 12 status inputs included by the live `worst_status()` call; current statuses are excluded. | Pass-through from `silver.fact_energy_readings_snapshot.overall_status`. | — |

### 19.9 `gold.energy_reading_gaps`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Derived physical gap table from consecutive analytical meter-reading timestamps. | — |
| 2 | meter_label | text | YES | — | — | No/Not shown | — | Canonical human-readable meter label. | Derived physical gap table from consecutive analytical meter-reading timestamps. | — |
| 3 | previous_reading_timestamp | timestamp without time zone | YES | — | — | No/Not shown | — | Previous reading timestamp. | Derived physical gap table from consecutive analytical meter-reading timestamps. | DQ-GAP-001 |
| 4 | current_reading_timestamp | timestamp without time zone | YES | — | — | No/Not shown | — | Current reading timestamp. | Derived physical gap table from consecutive analytical meter-reading timestamps. | DQ-GAP-001 |
| 5 | gap_seconds | numeric | YES | — | — | No/Not shown | seconds | Elapsed seconds between consecutive meter readings for a recorded gap. | Derived physical gap table from consecutive analytical meter-reading timestamps. | DQ-GAP-001 |
| 6 | gap_minutes | numeric | YES | — | — | No/Not shown | minutes | Elapsed minutes between relevant consecutive valid/readings. | Derived physical gap table from consecutive analytical meter-reading timestamps. | DQ-GAP-001 |
| 7 | gap_hours | numeric | YES | — | — | No/Not shown | hours | Elapsed hours between consecutive meter readings for a recorded gap. | Derived physical gap table from consecutive analytical meter-reading timestamps. | DQ-GAP-001 |
| 8 | gap_days | numeric | YES | — | — | No/Not shown | days | Elapsed days between consecutive meter readings for a recorded gap. | Derived physical gap table from consecutive analytical meter-reading timestamps. | DQ-GAP-001 |

### 19.10 `gold.facility`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.dim_facility_staging.facility_key`. | — |
| 2 | facility_name | text | YES | — | — | No/Not shown | — | Facility name. | Pass-through from `silver.dim_facility_staging.facility_name`. | — |
| 3 | facility_type_key | uuid | YES | — | — | No/Not shown | — | Facility type key identifier. | Pass-through from `silver.dim_facility_staging.facility_type_key`. | — |
| 4 | facility_type_name | text | YES | — | — | No/Not shown | — | Facility type name. | Pass-through from `silver.dim_facility_staging.facility_type_name`. | — |
| 5 | latitude | numeric | YES | — | — | No/Not shown | decimal degrees | Latitude. | Pass-through from `silver.dim_facility_staging.latitude`. | — |
| 6 | longitude | numeric | YES | — | — | No/Not shown | decimal degrees | Longitude. | Pass-through from `silver.dim_facility_staging.longitude`. | — |
| 7 | x_coordinate | numeric | YES | — | — | No/Not shown | — | X coordinate. | Pass-through from `silver.dim_facility_staging.x_coordinate`. | — |
| 8 | y_coordinate | numeric | YES | — | — | No/Not shown | — | Y coordinate. | Pass-through from `silver.dim_facility_staging.y_coordinate`. | — |
| 9 | address_key | uuid | YES | — | — | No/Not shown | — | Address key identifier. | Pass-through from `silver.dim_facility_staging.address_key`. | — |
| 10 | address_title | text | YES | — | — | No/Not shown | — | Address title. | Pass-through from `silver.dim_facility_staging.address_title`. | — |
| 11 | short_address | text | YES | — | — | No/Not shown | — | Short address. | Pass-through from `silver.dim_facility_staging.short_address`. | — |
| 12 | building_number | integer | YES | — | — | No/Not shown | — | Building number. | Pass-through from `silver.dim_facility_staging.building_number`. | — |
| 13 | street_name | text | YES | — | — | No/Not shown | — | Street name. | Pass-through from `silver.dim_facility_staging.street_name`. | — |
| 14 | district_name | text | YES | — | — | No/Not shown | — | District name. | Pass-through from `silver.dim_facility_staging.district_name`. | — |
| 15 | city_name | text | YES | — | — | No/Not shown | — | City name. | Pass-through from `silver.dim_facility_staging.city_name`. | — |
| 16 | zip_code | integer | YES | — | — | No/Not shown | — | Zip code. | Pass-through from `silver.dim_facility_staging.zip_code`. | — |
| 17 | additional_number | integer | YES | — | — | No/Not shown | — | Additional number. | Pass-through from `silver.dim_facility_staging.additional_number`. | — |
| 18 | unit_number | integer | YES | — | — | No/Not shown | — | Unit number. | Pass-through from `silver.dim_facility_staging.unit_number`. | — |
| 19 | source_created_at | timestamp without time zone | YES | — | — | No/Not shown | — | Source created at. | Pass-through from `silver.dim_facility_staging.source_created_at`. | — |

### 19.11 `gold.mapping_audit`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | source_energy_meter_id | uuid | YES | — | — | No/Not shown | — | Source `energy_meters.id` identifier retained for traceability. | Pass-through from `silver.energy_meter_mapping_audit_staging.source_energy_meter_id`. | — |
| 2 | device_id | uuid | YES | — | — | No/Not shown | — | Device id identifier. | Pass-through from `silver.energy_meter_mapping_audit_staging.device_id`. | — |
| 3 | facility_id | uuid | YES | — | — | No/Not shown | — | Facility id identifier. | Pass-through from `silver.energy_meter_mapping_audit_staging.facility_id`. | — |
| 4 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.energy_meter_mapping_audit_staging.zone_key`. | — |
| 5 | zone_name | text | YES | — | — | No/Not shown | — | Zone name. | Pass-through from `silver.energy_meter_mapping_audit_staging.zone_name`. | — |
| 6 | source_device_name | text | YES | — | — | No/Not shown | — | Source device name. | Pass-through from `silver.energy_meter_mapping_audit_staging.source_device_name`. | — |
| 7 | source_meter_label | text | YES | — | — | No/Not shown | — | Source meter label. | Pass-through from `silver.energy_meter_mapping_audit_staging.source_meter_label`. | — |
| 8 | canonical_device_name | text | YES | — | — | No/Not shown | — | Canonical device name. | Pass-through from `silver.energy_meter_mapping_audit_staging.canonical_device_name`. | — |
| 9 | canonical_meter_label | text | YES | — | — | No/Not shown | — | Canonical meter label. | Pass-through from `silver.energy_meter_mapping_audit_staging.canonical_meter_label`. | — |
| 10 | source_meter_records_for_device | bigint | YES | — | — | No/Not shown | — | Source meter records for device. | Pass-through from `silver.energy_meter_mapping_audit_staging.source_meter_records_for_device`. | DQ-MAP-001 |
| 11 | source_records_for_meter_label | bigint | YES | — | — | No/Not shown | — | Source records for meter label. | Pass-through from `silver.energy_meter_mapping_audit_staging.source_records_for_meter_label`. | DQ-MAP-001 |
| 12 | business_rule_code | text | YES | — | — | No/Not shown | — | Business rule code. | Pass-through from `silver.energy_meter_mapping_audit_staging.business_rule_code`. | DQ-MAP-001 |
| 13 | canonical_mapping_rank | bigint | YES | — | — | No/Not shown | — | Canonical mapping rank. | Pass-through from `silver.energy_meter_mapping_audit_staging.canonical_mapping_rank`. | DQ-MAP-001 |
| 14 | mapping_decision | text | YES | — | — | No/Not shown | — | Mapping decision. | Pass-through from `silver.energy_meter_mapping_audit_staging.mapping_decision`. | DQ-MAP-001 |
| 15 | mapping_status | text | YES | — | — | No/Not shown | — | Mapping status controlled status field. | Pass-through from `silver.energy_meter_mapping_audit_staging.mapping_status`. | DQ-MAP-001 |
| 16 | is_meter_active | boolean | YES | — | — | No/Not shown | — | Is meter active flag. | Pass-through from `silver.energy_meter_mapping_audit_staging.is_meter_active`. | — |
| 17 | meter_source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Meter source created at. | Pass-through from `silver.energy_meter_mapping_audit_staging.meter_source_created_at`. | — |

### 19.12 `gold.meter`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Pass-through from `silver.dim_energy_meter_staging.energy_meter_key`. | — |
| 2 | source_energy_meter_id | uuid | YES | — | — | No/Not shown | — | Source `energy_meters.id` identifier retained for traceability. | Pass-through from `silver.dim_energy_meter_staging.source_energy_meter_id`. | — |
| 3 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.dim_energy_meter_staging.facility_key`. | — |
| 4 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.dim_energy_meter_staging.zone_key`. | — |
| 5 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Pass-through from `silver.dim_energy_meter_staging.grid_billing_account_key`. | — |
| 6 | parent_energy_meter_source_id | uuid | YES | — | — | No/Not shown | — | Parent energy meter source id identifier. | Pass-through from `silver.dim_energy_meter_staging.parent_energy_meter_source_id`. | — |
| 7 | meter_label | text | YES | — | — | No/Not shown | — | Canonical human-readable meter label. | Pass-through from `silver.dim_energy_meter_staging.meter_label`. | — |
| 8 | meter_serial_number | text | YES | — | — | No/Not shown | — | Meter serial number. | Pass-through from `silver.dim_energy_meter_staging.meter_serial_number`. | — |
| 9 | phase_count | integer | YES | — | — | No/Not shown | — | Phase count. | Pass-through from `silver.dim_energy_meter_staging.phase_count`. | — |
| 10 | maximum_kwh | integer | YES | — | — | No/Not shown | kWh | Maximum kwh. | Pass-through from `silver.dim_energy_meter_staging.maximum_kwh`. | — |
| 11 | energy_meter_type_key | uuid | YES | — | — | No/Not shown | — | Energy meter type key identifier. | Pass-through from `silver.dim_energy_meter_staging.energy_meter_type_key`. | — |
| 12 | energy_meter_type_name | text | YES | — | — | No/Not shown | — | Energy meter type name. | Pass-through from `silver.dim_energy_meter_staging.energy_meter_type_name`. | — |
| 13 | is_meter_active | boolean | YES | — | — | No/Not shown | — | Is meter active flag. | Pass-through from `silver.dim_energy_meter_staging.is_meter_active`. | — |
| 14 | device_name | text | YES | — | — | No/Not shown | — | Device name. | Pass-through from `silver.dim_energy_meter_staging.device_name`. | — |
| 15 | device_label | text | YES | — | — | No/Not shown | — | Device label. | Pass-through from `silver.dim_energy_meter_staging.device_label`. | — |
| 16 | device_serial_number | bigint | YES | — | — | No/Not shown | — | Device serial number. | Pass-through from `silver.dim_energy_meter_staging.device_serial_number`. | — |
| 17 | device_type_key | uuid | YES | — | — | No/Not shown | — | Device type key identifier. | Pass-through from `silver.dim_energy_meter_staging.device_type_key`. | — |
| 18 | device_type_name | text | YES | — | — | No/Not shown | — | Device type name. | Pass-through from `silver.dim_energy_meter_staging.device_type_name`. | — |
| 19 | device_category_key | uuid | YES | — | — | No/Not shown | — | Device category key identifier. | Pass-through from `silver.dim_energy_meter_staging.device_category_key`. | — |
| 20 | device_category_name | text | YES | — | — | No/Not shown | — | Device category name. | Pass-through from `silver.dim_energy_meter_staging.device_category_name`. | — |
| 21 | gateway_id | uuid | YES | — | — | No/Not shown | — | Gateway id identifier. | Pass-through from `silver.dim_energy_meter_staging.gateway_id`. | — |
| 22 | is_device_active | boolean | YES | — | — | No/Not shown | — | Is device active flag. | Pass-through from `silver.dim_energy_meter_staging.is_device_active`. | — |
| 23 | is_device_online | boolean | YES | — | — | No/Not shown | — | Is device online flag. | Pass-through from `silver.dim_energy_meter_staging.is_device_online`. | — |
| 24 | assembly_date | timestamp without time zone | YES | — | — | No/Not shown | — | Assembly date. | Pass-through from `silver.dim_energy_meter_staging.assembly_date`. | — |
| 25 | device_properties | jsonb | YES | — | — | No/Not shown | — | Device properties. | Pass-through from `silver.dim_energy_meter_staging.device_properties`. | — |
| 26 | source_meter_records_for_device | bigint | YES | — | — | No/Not shown | — | Source meter records for device. | Pass-through from `silver.dim_energy_meter_staging.source_meter_records_for_device`. | DQ-MAP-001 |
| 27 | source_records_for_meter_label | bigint | YES | — | — | No/Not shown | — | Source records for meter label. | Pass-through from `silver.dim_energy_meter_staging.source_records_for_meter_label`. | DQ-MAP-001 |
| 28 | meter_label_matches_device_name | boolean | YES | — | — | No/Not shown | — | Meter label matches device name. | Pass-through from `silver.dim_energy_meter_staging.meter_label_matches_device_name`. | DQ-MAP-001 |
| 29 | mapping_status | text | YES | — | — | No/Not shown | — | Mapping status controlled status field. | Pass-through from `silver.dim_energy_meter_staging.mapping_status`. | DQ-MAP-001 |
| 30 | meter_source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Meter source created at. | Pass-through from `silver.dim_energy_meter_staging.meter_source_created_at`. | — |

### 19.13 `gold.quality_summary`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Pass-through from `silver.data_quality_summary.energy_meter_key`. | — |
| 2 | meter_label | text | YES | — | — | No/Not shown | — | Canonical human-readable meter label. | Pass-through from `silver.data_quality_summary.meter_label`. | — |
| 3 | total_readings | integer | YES | — | — | No/Not shown | — | Total readings. | Pass-through from `silver.data_quality_summary.total_readings`. | — |
| 4 | overall_acceptable_count | integer | YES | — | — | No/Not shown | — | Overall acceptable count. | Pass-through from `silver.data_quality_summary.overall_acceptable_count`. | — |
| 5 | overall_review_required_count | integer | YES | — | — | No/Not shown | — | Overall review required count. | Pass-through from `silver.data_quality_summary.overall_review_required_count`. | — |
| 6 | overall_anomaly_count | integer | YES | — | — | No/Not shown | — | Overall anomaly count. | Pass-through from `silver.data_quality_summary.overall_anomaly_count`. | — |
| 7 | overall_problematic_count | integer | YES | — | — | No/Not shown | — | Overall problematic count. | Pass-through from `silver.data_quality_summary.overall_problematic_count`. | — |
| 8 | overall_critical_count | integer | YES | — | — | No/Not shown | — | Overall critical count. | Pass-through from `silver.data_quality_summary.overall_critical_count`. | — |
| 9 | overall_invalid_count | integer | YES | — | — | No/Not shown | — | Overall invalid count. | Pass-through from `silver.data_quality_summary.overall_invalid_count`. | — |
| 10 | computed_at | timestamp without time zone | YES | — | — | No/Not shown | — | Computed at. | Pass-through from `silver.data_quality_summary.computed_at`. | — |

### 19.14 `gold.zone`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Pass-through from `silver.dim_zone_staging.zone_key`. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Pass-through from `silver.dim_zone_staging.facility_key`. | — |
| 3 | parent_zone_key | uuid | YES | — | — | No/Not shown | — | Parent zone key identifier. | Pass-through from `silver.dim_zone_staging.parent_zone_key`. | — |
| 4 | parent_zone_name | text | YES | — | — | No/Not shown | — | Parent zone name. | Pass-through from `silver.dim_zone_staging.parent_zone_name`. | — |
| 5 | zone_name | text | YES | — | — | No/Not shown | — | Zone name. | Pass-through from `silver.dim_zone_staging.zone_name`. | — |
| 6 | zone_type_key | uuid | YES | — | — | No/Not shown | — | Zone type key identifier. | Pass-through from `silver.dim_zone_staging.zone_type_key`. | — |
| 7 | zone_type_name | text | YES | — | — | No/Not shown | — | Zone type name. | Pass-through from `silver.dim_zone_staging.zone_type_name`. | — |
| 8 | hierarchy_level | integer | YES | — | — | No/Not shown | — | Hierarchy level. | Pass-through from `silver.dim_zone_staging.hierarchy_level`. | — |
| 9 | is_building | boolean | YES | — | — | No/Not shown | — | Is building flag. | Pass-through from `silver.dim_zone_staging.is_building`. | — |
| 10 | is_active | boolean | YES | — | — | No/Not shown | — | Is active flag. | Pass-through from `silver.dim_zone_staging.is_active`. | — |
| 11 | has_children | boolean | YES | — | — | No/Not shown | — | Has children flag. | Pass-through from `silver.dim_zone_staging.has_children`. | — |
| 12 | latitude | numeric | YES | — | — | No/Not shown | decimal degrees | Latitude. | Pass-through from `silver.dim_zone_staging.latitude`. | — |
| 13 | longitude | numeric | YES | — | — | No/Not shown | decimal degrees | Longitude. | Pass-through from `silver.dim_zone_staging.longitude`. | — |
| 14 | x_coordinate | numeric | YES | — | — | No/Not shown | — | X coordinate. | Pass-through from `silver.dim_zone_staging.x_coordinate`. | — |
| 15 | y_coordinate | numeric | YES | — | — | No/Not shown | — | Y coordinate. | Pass-through from `silver.dim_zone_staging.y_coordinate`. | — |
| 16 | html_hex_color | text | YES | — | — | No/Not shown | — | Html hex color. | Pass-through from `silver.dim_zone_staging.html_hex_color`. | — |
| 17 | description | text | YES | — | — | No/Not shown | — | Description. | Pass-through from `silver.dim_zone_staging.description`. | — |
| 18 | source_created_at | timestamp without time zone | YES | — | — | No/Not shown | — | Source created at. | Pass-through from `silver.dim_zone_staging.source_created_at`. | — |

### 19.15 `silver.dim_energy_meter_staging`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 2 | source_energy_meter_id | uuid | YES | — | — | No/Not shown | — | Source `energy_meters.id` identifier retained for traceability. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 3 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 4 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 5 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 6 | parent_energy_meter_source_id | uuid | YES | — | — | No/Not shown | — | Parent energy meter source id identifier. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 7 | meter_label | text | YES | — | — | No/Not shown | — | Canonical human-readable meter label. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 8 | meter_serial_number | text | YES | — | — | No/Not shown | — | Meter serial number. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 9 | phase_count | integer | YES | — | — | No/Not shown | — | Phase count. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 10 | maximum_kwh | integer | YES | — | — | No/Not shown | kWh | Maximum kwh. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 11 | energy_meter_type_key | uuid | YES | — | — | No/Not shown | — | Energy meter type key identifier. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 12 | energy_meter_type_name | text | YES | — | — | No/Not shown | — | Energy meter type name. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 13 | is_meter_active | boolean | YES | — | — | No/Not shown | — | Is meter active flag. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 14 | device_name | text | YES | — | — | No/Not shown | — | Device name. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 15 | device_label | text | YES | — | — | No/Not shown | — | Device label. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 16 | device_serial_number | bigint | YES | — | — | No/Not shown | — | Device serial number. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 17 | device_type_key | uuid | YES | — | — | No/Not shown | — | Device type key identifier. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 18 | device_type_name | text | YES | — | — | No/Not shown | — | Device type name. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 19 | device_category_key | uuid | YES | — | — | No/Not shown | — | Device category key identifier. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 20 | device_category_name | text | YES | — | — | No/Not shown | — | Device category name. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 21 | gateway_id | uuid | YES | — | — | No/Not shown | — | Gateway id identifier. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 22 | is_device_active | boolean | YES | — | — | No/Not shown | — | Is device active flag. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 23 | is_device_online | boolean | YES | — | — | No/Not shown | — | Is device online flag. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 24 | assembly_date | timestamp without time zone | YES | — | — | No/Not shown | — | Assembly date. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 25 | device_properties | jsonb | YES | — | — | No/Not shown | — | Device properties. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |
| 26 | source_meter_records_for_device | bigint | YES | — | — | No/Not shown | — | Source meter records for device. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | DQ-MAP-001 |
| 27 | source_records_for_meter_label | bigint | YES | — | — | No/Not shown | — | Source records for meter label. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | DQ-MAP-001 |
| 28 | meter_label_matches_device_name | boolean | YES | — | — | No/Not shown | — | Meter label matches device name. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | DQ-MAP-001 |
| 29 | mapping_status | text | YES | — | — | No/Not shown | — | Mapping status controlled status field. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | DQ-MAP-001 |
| 30 | meter_source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Meter source created at. | Derived from Silver meter/device/unit/type/category landing views with canonical mapping rules. | — |

### 19.16 `silver.dim_grid_billing_account_staging`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Derived from Silver billing-account/type/service-class landing views. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Derived from Silver billing-account/type/service-class landing views. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Derived from Silver billing-account/type/service-class landing views. | — |
| 4 | account_label | text | YES | — | — | No/Not shown | — | Account label. | Derived from Silver billing-account/type/service-class landing views. | — |
| 5 | account_number | text | YES | — | — | No/Not shown | — | Account number. | Derived from Silver billing-account/type/service-class landing views. | — |
| 6 | meter_serial_number | text | YES | — | — | No/Not shown | — | Meter serial number. | Derived from Silver billing-account/type/service-class landing views. | — |
| 7 | account_type_key | uuid | YES | — | — | No/Not shown | — | Account type key identifier. | Derived from Silver billing-account/type/service-class landing views. | — |
| 8 | account_type_name | text | YES | — | — | No/Not shown | — | Account type name. | Derived from Silver billing-account/type/service-class landing views. | — |
| 9 | service_class_key | uuid | YES | — | — | No/Not shown | — | Service class key identifier. | Derived from Silver billing-account/type/service-class landing views. | — |
| 10 | service_class_name | text | YES | — | — | No/Not shown | — | Service class name. | Derived from Silver billing-account/type/service-class landing views. | — |
| 11 | breaker_capacity | integer | YES | — | — | No/Not shown | — | Breaker capacity. | Derived from Silver billing-account/type/service-class landing views. | — |
| 12 | minimal_breaker_capacity | integer | YES | — | — | No/Not shown | — | Minimal breaker capacity. | Derived from Silver billing-account/type/service-class landing views. | — |
| 13 | maximum_breaker_capacity | integer | YES | — | — | No/Not shown | — | Maximum breaker capacity. | Derived from Silver billing-account/type/service-class landing views. | — |
| 14 | service_class_fee | integer | YES | — | — | No/Not shown | — | Service class fee. | Derived from Silver billing-account/type/service-class landing views. | — |
| 15 | multiplication_factor | integer | YES | — | — | No/Not shown | — | Multiplication factor. | Derived from Silver billing-account/type/service-class landing views. | — |
| 16 | start_period | timestamp with time zone | YES | — | — | No/Not shown | — | Start period. | Derived from Silver billing-account/type/service-class landing views. | — |
| 17 | end_period | timestamp with time zone | YES | — | — | No/Not shown | — | End period. | Derived from Silver billing-account/type/service-class landing views. | — |
| 18 | configured_billing_days | integer | YES | — | — | No/Not shown | — | Configured billing days. | Derived from Silver billing-account/type/service-class landing views. | — |
| 19 | source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Source created at. | Derived from Silver billing-account/type/service-class landing views. | — |

### 19.17 `silver.dim_meter_cb_rating`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | NO | — | PK | Yes | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Project-maintained breaker-rating reference table; external authoritative engineering source not embedded in catalog metadata. | — |
| 2 | cb_max_rating_a | double precision | NO | — | — | No/Not shown | A | Per-meter circuit-breaker maximum current rating used by the current classifier. | Project-maintained breaker-rating reference table; external authoritative engineering source not embedded in catalog metadata. | DQ-CUR-001 |
| 3 | updated_at | timestamp without time zone | YES | now() | — | No/Not shown | — | Updated at. | Project-maintained breaker-rating reference table; external authoritative engineering source not embedded in catalog metadata. | — |

### 19.18 `silver.energy_meter_mapping_audit_staging`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | source_energy_meter_id | uuid | YES | — | — | No/Not shown | — | Source `energy_meters.id` identifier retained for traceability. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 2 | device_id | uuid | YES | — | — | No/Not shown | — | Device id identifier. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 3 | facility_id | uuid | YES | — | — | No/Not shown | — | Facility id identifier. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 4 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 5 | zone_name | text | YES | — | — | No/Not shown | — | Zone name. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 6 | source_device_name | text | YES | — | — | No/Not shown | — | Source device name. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 7 | source_meter_label | text | YES | — | — | No/Not shown | — | Source meter label. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 8 | canonical_device_name | text | YES | — | — | No/Not shown | — | Canonical device name. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 9 | canonical_meter_label | text | YES | — | — | No/Not shown | — | Canonical meter label. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 10 | source_meter_records_for_device | bigint | YES | — | — | No/Not shown | — | Source meter records for device. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | DQ-MAP-001 |
| 11 | source_records_for_meter_label | bigint | YES | — | — | No/Not shown | — | Source records for meter label. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | DQ-MAP-001 |
| 12 | business_rule_code | text | YES | — | — | No/Not shown | — | Business rule code. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | DQ-MAP-001 |
| 13 | canonical_mapping_rank | bigint | YES | — | — | No/Not shown | — | Canonical mapping rank. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | DQ-MAP-001 |
| 14 | mapping_decision | text | YES | — | — | No/Not shown | — | Mapping decision. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | DQ-MAP-001 |
| 15 | mapping_status | text | YES | — | — | No/Not shown | — | Mapping status controlled status field. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | DQ-MAP-001 |
| 16 | is_meter_active | boolean | YES | — | — | No/Not shown | — | Is meter active flag. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |
| 17 | meter_source_created_at | timestamp with time zone | YES | — | — | No/Not shown | — | Meter source created at. | Derived from Silver meter/device/unit landing views with mapping business rules and ranking. | — |

### 19.19 `silver.fact_energy_consumption_validated`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | Yes | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | From reading snapshot / canonical meter dimension. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | From reading snapshot / canonical meter dimension. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | From reading snapshot / canonical meter dimension. | — |
| 4 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | From reading snapshot / canonical meter dimension. | — |
| 5 | meter_label | text | YES | — | — | Yes | — | Canonical human-readable meter label. | From reading snapshot / canonical meter dimension. | — |
| 6 | reading_timestamp_utc | timestamp without time zone | YES | — | — | Yes | UTC timestamp | Telemetry reading timestamp in UTC at native source precision. | From reading snapshot / canonical meter dimension. | — |
| 7 | reading_timestamp_saudi | timestamp without time zone | YES | — | — | No/Not shown | Asia/Riyadh timestamp | Telemetry reading timestamp converted to Asia/Riyadh local time. | From reading snapshot / canonical meter dimension. | — |
| 8 | reading_date_saudi | date | YES | — | — | Yes | — | Saudi-local calendar date derived from the telemetry timestamp. | From reading snapshot / canonical meter dimension. | — |
| 9 | active_energy_cumulative_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative active-energy register reported by the meter. | From reading snapshot / canonical meter dimension. | DQ-KWH-001 |
| 10 | status_kwh | text | YES | — | — | No/Not shown | kWh | DQ status for cumulative active-energy direction. | From reading snapshot / canonical meter dimension. | DQ-KWH-001 |
| 11 | raw_previous_kwh | double precision | YES | — | — | No/Not shown | kWh | Raw previous kwh. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |
| 12 | raw_next_kwh | double precision | YES | — | — | No/Not shown | kWh | Raw next kwh. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |
| 13 | consumption_cleaning_status | text | YES | — | — | No/Not shown | — | Consumption-cleaning decision/status assigned to the reading. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |
| 14 | previous_valid_timestamp | timestamp without time zone | YES | — | — | No/Not shown | — | Timestamp of the preceding reading retained as valid for consumption differencing. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |
| 15 | previous_valid_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative kWh value of the preceding retained valid reading. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |
| 16 | validated_kwh_consumption | double precision | YES | — | — | No/Not shown | — | Validated interval energy consumption derived from cumulative kWh. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |
| 17 | gap_minutes | numeric | YES | — | — | No/Not shown | minutes | Elapsed minutes between relevant consecutive valid/readings. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-GAP-001 |
| 18 | interval_quality | text | YES | — | — | No/Not shown | — | Quality class assigned to the validated consumption interval. | Derived from cumulative-kWh validation/differencing logic documented in §10. | DQ-CONS-001 |

### 19.20 `silver.fact_energy_readings_flagged`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 2 | source_energy_meter_id | uuid | YES | — | — | No/Not shown | — | Source `energy_meters.id` identifier retained for traceability. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 3 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 4 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 5 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 6 | date_key | integer | YES | — | — | No/Not shown | — | Calendar date surrogate/key in YYYYMMDD-style integer form. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 7 | time_key | integer | YES | — | — | No/Not shown | — | Time key derived from the reading timestamp. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 8 | source_timestamp_ms | bigint | YES | — | — | No/Not shown | — | Original Bronze telemetry epoch timestamp in milliseconds. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 9 | reading_timestamp_utc | timestamp without time zone | YES | — | — | No/Not shown | UTC timestamp | Telemetry reading timestamp in UTC at native source precision. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 10 | reading_timestamp_saudi | timestamp without time zone | YES | — | — | No/Not shown | Asia/Riyadh timestamp | Telemetry reading timestamp converted to Asia/Riyadh local time. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 11 | reading_date_saudi | date | YES | — | — | No/Not shown | — | Saudi-local calendar date derived from the telemetry timestamp. | Identity/time field passed from `fact_energy_readings_staging`. | — |
| 12 | status_vn1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 line-to-neutral voltage. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-VN-001 |
| 13 | status_vn2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 line-to-neutral voltage. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-VN-001 |
| 14 | status_vn3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 line-to-neutral voltage. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-VN-001 |
| 15 | status_v1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 line voltage. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-VL-001 |
| 16 | status_v2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 line voltage. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-VL-001 |
| 17 | status_v3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 line voltage. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-VL-001 |
| 18 | status_amp1 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 1. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-CUR-001 |
| 19 | status_amp2 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 2. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-CUR-001 |
| 20 | status_amp3 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 3. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-CUR-001 |
| 21 | status_hz | text | YES | — | — | No/Not shown | Hz | DQ status for frequency. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-FREQ-001 |
| 22 | status_pf1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 power factor. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-PF-001 |
| 23 | status_pf2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 power factor. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-PF-001 |
| 24 | status_pf3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 power factor. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-PF-001 |
| 25 | status_pfa | text | YES | — | — | No/Not shown | — | DQ status for average power factor. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-PF-001 |
| 26 | status_kwh | text | YES | — | — | No/Not shown | kWh | DQ status for cumulative active-energy direction. | Derived by live Silver classifier function(s); see DQ Rule. | DQ-KWH-001 |
| 27 | overall_status | text | YES | — | — | No/Not shown | — | Worst status across the 12 status inputs included by the live `worst_status()` call; current statuses are excluded. | Derived by `silver.worst_status()` over 12 non-current status inputs. | — |

### 19.21 `silver.fact_energy_readings_snapshot`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | NO | — | PK | Yes | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | From `silver.fact_energy_readings_staging`. | — |
| 2 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | From `silver.fact_energy_readings_staging`. | — |
| 3 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | From `silver.fact_energy_readings_staging`. | — |
| 4 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | From `silver.fact_energy_readings_staging`. | — |
| 5 | reading_timestamp_utc | timestamp without time zone | NO | — | PK | Yes | UTC timestamp | Telemetry reading timestamp in UTC at native source precision. | From `silver.fact_energy_readings_staging`. | — |
| 6 | active_energy_cumulative_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative active-energy register reported by the meter. | From `silver.fact_energy_readings_staging`. | DQ-KWH-001 |
| 7 | reactive_energy_cumulative_kvarh | double precision | YES | — | — | No/Not shown | kVArh | Electrical measurement pivoted from Bronze telemetry key `kVArh`. | From `silver.fact_energy_readings_staging`. | — |
| 8 | apparent_energy_cumulative_kvah | double precision | YES | — | — | No/Not shown | kVAh | Electrical measurement pivoted from Bronze telemetry key `kVAh`. | From `silver.fact_energy_readings_staging`. | — |
| 9 | voltage_neutral_1_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn1`. | From `silver.fact_energy_readings_staging`. | DQ-VN-001 |
| 10 | voltage_neutral_2_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn2`. | From `silver.fact_energy_readings_staging`. | DQ-VN-001 |
| 11 | voltage_neutral_3_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn3`. | From `silver.fact_energy_readings_staging`. | DQ-VN-001 |
| 12 | voltage_neutral_average_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vna`. | From `silver.fact_energy_readings_staging`. | DQ-VN-001 |
| 13 | voltage_line_1_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V1`. | From `silver.fact_energy_readings_staging`. | DQ-VL-001 |
| 14 | voltage_line_2_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V2`. | From `silver.fact_energy_readings_staging`. | DQ-VL-001 |
| 15 | voltage_line_3_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V3`. | From `silver.fact_energy_readings_staging`. | DQ-VL-001 |
| 16 | voltage_line_average_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Va`. | From `silver.fact_energy_readings_staging`. | DQ-VL-001 |
| 17 | current_phase_1_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp1`. | From `silver.fact_energy_readings_staging`. | DQ-CUR-001 |
| 18 | current_phase_2_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp2`. | From `silver.fact_energy_readings_staging`. | DQ-CUR-001 |
| 19 | current_phase_3_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp3`. | From `silver.fact_energy_readings_staging`. | DQ-CUR-001 |
| 20 | frequency_hz | double precision | YES | — | — | No/Not shown | Hz | Electrical measurement pivoted from Bronze telemetry key `Hz`. | From `silver.fact_energy_readings_staging`. | DQ-FREQ-001 |
| 21 | power_factor_phase_1 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF1`. | From `silver.fact_energy_readings_staging`. | DQ-PF-001 |
| 22 | power_factor_phase_2 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF2`. | From `silver.fact_energy_readings_staging`. | DQ-PF-001 |
| 23 | power_factor_phase_3 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF3`. | From `silver.fact_energy_readings_staging`. | DQ-PF-001 |
| 24 | power_factor_average | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PFa`. | From `silver.fact_energy_readings_staging`. | DQ-PF-001 |
| 25 | active_power_phase_1_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW1`. | From `silver.fact_energy_readings_staging`. | — |
| 26 | active_power_phase_2_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW2`. | From `silver.fact_energy_readings_staging`. | — |
| 27 | active_power_phase_3_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW3`. | From `silver.fact_energy_readings_staging`. | — |
| 28 | active_power_total_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `TkW`. | From `silver.fact_energy_readings_staging`. | — |
| 29 | apparent_power_phase_1_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA1`. | From `silver.fact_energy_readings_staging`. | — |
| 30 | apparent_power_phase_2_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA2`. | From `silver.fact_energy_readings_staging`. | — |
| 31 | apparent_power_phase_3_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA3`. | From `silver.fact_energy_readings_staging`. | — |
| 32 | apparent_power_total_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `TkVA`. | From `silver.fact_energy_readings_staging`. | — |
| 33 | reactive_power_phase_1_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr1`. | From `silver.fact_energy_readings_staging`. | — |
| 34 | reactive_power_phase_2_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr2`. | From `silver.fact_energy_readings_staging`. | — |
| 35 | reactive_power_phase_3_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr3`. | From `silver.fact_energy_readings_staging`. | — |
| 36 | reactive_power_total_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `TkVAr`. | From `silver.fact_energy_readings_staging`. | — |
| 37 | status_vn1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 line-to-neutral voltage. | From `silver.fact_energy_readings_flagged`. | DQ-VN-001 |
| 38 | status_vn2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 line-to-neutral voltage. | From `silver.fact_energy_readings_flagged`. | DQ-VN-001 |
| 39 | status_vn3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 line-to-neutral voltage. | From `silver.fact_energy_readings_flagged`. | DQ-VN-001 |
| 40 | status_v1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 line voltage. | From `silver.fact_energy_readings_flagged`. | DQ-VL-001 |
| 41 | status_v2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 line voltage. | From `silver.fact_energy_readings_flagged`. | DQ-VL-001 |
| 42 | status_v3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 line voltage. | From `silver.fact_energy_readings_flagged`. | DQ-VL-001 |
| 43 | status_amp1 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 1. | From `silver.fact_energy_readings_flagged`. | DQ-CUR-001 |
| 44 | status_amp2 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 2. | From `silver.fact_energy_readings_flagged`. | DQ-CUR-001 |
| 45 | status_amp3 | text | YES | — | — | No/Not shown | — | Production current-classifier result for Phase 3. | From `silver.fact_energy_readings_flagged`. | DQ-CUR-001 |
| 46 | status_hz | text | YES | — | — | No/Not shown | Hz | DQ status for frequency. | From `silver.fact_energy_readings_flagged`. | DQ-FREQ-001 |
| 47 | status_pf1 | text | YES | — | — | No/Not shown | — | DQ status for Phase-1 power factor. | From `silver.fact_energy_readings_flagged`. | DQ-PF-001 |
| 48 | status_pf2 | text | YES | — | — | No/Not shown | — | DQ status for Phase-2 power factor. | From `silver.fact_energy_readings_flagged`. | DQ-PF-001 |
| 49 | status_pf3 | text | YES | — | — | No/Not shown | — | DQ status for Phase-3 power factor. | From `silver.fact_energy_readings_flagged`. | DQ-PF-001 |
| 50 | status_pfa | text | YES | — | — | No/Not shown | — | DQ status for average power factor. | From `silver.fact_energy_readings_flagged`. | DQ-PF-001 |
| 51 | status_kwh | text | YES | — | — | No/Not shown | kWh | DQ status for cumulative active-energy direction. | From `silver.fact_energy_readings_flagged`. | DQ-KWH-001 |
| 52 | overall_status | text | YES | — | — | No/Not shown | — | Worst status across the 12 status inputs included by the live `worst_status()` call; current statuses are excluded. | From `silver.fact_energy_readings_flagged`. | — |

### 19.22 `silver.fact_energy_readings_staging`

| Ord | Column | Type | Nullable | Default | Key | Indexed | Unit / Format | Business definition | Source / transformation | DQ rule |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | energy_meter_key | uuid | YES | — | — | No/Not shown | — | Canonical reporting-device / energy-meter identifier used across Silver and Gold. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 2 | source_energy_meter_id | uuid | YES | — | — | No/Not shown | — | Source `energy_meters.id` identifier retained for traceability. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 3 | facility_key | uuid | YES | — | — | No/Not shown | — | Facility identifier associated with the record. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 4 | zone_key | uuid | YES | — | — | No/Not shown | — | Zone/unit identifier associated with the record. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 5 | grid_billing_account_key | uuid | YES | — | — | No/Not shown | — | Grid billing-account identifier associated with the record. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 6 | date_key | integer | YES | — | — | No/Not shown | — | Calendar date surrogate/key in YYYYMMDD-style integer form. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 7 | time_key | integer | YES | — | — | No/Not shown | — | Time key derived from the reading timestamp. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 8 | source_timestamp_ms | bigint | YES | — | — | No/Not shown | — | Original Bronze telemetry epoch timestamp in milliseconds. | Inherited from canonical meter mapping or source telemetry packet. | — |
| 9 | reading_timestamp_utc | timestamp without time zone | YES | — | — | No/Not shown | UTC timestamp | Telemetry reading timestamp in UTC at native source precision. | Converted from Bronze epoch milliseconds to UTC timestamp. | — |
| 10 | voltage_line_1_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V1`. | Pivot from Bronze telemetry key `V1` via Silver landing views. | DQ-VL-001 |
| 11 | voltage_line_2_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V2`. | Pivot from Bronze telemetry key `V2` via Silver landing views. | DQ-VL-001 |
| 12 | voltage_line_3_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `V3`. | Pivot from Bronze telemetry key `V3` via Silver landing views. | DQ-VL-001 |
| 13 | voltage_line_average_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Va`. | Pivot from Bronze telemetry key `Va` via Silver landing views. | DQ-VL-001 |
| 14 | voltage_neutral_1_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn1`. | Pivot from Bronze telemetry key `Vn1` via Silver landing views. | DQ-VN-001 |
| 15 | voltage_neutral_2_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn2`. | Pivot from Bronze telemetry key `Vn2` via Silver landing views. | DQ-VN-001 |
| 16 | voltage_neutral_3_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vn3`. | Pivot from Bronze telemetry key `Vn3` via Silver landing views. | DQ-VN-001 |
| 17 | voltage_neutral_average_v | double precision | YES | — | — | No/Not shown | V | Electrical measurement pivoted from Bronze telemetry key `Vna`. | Pivot from Bronze telemetry key `Vna` via Silver landing views. | DQ-VN-001 |
| 18 | current_phase_1_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp1`. | Pivot from Bronze telemetry key `Amp1` via Silver landing views. | DQ-CUR-001 |
| 19 | current_phase_2_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp2`. | Pivot from Bronze telemetry key `Amp2` via Silver landing views. | DQ-CUR-001 |
| 20 | current_phase_3_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Amp3`. | Pivot from Bronze telemetry key `Amp3` via Silver landing views. | DQ-CUR-001 |
| 21 | current_average_a | double precision | YES | — | — | No/Not shown | A | Electrical measurement pivoted from Bronze telemetry key `Ampa`. | Pivot from Bronze telemetry key `Ampa` via Silver landing views. | — |
| 22 | frequency_hz | double precision | YES | — | — | No/Not shown | Hz | Electrical measurement pivoted from Bronze telemetry key `Hz`. | Pivot from Bronze telemetry key `Hz` via Silver landing views. | DQ-FREQ-001 |
| 23 | power_factor_phase_1 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF1`. | Pivot from Bronze telemetry key `PF1` via Silver landing views. | DQ-PF-001 |
| 24 | power_factor_phase_2 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF2`. | Pivot from Bronze telemetry key `PF2` via Silver landing views. | DQ-PF-001 |
| 25 | power_factor_phase_3 | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PF3`. | Pivot from Bronze telemetry key `PF3` via Silver landing views. | DQ-PF-001 |
| 26 | power_factor_average | double precision | YES | — | — | No/Not shown | unitless | Electrical measurement pivoted from Bronze telemetry key `PFa`. | Pivot from Bronze telemetry key `PFa` via Silver landing views. | DQ-PF-001 |
| 27 | active_power_phase_1_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW1`. | Pivot from Bronze telemetry key `kW1` via Silver landing views. | — |
| 28 | active_power_phase_2_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW2`. | Pivot from Bronze telemetry key `kW2` via Silver landing views. | — |
| 29 | active_power_phase_3_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `kW3`. | Pivot from Bronze telemetry key `kW3` via Silver landing views. | — |
| 30 | active_power_total_kw | double precision | YES | — | — | No/Not shown | kW | Electrical measurement pivoted from Bronze telemetry key `TkW`. | Pivot from Bronze telemetry key `TkW` via Silver landing views. | — |
| 31 | apparent_power_phase_1_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA1`. | Pivot from Bronze telemetry key `kVA1` via Silver landing views. | — |
| 32 | apparent_power_phase_2_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA2`. | Pivot from Bronze telemetry key `kVA2` via Silver landing views. | — |
| 33 | apparent_power_phase_3_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `kVA3`. | Pivot from Bronze telemetry key `kVA3` via Silver landing views. | — |
| 34 | apparent_power_total_kva | double precision | YES | — | — | No/Not shown | kVA | Electrical measurement pivoted from Bronze telemetry key `TkVA`. | Pivot from Bronze telemetry key `TkVA` via Silver landing views. | — |
| 35 | reactive_power_phase_1_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr1`. | Pivot from Bronze telemetry key `kVAr1` via Silver landing views. | — |
| 36 | reactive_power_phase_2_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr2`. | Pivot from Bronze telemetry key `kVAr2` via Silver landing views. | — |
| 37 | reactive_power_phase_3_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `kVAr3`. | Pivot from Bronze telemetry key `kVAr3` via Silver landing views. | — |
| 38 | reactive_power_total_kvar | double precision | YES | — | — | No/Not shown | kVAr | Electrical measurement pivoted from Bronze telemetry key `TkVAr`. | Pivot from Bronze telemetry key `TkVAr` via Silver landing views. | — |
| 39 | active_energy_cumulative_kwh | double precision | YES | — | — | No/Not shown | kWh | Cumulative active-energy register reported by the meter. | Pivot from Bronze telemetry key `kWh` via Silver landing views. | DQ-KWH-001 |
| 40 | apparent_energy_cumulative_kvah | double precision | YES | — | — | No/Not shown | kVAh | Electrical measurement pivoted from Bronze telemetry key `kVAh`. | Pivot from Bronze telemetry key `kVAh` via Silver landing views. | — |
| 41 | reactive_energy_cumulative_kvarh | double precision | YES | — | — | No/Not shown | kVArh | Electrical measurement pivoted from Bronze telemetry key `kVArh`. | Pivot from Bronze telemetry key `kVArh` via Silver landing views. | — |
| 42 | source_measurement_row_count | integer | YES | — | — | No/Not shown | — | Count of source telemetry rows contributing to the meter×timestamp packet. | Derived by packet-level row/distinct-key counts. | DQ-PACKET-001 |
| 43 | populated_measurement_count | integer | YES | — | — | No/Not shown | — | Count of distinct telemetry keys populated in the meter×timestamp packet. | Derived by packet-level row/distinct-key counts. | DQ-PACKET-001 |
| 44 | duplicate_measurement_row_count | integer | YES | — | — | No/Not shown | — | Source telemetry rows beyond the distinct-key count for the packet; diagnostic for duplicate measurements. | Derived by packet-level row/distinct-key counts. | DQ-PACKET-001 |
| 45 | reading_timestamp_saudi | timestamp without time zone | YES | — | — | No/Not shown | Asia/Riyadh timestamp | Telemetry reading timestamp converted to Asia/Riyadh local time. | Derived from source epoch timestamp using `Asia/Riyadh`. | — |
| 46 | reading_date_saudi | date | YES | — | — | No/Not shown | — | Saudi-local calendar date derived from the telemetry timestamp. | Derived from source epoch timestamp using `Asia/Riyadh`. | — |
| 47 | reading_time_saudi | time without time zone | YES | — | — | No/Not shown | — | Reading time saudi. | Derived from source epoch timestamp using `Asia/Riyadh`. | — |
| 48 | saudi_date_key | integer | YES | — | — | No/Not shown | — | Saudi-local date key derived from reading timestamp. | Derived from source epoch timestamp using `Asia/Riyadh`. | — |
| 49 | saudi_time_key | integer | YES | — | — | No/Not shown | — | Saudi-local time key derived from reading timestamp. | Derived from source epoch timestamp using `Asia/Riyadh`. | — |
| 50 | calculated_current_average_a | double precision | YES | — | — | No/Not shown | A | Calculated arithmetic mean of the three phase-current readings when evaluation prerequisites are met. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-CUR-001 |
| 51 | current_phase_spread_a | double precision | YES | — | — | No/Not shown | A | Difference between maximum and minimum three-phase current. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-CUR-001 |
| 52 | current_imbalance_pct | double precision | YES | — | — | No/Not shown | % | Maximum phase deviation from the three-phase mean, expressed as a percentage of the absolute mean. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-CUR-001 |
| 53 | current_imbalance_evaluation_status | text | YES | — | — | No/Not shown | — | Diagnostic status indicating whether current imbalance was evaluated and why it may be not applicable. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-CUR-001 |
| 54 | calculated_voltage_average_v | double precision | YES | — | — | No/Not shown | V | Calculated arithmetic mean of the three line-voltage phase readings when prerequisites are met. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-VOLT-001 |
| 55 | voltage_phase_spread_v | double precision | YES | — | — | No/Not shown | V | Difference between maximum and minimum three-phase line voltage. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-VOLT-001 |
| 56 | voltage_imbalance_pct | double precision | YES | — | — | No/Not shown | % | Maximum phase-voltage deviation from the three-phase mean, expressed as a percentage of the absolute mean. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-VOLT-001 |
| 57 | voltage_imbalance_evaluation_status | text | YES | — | — | No/Not shown | — | Diagnostic status indicating whether voltage imbalance was evaluated and why it may be not applicable. | Derived in `fact_energy_readings_staging` from three-phase values. | DQ-IMB-VOLT-001 |

## 20. Metadata Evidence & Change Control

### 20.1 Evidence used for this edition

This edition incorporates live PostgreSQL outputs for:
- object type and relation size;
- complete scoped column metadata from `information_schema.columns`;
- PK/FK/CHECK/NOT NULL metadata from PostgreSQL catalogs;
- index definitions from `pg_indexes`;
- live view definitions via `pg_get_viewdef()`;
- live function definitions via `pg_get_functiondef()`.

### 20.2 Important implementation confirmations from the live metadata

1. `silver.fact_energy_readings_flagged` calls **`classify_current_v2(value, cb_max, phase_kw)`**, not the two-argument overload.
2. Current/power mismatch logic is confined to the **lower fringe (`current < 15% of CB`)** in that production function.
3. Current uses literal zero comparisons; no epsilon is present in the extracted function.
4. Negative current returns `Invalid`; current strictly above breaker rating returns `Critical`.
5. `overall_status` excludes **all three current statuses**.
6. `silver.fact_energy_readings_snapshot` is a physical table with enforced PK `(energy_meter_key, reading_timestamp_utc)`.
7. `silver.fact_energy_consumption_validated` is a physical table with indexes on Saudi date, meter label, and `(energy_meter_key, reading_timestamp_utc)`, but no PK/UNIQUE constraint was returned.
8. `gold.energy_reading_gaps` is a physical table; its scheduler/refresh procedure is not present in the supplied catalog metadata.
9. `gold.energy_raw` is a SQL view with 52 physical columns. `meter_label` is not one of them; the readable meter label used in Power BI is a model-level calculated/related field as documented earlier.

### 20.3 Change-control principle

Future editions should re-run the metadata extractor after schema/function changes. Physical metadata should be replaced from the new catalog output rather than manually guessed. Business definitions and DQ descriptions should then be reviewed only where the underlying SQL or approved business rule changed.

