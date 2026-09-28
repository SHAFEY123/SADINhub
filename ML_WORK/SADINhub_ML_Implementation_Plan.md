# SADINhub — ML Implementation Plan (v2)
**Supersedes:** `03_ml_experiment.py` / `ml_outputs/experiment_20260907_v1` (Random Forest, HistGB, Isolation Forest on per-meter daily data)
**Status:** Proposed implementation plan, not yet built
**Prepared for:** Energy Intelligence & Predictive Analytics Platform (SADINhub)

---

## 1. Map of the current system (as-is, unchanged)

This plan builds **on top of** the existing pipeline. Nothing below changes Bronze, Silver, Gold, or Power BI.

```
Bronze (unchanged source)
  bronze.telemetries  (~109M rows, long format)
  bronze.energy_meters, bronze.telemetries_dictionaries
        │
        ▼
Silver (business rules, isolated from source)
  silver.fact_energy_readings_staging     → pivot to wide, 5-min grain
  silver.fact_energy_readings_flagged     → status_* classifiers (PF, V, Hz, current, kWh)
  silver.fact_energy_readings_snapshot    → PHYSICAL, 4,535,918 rows, 31 meters
  silver.fact_energy_consumption_validated→ PHYSICAL, 4,260,849 rows, 29 meters (Zn.13 excluded)
        │
        ▼
Gold (governed reporting layer)
  gold.energy_raw                  → raw grain, all 31 meters, all statuses
  gold.energy_consumption_validated→ interval kWh, 29 meters
  gold.energy_reading_gaps         → gap evidence
  gold.meter / zone / facility / date / billing_account → dimensions
        │
        ├──► Power BI (8-page report, reconciled, read from Gold only)
        │
        └──► ML branch (read-only Postgres access, writes local files only)
                 02_prepare_daily_data.py → daily_consumption_profile.csv (OLD, to be revised — §3.0)
                 03_ml_experiment.py      → RF / HistGB / Isolation Forest (DISCARDED)
```

**What stays exactly as-is:** Bronze→Silver→Gold ETL, reconciliation checks, Power BI model, the read-only/isolated ML access pattern, and the existing `status_*` classifier logic (current/power, PF, voltage, frequency, kWh direction) — this classifier output becomes an **input feature** to the new ML layer rather than being discarded after dashboarding.

**What this plan replaces:** everything downstream of Gold in the ML branch — the daily-prep script's label logic, and all three models.

---

## 2. Target architecture (to-be)

```
gold.energy_raw ─────────────────────┐
 (5-min, 31 meters, quality flags)   │
        │                            │
        ▼                            │
 MODEL 1: Raw-grain SPC / rule       │
 anomaly layer (per meter × phase)   │
        │                            │
        ▼                            │
 anomaly_events (raw grain output)   │
        │                            │
        │                            ▼
        │                 gold.energy_consumption_validated
        │                            │
        │                            ▼
        │                 LEAKAGE-SAFE daily replay
        │                 (forecast-time-safe cleaning — §3.0, prerequisite)
        │                            │
        │              ┌─────────────┴─────────────┐
        │              ▼                            ▼
        │   MODEL 2: Global pooled          MODEL 3: Daily-aggregate
        │   quantile forecaster              triage (Isolation Forest
        │   (all 29 meters, one model)       on quality-flag daily counts)
        │              │                            │
        └──────────────┴─────────────┬──────────────┘
                                      ▼
                        model_outputs/ (versioned CSV/Parquet)
                        run_metadata.json (unchanged discipline)
                                      │
                                      ▼
                   Review queue → engineering labels → promotion gate
                                      │
                                      ▼
                    Power BI ML pages (import only after sign-off)
```

---

## 3. Prerequisite (blocking, do before any model work)

### 3.0 Leakage-safe label replay
The current `silver.fact_energy_consumption_validated` cleaning logic (isolated-low/high-point removal) inspects the *following* reading — which a real forecast at issue-time would not have available yet. Before Model 2 or Model 3 can be trusted:

