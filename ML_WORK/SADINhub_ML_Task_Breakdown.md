# SADINhub — ML Task Breakdown (Step-by-Step, per Model)
**Purpose:** Hand-off document. Each section is a self-contained work ticket: objective, inputs, exact steps, outputs, and a Definition of Done (DoD) a reviewer can check against.
**Rule for all tasks:** read-only Postgres access, write outputs to local files only (unchanged safety boundary from the current pipeline). Nothing here touches Bronze/Silver/Gold/Power BI.

---

## TASK 0 — Leakage-safe daily label replay
**Blocks:** Model 2 and Model 3. Start this first, independently of Task 1 (Model 1 has no dependency on this).
**Owner skill:** SQL + Python, familiarity with `silver.fact_energy_consumption_validated` logic.

### Steps
1. Pull the exact cleaning rule from the pipeline doc (§6.7, rule order items 1–10: Zone 13 exclusion, ZN.1/ZN.4 baseline cutoffs, isolated-low/high-point rules, LONG_GAP labeling). Do not reinterpret it — copy the rule order verbatim into a spec doc (`label_replay_spec.md`) and get one line of sign-off from whoever owns that Silver logic that the spec matches production.
2. Write `replay_validated_kwh(meter_id, as_of_timestamp)` in Python: given only readings with `reading_timestamp_utc <= as_of_timestamp`, reproduce the isolated-point exclusion and interval-consumption calculation using strictly backward-looking logic (no peeking at the next reading beyond `as_of_timestamp`).
3. Unit test it against 5 meters × 30 known days by comparing replay output to the actual `gold.energy_consumption_validated` value for days *not* touched by an isolated-point correction (these should match exactly — this proves the replay logic is faithful where it doesn't matter, before trusting it where it does).
4. Identify the subset of rows where replay output *differs* from the retrospective Gold value (these are exactly the rows affected by forward-looking cleaning). Log the count and % of total — this number itself is a useful finding to report back.
5. Re-run `02_prepare_daily_data.py`-equivalent logic using the replay function instead of `gold.energy_consumption_validated` directly, producing `daily_consumption_profile_v2.csv` with an added column `label_source = replay | retrospective` for transparency.
6. Store `run_metadata_v2.json` recording: input hash, replay spec version, row counts, % of rows where replay ≠ retrospective.

### Definition of Done
- [ ] `label_replay_spec.md` exists and is signed off.
- [ ] Unit tests pass for all 5 sampled meters on untouched days (exact match).
- [ ] `daily_consumption_profile_v2.csv` produced with `label_source` column.
- [ ] % of affected rows reported to the team (this number determines how much the old backtest numbers should be discounted).

---

## TASK 1 — Model 1: Raw-grain SPC / rule-based anomaly layer
**Blocks:** nothing — start immediately, in parallel with Task 0.
**Owner skill:** Python/pandas at raw 5-min grain, basic statistics (EWMA/CUSUM), SQL against `gold.energy_raw`.

### Objective
Detect abnormal per-meter, per-phase electrical behavior at the grain where it physically occurs (5-min), reusing the existing `status_*` flags as inputs, without requiring any labeled fault data.

### Steps
1. **Pull scope.** Query `gold.energy_raw` for all 31 meters, full history, columns: `active_power_kw{1,2,3}`, `power_factor{1,2,3}`, `current{1,2,3}`, `status_amp{1,2,3}`, `status_pf{1,2,3}`, plus timestamp and meter_id. Confirm row count matches 4,535,918 (sanity check against known volume).
2. **Build the per-meter×phase baseline.** For each (meter, phase) pair, compute a rolling 30-day mean and standard deviation of `active_power_kw` and `power_factor`, excluding any window already known to contain a confirmed fault (ZN.16-PB should be excluded from its own baseline calibration, or the control limits will be calibrated on faulty behavior).
3. **Implement two detectors per (meter, phase):**
   - EWMA control chart on `active_power_kw` — flag when the smoothed value crosses ±3σ of its own rolling baseline.
   - CUSUM on `power_factor` — flag sustained drift (not single-point noise) below the acceptable threshold, distinguishing "chronically low PF at low load" (not necessarily a fault) from "sudden sustained drop" (more suspicious).
4. **Fold in existing classifier flags as corroborating evidence, not the primary trigger.** For every EWMA/CUSUM flag, attach the concurrent `status_amp*`/`status_pf*` value — this lets the output distinguish "statistically unusual AND classifier-flagged" (high confidence) from "statistically unusual only" (lower confidence, worth a second look).
5. **Assemble `anomaly_events` table:** columns `meter_id, phase, event_start, event_end, metric, detector (ewma/cusum), severity, concurrent_status_flag, evidence_window_rows`. One row per contiguous flagged episode, not per reading (collapse consecutive flagged rows into one event).
6. **Sanity-check against known findings.** Run the detector across full history and confirm it independently surfaces: ZN.16-PB (all phases), ZN.5-PB (Phase 1 dominant + Phase 3), ZN.8-PB.2 (Phase 1), ZN.12-PB (Phase 3), ZN.20-PB.1 (Phase 1/3), ZN.10-PB.2 (Phase 3). If any of these are missed, tune thresholds before moving on — this is the acceptance test, not a nice-to-have.
7. **Produce a review-ready output:** `anomaly_review_raw.csv`, sorted by severity, with a short natural-language description per event (e.g., "ZN.12-PB Phase 3: PF sustained below 0.6 for 11 days, concurrent Major Problem flags") — engineering should be able to read this without touching code.
8. **Document thresholds and calibration window** in `model1_config.yaml` so the calibration is reproducible and auditable, not hardcoded magic numbers scattered in code.

### Definition of Done
- [ ] Detector runs end-to-end on full 4.5M-row history in a documented runtime (record it).
- [ ] All 6 known findings from the Assessment Report are independently reproduced by the detector (pass/fail per meter, documented).
- [ ] `anomaly_events` and `anomaly_review_raw.csv` produced with human-readable descriptions.
- [ ] `model1_config.yaml` checked in with calibration parameters and rationale.
- [ ] Zero writes to Postgres; only reads via existing read-only connection pattern.

---

## TASK 2 — Model 2: Global pooled quantile forecaster
**Blocks on:** Task 0 (needs `daily_consumption_profile_v2.csv`).
**Owner skill:** Python, LightGBM or scikit-learn HistGradientBoosting, time-series backtesting discipline.

### Steps
1. **Load `daily_consumption_profile_v2.csv`.** Confirm the same quality-screen rules as before (95–100% normal-interval coverage, no long-gap-touched days, etc. — reuse existing screen logic unchanged) are applied before this becomes the training table.
2. **Build the feature table, pooled across all 29 meters into one flat table** (not 29 separate tables): columns = `meter_id` (categorical), `zone_id` (categorical, from `gold.meter`/`gold.zone`), `breaker_rating` (from `silver.dim_meter_cb_rating`), `lag_1`, `lag_7`, `lag_14`, `roll_mean_7`, `roll_std_7`, `weekday`, `is_weekend_fri_sat`, `day_of_year`, `target = kwh_next_day`.
3. **Verify no future leakage in feature construction** — reuse the existing unit tests from `test_ml_experiment.py` (future-value isolation, missing-day handling) against the new pooled table; they should still apply almost unchanged.
4. **Define the chronological splits**, keeping the same dates as before for comparability: validation windows 12 Jan–12 Mar 2026 and 13 Mar–11 May 2026; final test 12 May–10 Jul 2026. Do not let any row from the final test window touch feature construction for earlier windows.
5. **Train one pooled LightGBM (or HistGB) model with quantile loss** at τ = 0.1, 0.5, 0.9, on all meters' training rows together, `meter_id`/`zone_id` as native categorical features (no one-hot needed if using LightGBM's categorical handling).
6. **Backtest against baselines** on the same eligible observations: previous-day, same-weekday-last-week, and the pooled model's P50. Compute WAPE **per meter**, not just aggregate.
7. **Apply the per-meter promotion gate:** for each of the 29 meters, keep the pooled model only if it beats the previous-day baseline's WAPE by ≥2 percentage points on the final test window; otherwise that meter's production forecast stays on the naive baseline. Record the per-meter decision in `model_selection_v2.csv` (meter_id, chosen_method, model_wape, baseline_wape, margin).
8. **(Optional, cheap) Add a zero-shot foundation-model column** (e.g., Chronos or TimesFM inference, no training) to the same backtest table purely for comparison — half a day of work, do not block on this.
9. **Produce outputs:** `forecast_backtest_v2.csv` (predictions + P10/P50/P90 + actuals by meter/date/method), `metrics_by_meter_v2.csv`, `model_selection_v2.csv`, `run_metadata_v2.json` (input hash, LightGBM version, hyperparameters, dates).
10. **Write a one-page results summary** stating in plain language: how many of 29 meters the pooled model actually beat the baseline for, and by how much — this is the number that determines whether Model 2 goes to production for any meter at all.