- Re-implement the cleaning rule (§6.7 of the pipeline doc — already fully specified) as a **point-in-time replay function**: given only data up to timestamp *t*, what would the validated kWh have been?
- Re-run `daily_consumption_profile.csv` generation through this replay instead of the current (retrospective) Gold view, for training/eval use only. Gold itself is untouched.
- Effort: ~3–5 days, pure engineering, no modeling. This is the single highest-leverage task in the whole plan — every downstream metric depends on it.

---

## 4. The three models

### Model 1 — Raw-grain anomaly detector (SPC + rules)

| | |
|---|---|
| **Replaces** | Isolation Forest on daily aggregates (old Model 3) |
| **Grain** | 5-minute, per meter × phase |
| **Type** | Statistical process control (CUSUM/EWMA) + reuse of existing classifiers, not a black-box learned model |
| **Inputs** | `active_power_kw`, `power_factor`, `current`, existing `status_*` flags (Major Issue/Major Problem, PF Critical, negative TkW) from `gold.energy_raw` |
| **Output** | `anomaly_events`: meter, phase, timestamp, event type, severity, evidence window |
| **Pretrained or trained?** | **Neither, strictly speaking — it's fit, not trained.** EWMA/CUSUM control limits are calibrated per meter×phase from historical mean/variance (a statistics step, seconds of compute, not a training loop). No pretrained model exists or is applicable — this is facility-specific electrical behavior; nothing in the open-source/foundation-model space encodes it. |
| **Why not a learned model here** | This is exactly the kind of pattern the Assessment Report already found by hand (ZN.20-PB.1, ZN.12-PB) using simple per-phase rate comparisons. A rule/SPC layer reproduces that reasoning automatically, stays fully explainable to engineering, and needs no labeled anomalies to start — critical since you currently have **zero confirmed-fault labels** except ZN.16-PB. |
| **Retraining cadence** | Recalibrate control limits monthly, or after any confirmed engineering fault (limits should reset once a known-faulty period is excluded from the baseline). |
| **Promotion gate** | Compare flagged events against the 4 already-known candidate meters (ZN.16, ZN.5, ZN.8.2, ZN.12-PB) as a sanity check — the detector should surface all 4 without being told about them. |

### Model 2 — Global pooled forecaster (quantile regression)

| | |
|---|---|
| **Replaces** | Per-meter Random Forest + HistGB (old Models 1 & 2) |
| **Grain** | Daily, all 29 validated-consumption meters in **one model**, `meter_id`/`zone_id` as categorical features |
| **Algorithm** | LightGBM or HistGradientBoosting with quantile loss (predict P10/P50/P90, not just a point) |
| **Features** | Existing lag/rolling/calendar set (t-1, t-7, t-14, 7-day mean/std, weekday, Fri/Sat flag, day-of-year) **plus** meter static covariates (breaker rating, zone) **plus**, once available, weather (temperature) and any production/occupancy calendar — see §5 |
| **Output** | Per meter/day: P10, P50, P90 forecast. Anomaly signal = actual outside [P10, P90]. |
| **Pretrained or trained?** | **Must be trained on this facility's data — no viable pretrained option for the core forecast.** This is short, sparse, facility-specific daily consumption (~4,260 usable rows total across 29 meters); nothing generic transfers well to a single building's idiosyncratic load pattern. **Optional comparison, not a replacement:** zero-shot time-series foundation models (e.g., Chronos, TimesFM, Moirai) can be run *pretrained, no training*, as an extra baseline column in the same backtest — cheap to try (inference only, no GPU training), and if one beats both the naive baseline and the trained LightGBM out of the box, that's valuable information. Expect it to land between the naive baseline and a well-tuned trained model, not ahead of both — but it's worth the half-day to check rather than assume. |
| **Training cadence** | Weekly retrain, daily inference. Daily retrain is not justified at this data volume. |
| **Promotion gate (per meter)** | Model must beat the previous-day baseline by a material margin (e.g., ≥2 percentage points WAPE) on the **leakage-safe** final test window, evaluated per meter, not just in aggregate — this is the gate the old experiment lacked, and it's the reason the old per-meter selection "improved" nothing. Where the model doesn't clear the bar for a given meter, that meter's production forecast stays on the naive baseline. |