### Definition of Done
- [ ] One pooled model file trained (not 29 separate models).
- [ ] Leakage tests pass on the new feature table.
- [ ] Per-meter WAPE comparison against baseline completed and logged in `model_selection_v2.csv`.
- [ ] Promotion gate applied mechanically (no manual override) — a meter is only "model-selected" if it clears the ≥2pp margin on final test.
- [ ] Results summary written in plain language for non-ML stakeholders.

---

## TASK 3 — Model 3: Daily-aggregate triage (Isolation Forest)
**Blocks on:** Task 0 (needs `daily_consumption_profile_v2.csv`) and ideally Task 1 (for flag-count features).
**Owner skill:** Python, scikit-learn.

### Steps
1. **Build the daily flag-count feature table** per meter/day: count of Major Issue readings, count of Major Problem readings, count of PF Critical readings per phase, count of negative-TkW readings — aggregated from `gold.energy_raw` for that meter/day (not raw kWh — this is the fix versus the old version).
2. **Fit Isolation Forest** on a trailing 6-month rolling window per refresh (not a single static historical fit), contamination parameter kept at ~2% as before unless Task 1's findings suggest a different rate is more realistic.
3. **Score all meter/days**, rank by anomaly score, output top-N (start with N=50) as `anomaly_review_triage.csv`.
4. **Cross-check against Task 1's `anomaly_events`:** for each top-N triage day, check whether Model 1 flagged an event for that meter on that day. Report the overlap rate — this is the validation for Model 3, since there are no ground-truth labels yet.
5. **Package as a weekly-refresh script**, re-fit alongside Model 2's weekly retrain, so both stay on a consistent cadence.