### Model 3 — Daily-aggregate triage (Isolation Forest, kept but demoted)

| | |
|---|---|
| **Role** | Coarse secondary screen only — not the primary anomaly source anymore (Model 1 is) |
| **Grain** | Daily, per meter |
| **Inputs** | Aggregated *counts* of quality-flag events per meter/day (Major Issue count, Major Problem count, PF Critical count, negative-TkW count) — not raw kWh, which is what it wrongly used before |
| **Output** | A daily "how unusual was this meter's electrical behavior overall" score, used to prioritize which of Model 1's raw events get reviewed first |
| **Pretrained or trained?** | **Trained**, unsupervised, on this facility's own daily aggregates — Isolation Forest has no meaningful pretrained variant; it fits a tree structure to the specific feature distribution it's given, so it must be re-fit here. Training cost is trivial (seconds, CPU only). |
| **Retraining cadence** | Weekly, alongside Model 2, on a rolling window (e.g., trailing 6 months) so it adapts as behavior legitimately drifts, rather than a single static historical fit. |
| **Promotion gate** | None required to run (it's advisory triage, not a decision-making output) — but its top-N flagged days should be cross-checked against Model 1's raw events for agreement before it's trusted as a ranking signal. |

---

## 5. Exogenous data (Tier 2, parallel workstream)

Not a model — a data-acquisition task that materially raises the ceiling for Model 2:
- Weather (temperature/humidity) for the facility's location — public API or existing zone metadata if available.
- Any production/occupancy/shift calendar — this is the most likely explanation for the weekend-higher-than-weekday finding in the EDA, and cheap to test once available.
- These join into the daily feature table as ordinary columns; no new model needed, just extend Model 2's feature set and re-run the promotion gate.

---

## 6. Sequencing and effort estimate

| Phase | Work | Depends on | Rough effort |
|---|---|---|---|
| 0 | Leakage-safe daily replay (§3.0) | Nothing — start immediately | 3–5 days |
| 1 | Model 1 (SPC/rules on raw grain) | Nothing — independent of Phase 0 | 3–5 days |
| 2 | Model 2 (pooled quantile forecaster) + per-meter promotion gate | Phase 0 | 4–6 days |
| 3 | Model 3 (triage IF on flag counts) | Phase 0 | 1–2 days |
| 4 | Exogenous features (weather/calendar) into Model 2 | Phase 2, data availability | 3–5 days (mostly data sourcing) |
| 5 | Optional: pretrained foundation-model comparison for Model 2 | Phase 2 | 0.5–1 day |
| 6 | Engineering review + labeling of Model 1/3 outputs | Phase 1, 3 | Ongoing, owned by engineering not ML |
| 7 | Promotion to Power BI (import only, versioned tables) | All gates cleared | 2–3 days |

Phases 0 and 1 can run in parallel and should start first — they unblock everything else and require no new data sources.

---

## 7. What "pretrained vs. trained" comes down to, in one line each

- **Model 1 (SPC/rules):** neither — it's calibrated from statistics, not trained or pretrained; no generic model applies to this facility's wiring.
- **Model 2 (forecaster):** must be trained on SADINhub's own data; a pretrained foundation time-series model can be added as a free extra baseline in the same backtest, but shouldn't be assumed to win.
- **Model 3 (triage):** must be trained (fit) on this facility's own flag-count distribution; no pretrained variant exists for Isolation Forest by nature of the algorithm.

**Net implication:** there is no shortcut around training here — this is a single facility with idiosyncratic behavior and a short history. The value in this plan comes from fixing *what* gets trained on (pooled, leakage-safe, quality-flag-aware) rather than from finding something that doesn't need training at all.