### Definition of Done
- [ ] `anomaly_review_triage.csv` produced with top-N ranked days.
- [ ] Overlap rate against Model 1 events computed and reported (this is the acceptance signal, not accuracy against ground truth, which doesn't exist yet).
- [ ] Refresh script runs on a rolling 6-month window, documented cadence.

---

## TASK 4 — Engineering review loop (cross-cutting, after Tasks 1 & 3)
**Owner:** whoever owns engineering sign-off, not the ML engineer — but the ML engineer sets this up.

### Steps
1. Package Task 1's `anomaly_review_raw.csv` and Task 3's `anomaly_review_triage.csv` into one combined, prioritized queue (Task 1 events first, Task 3 as supporting context).
2. Add two blank columns for engineering to fill in: `confirmed_fault (Y/N/Unsure)` and `notes`.
3. Once even a small labeled sample comes back (target: at least 20 labeled events), compute precision for Model 1 and overlap-based validation for Model 3 — this is the first real ground-truth check either model will have had.
4. Feed confirmed faults back into Task 1's calibration (exclude confirmed-fault windows from baseline recalibration, per Task 1 Step 2).

### Definition of Done
- [ ] Combined review queue delivered to engineering.
- [ ] At least 20 labeled responses collected and precision computed.
- [ ] Feedback loop into Task 1 calibration documented.

---

## Suggested assignment if split across a small team
- **Task 0 (label replay):** most senior person — it's a correctness-critical, low-glamour task that everything else depends on.
- **Task 1 (raw-grain anomaly):** whoever is most comfortable with the existing classifier SQL and raw electrical domain — reuses Assessment Report reasoning directly.
- **Task 2 (forecaster):** whoever owns the existing `03_ml_experiment.py` — most of the harness (splits, tests, metadata) is reusable, the change is pooling + quantile loss + promotion gate.
- **Task 3 (triage):** can be done by the same person as Task 2, it's small.
- **Task 4:** ML engineer sets it up, but ownership of actually labeling sits with engineering, not ML.
