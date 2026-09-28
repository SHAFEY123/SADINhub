# SADINhub — ML Implementation Instructions V2 (Code-Level Detail)
**Purpose:** Follow-on to the Task Breakdown doc — this version adds concrete file structure, function signatures, SQL, and pseudocode so each task can be implemented without further design decisions.
**Safety boundary (unchanged):** read-only Postgres (`transaction_read_only = on`, `REPEATABLE READ`), all writes go to local files under `ML_WORK/`, nothing touches Bronze/Silver/Gold/Power BI.

---

## 0. Project structure

```
ML_WORK/
  .venv/
  config/
    db_config.yaml
    model1_config.yaml
    model2_config.yaml
    model3_config.yaml
  src/
    db.py                      # read-only connection helper
    labels/
      replay_spec.md
      replay.py                # Task 0
    model1_anomaly_raw/
      features.py
      detectors.py
      run_model1.py
    model2_forecaster/
      features.py
      train.py
      backtest.py
      run_model2.py
    model3_triage/
      features.py
      fit.py
      run_model3.py
    common/
      metrics.py                # WAPE, MAE, coverage calcs
      io.py                     # versioned CSV/Parquet + run_metadata.json writer
  tests/
    test_replay.py
    test_model1.py
    test_model2_leakage.py
    test_model3.py
  outputs/
    <run_timestamp>/
      run_metadata.json
      *.csv
  ml_outputs_v2/                # final versioned artifacts, mirrors old ml_outputs/
```

Every `run_*.py` script writes to a fresh timestamped folder under `outputs/` and only promotes to `ml_outputs_v2/` after DoD checks pass — mirrors the discipline already used in `ml_outputs/experiment_20260907_v1`.

---

## 1. `src/db.py` — shared read-only connection (build once, reuse everywhere)

```python
import psycopg
from contextlib import contextmanager

@contextmanager
def readonly_connection(dsn: str, statement_timeout_ms: int = 120_000):
    conn = psycopg.connect(dsn, connect_timeout=10)
    conn.execute("SET SESSION CHARACTERISTICS AS TRANSACTION READ ONLY")
    conn.execute("SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL REPEATABLE READ")
    conn.execute(f"SET statement_timeout = {statement_timeout_ms}")
    ro = conn.execute("SHOW transaction_read_only").fetchone()[0]
    assert ro == "on", "Refusing to proceed: connection is not verified read-only"
    try:
        yield conn
    finally:
        conn.close()
```
Every task's script imports this. No credentials in source — read from env var or runtime prompt, matching current practice.

---

## TASK 0 — `src/labels/replay.py`

### 0.1 Pull the exact rule (do this first, by hand, into `replay_spec.md`)
Copy the rule order from pipeline doc §6.7 verbatim:
1. Exclude ZN.13-PB.1 / ZN.13-PB.2.
2. ZN.1-PB.1: ignore reads before 2024-12-10 17:16:15.655 UTC, baseline 46.5 kWh.
3. ZN.4-PB.1: ignore reads before 2024-12-10 21:46:39.010 UTC, baseline 150.4 kWh.
4. Isolated-low-point exclusion (dips then recovers ≥ prior level).
5. Isolated-high-spike exclusion (spikes then recovers to ≥ prior level).
6. Build valid-reading sequence.
7. `delta = current_valid_kwh - preceding_valid_kwh`.
8. Flat counter → 0 kWh.
9. Remaining negative delta → not counted.
10. `interval_quality = LONG_GAP` if gap ≥ 15 min else `NORMAL_INTERVAL`.

### 0.2 Function signature
```python
def replay_validated_kwh(
    readings: pd.DataFrame,   # columns: reading_timestamp_utc, active_energy_cumulative_kwh
    meter_id: str,
    as_of_timestamp: pd.Timestamp,
) -> pd.DataFrame:
    """
    Returns interval-level validated kWh using ONLY readings with
    reading_timestamp_utc <= as_of_timestamp. Isolated-point detection
    must not use any reading with timestamp > as_of_timestamp.
    Output columns: reading_timestamp_utc, validated_kwh, interval_quality, label_source='replay'
    """
```

**Key implementation constraint:** the isolated-point rules (steps 4–5) normally compare reading *i* against reading *i+1*. In the replay, reading *i+1* is only usable if `timestamp(i+1) <= as_of_timestamp`. For the most recent reading in any given `as_of` cut, there is no future point available — treat it as **not yet confirmed** (carry it forward unflagged rather than excluded) and only resolve it once a later reading becomes available in a subsequent `as_of` pass. This is the correct real-time behavior and the main behavioral difference from the retrospective Gold logic.

### 0.3 Validation script
```python
def test_replay_matches_gold_on_untouched_days():
    # For 5 sample meters, 30 days each, where no isolated-point correction applies:
    # replay output must equal gold.energy_consumption_validated exactly.
    ...

def test_replay_never_uses_future_rows():
    # Assert no row with timestamp > as_of_timestamp is read inside replay_validated_kwh.
    ...
```

### 0.4 Batch driver — `run_replay_batch.py`
```python
# For each meter, for each calendar day D in history:
#   as_of = end-of-day D (Saudi local, converted to UTC)
#   call replay_validated_kwh(..., as_of_timestamp=as_of)
#   append to daily_consumption_profile_v2.csv
# Also compute: % of rows where replay_kwh != gold_kwh (retrospective) -> log to run_metadata_v2.json
```

### DoD (unchanged from Task Breakdown, now with file targets)
- [ ] `src/labels/replay_spec.md` signed off
- [ ] `tests/test_replay.py` passes (both tests above)
- [ ] `outputs/<ts>/daily_consumption_profile_v2.csv` produced
- [ ] `run_metadata_v2.json` contains `pct_rows_replay_differs_from_retrospective`

---

## TASK 1 — `src/model1_anomaly_raw/`

### 1.1 `features.py` — pull scope
```sql
-- one query per meter, or one batched query with meter_id in results
SELECT
  energy_meter_key,
  reading_timestamp_utc,
  active_power_kw1, active_power_kw2, active_power_kw3,
  power_factor_1, power_factor_2, power_factor_3,
  current_amp1, current_amp2, current_amp3,
  status_amp1, status_amp2, status_amp3,
  status_pf1, status_pf2, status_pf3
FROM gold.energy_raw
ORDER BY energy_meter_key, reading_timestamp_utc;
```
Confirm `SELECT count(*)` returns 4,535,918 before proceeding — hard assert in code, not just a manual check.

### 1.2 `detectors.py` — baseline + EWMA/CUSUM
```python
def rolling_baseline(series: pd.Series, window_days: int = 30, exclude_windows: list[tuple] = None):
    """exclude_windows: [(start_ts, end_ts), ...] for known-faulty periods (e.g. ZN.16-PB full history)
       Returns rolling mean/std with those windows masked out of the baseline calc."""

def ewma_flags(series: pd.Series, baseline_mean, baseline_std, lam=0.2, k=3.0) -> pd.Series:
    """Standard EWMA control chart. Flag where |ewma - mean| > k * std_ewma."""

def cusum_flags(series: pd.Series, target, k=0.5, h=5.0) -> pd.Series:
    """Two-sided CUSUM for sustained drift, not single-point noise. k=slack, h=decision threshold in std units."""
```

### 1.3 `run_model1.py` — orchestration
```
for meter in all_31_meters:
    for phase in [1, 2, 3]:
        baseline = rolling_baseline(kw[meter][phase], exclude_windows=known_fault_windows.get(meter))
        ewma_events = ewma_flags(kw[meter][phase], *baseline)
        cusum_events = cusum_flags(pf[meter][phase], target=0.8)
        collapse consecutive flagged rows into episodes
        attach concurrent status_amp/status_pf value at event midpoint
        append to anomaly_events
```

### 1.4 Acceptance test — hardcode the 6 known findings and assert detection
```python
KNOWN_FINDINGS = {
    "ZN.16-PB": {"phases": [1, 2, 3]},
    "ZN.5-PB": {"phases": [1, 3]},
    "ZN.8-PB.2": {"phases": [1]},
    "ZN.12-PB": {"phases": [3]},
    "ZN.20-PB.1": {"phases": [1, 3]},
    "ZN.10-PB.2": {"phases": [3]},
}
def test_known_findings_are_detected(anomaly_events_df):
    for meter, spec in KNOWN_FINDINGS.items():
        for phase in spec["phases"]:
            assert ((anomaly_events_df.meter_id == meter) &
                    (anomaly_events_df.phase == phase)).any(), f"MISSED {meter} phase {phase}"
```
If this fails for any meter/phase, tune `k`/`h`/window before moving on — this test is the gate, not optional.

### 1.5 Output formatting — human-readable description generator
```python
def describe_event(row) -> str:
    return (f"{row.meter_id} Phase {row.phase}: {row.metric} "
            f"{row.detector} flag from {row.event_start} to {row.event_end} "
            f"({row.duration_days:.1f} days), concurrent status={row.concurrent_status_flag}")
```

### DoD — file targets
- [ ] `outputs/<ts>/anomaly_events.parquet`
- [ ] `outputs/<ts>/anomaly_review_raw.csv` (with `description` column from 1.5)
- [ ] `config/model1_config.yaml` with all thresholds (`ewma_lambda`, `ewma_k`, `cusum_k`, `cusum_h`, `baseline_window_days`, `exclude_windows`)
- [ ] `tests/test_model1.py::test_known_findings_are_detected` passes for all 6 meters

---

## TASK 2 — `src/model2_forecaster/`

### 2.1 `features.py` — pooled feature table
```python
def build_feature_table(daily_profile: pd.DataFrame, meter_dim: pd.DataFrame) -> pd.DataFrame:
    """
    daily_profile: output of Task 0 (daily_consumption_profile_v2.csv), post quality-screen filter
    meter_dim: energy_meter_key, zone_id, breaker_rating (from silver.dim_meter_cb_rating)
    Returns one flat table, ALL 29 meters together:
      meter_id, zone_id, breaker_rating,
      lag_1, lag_7, lag_14, roll_mean_7, roll_std_7,
      weekday, is_weekend_fri_sat, day_of_year,
      target = next_day_kwh
    """
```
Reuse the existing quality-screen predicate unchanged (95–100% normal-interval coverage, not boundary/long-gap-touched, no negative/duplicate/overlap evidence) — this logic already exists in `02_prepare_daily_data.py`, port it as-is.

### 2.2 Leakage tests — port existing tests, add one
```python
# Reuse from test_ml_experiment.py: future-value isolation, missing-day handling, quality masking
def test_no_future_row_used_in_lag_features(): ...
def test_pooled_table_has_no_row_overlap_across_splits():
    # train/val/test date ranges must not overlap for ANY meter
```

### 2.3 `train.py` — pooled quantile model
```python
import lightgbm as lgb

def train_quantile_models(train_df, cat_features=["meter_id", "zone_id"]):
    models = {}
    for q in [0.1, 0.5, 0.9]:
        models[q] = lgb.LGBMRegressor(
            objective="quantile", alpha=q,
            n_estimators=500, learning_rate=0.03,
            num_leaves=31, min_child_samples=30,   # conservative, data-sparse regularization
        ).fit(train_df[FEATURES], train_df["target"],
              categorical_feature=cat_features)
    return models  # one dict, ALL 29 meters share these 3 models
```

### 2.4 `backtest.py` — chronological windows (same dates as before)
```python
WINDOWS = {
    "val1": ("2026-01-12", "2026-03-12"),
    "val2": ("2026-03-13", "2026-05-11"),
    "final_test": ("2026-05-12", "2026-07-10"),
}
# train only on rows strictly before each window's start date
# score val1, val2 for model comparison; final_test used once, not for selection
```

### 2.5 Promotion gate — mechanical, per meter
```python
def apply_promotion_gate(metrics_by_meter: pd.DataFrame, margin_pp: float = 2.0) -> pd.DataFrame:
    """
    metrics_by_meter: meter_id, model_wape, baseline_wape (previous-day, on final_test)
    Returns: meter_id, chosen_method ('model' if baseline_wape - model_wape >= margin_pp else 'baseline')
    No manual override column — this is intentional.
    """
    metrics_by_meter["chosen_method"] = np.where(
        metrics_by_meter.baseline_wape - metrics_by_meter.model_wape >= margin_pp,
        "pooled_model", "previous_day_baseline"
    )
    return metrics_by_meter
```

### 2.6 Optional — zero-shot foundation model column (half-day, non-blocking)
```python
# e.g. Chronos via HuggingFace pipeline, inference only, no .fit() call
# from chronos import ChronosPipeline
# pipeline = ChronosPipeline.from_pretrained("amazon/chronos-t5-small")
# forecast = pipeline.predict(context=historical_series, prediction_length=1)
# Add as an extra column in forecast_backtest_v2.csv: method='chronos_zeroshot'
```

### DoD — file targets
- [ ] `outputs/<ts>/forecast_backtest_v2.csv` (meter, date, method, p10, p50, p90, actual)
- [ ] `outputs/<ts>/metrics_by_meter_v2.csv`
- [ ] `outputs/<ts>/model_selection_v2.csv` (from 2.5, no manual edits)
- [ ] `outputs/<ts>/run_metadata_v2.json` (input hash, LightGBM version, hyperparams, window dates)
- [ ] One-page `results_summary_v2.md`: "X of 29 meters cleared the promotion gate, average margin Ypp"

---

## TASK 3 — `src/model3_triage/`

### 3.1 `features.py`
```python
def build_daily_flag_counts(gold_energy_raw: pd.DataFrame) -> pd.DataFrame:
    """
    Group gold.energy_raw by (meter_id, saudi_date), count:
      major_issue_count, major_problem_count,
      pf_critical_count_p1/p2/p3, negative_tkw_count
    """
```

### 3.2 `fit.py`
```python
from sklearn.ensemble import IsolationForest

def fit_rolling_triage(flag_counts_df, window_days=180, contamination=0.02):
    # refit on trailing window_days of data each call — not a single static historical fit
    model = IsolationForest(contamination=contamination, random_state=42)
    model.fit(flag_counts_df[FLAG_FEATURES])
    return model
```

### 3.3 Cross-check against Task 1
```python
def compute_overlap_rate(triage_top_n: pd.DataFrame, anomaly_events: pd.DataFrame) -> float:
    # for each (meter, date) in triage_top_n, check if anomaly_events has an event
    # for that meter overlapping that date
    # return fraction with a match — this is the acceptance metric, not ground-truth precision
```

### DoD — file targets
- [ ] `outputs/<ts>/anomaly_review_triage.csv` (top-50, ranked)
- [ ] Overlap rate vs. Task 1 computed and printed in `results_summary_v2.md`
- [ ] `config/model3_config.yaml` (window_days, contamination)

---

## TASK 4 — Review loop
```python
def build_combined_review_queue(anomaly_review_raw, anomaly_review_triage) -> pd.DataFrame:
    combined = pd.concat([anomaly_review_raw.assign(source="model1_raw"),
                           anomaly_review_triage.assign(source="model3_triage")])
    combined["confirmed_fault"] = ""   # blank for engineering to fill
    combined["notes"] = ""
    return combined.sort_values(["severity"], ascending=False)
```
Deliver as `review_queue_v1.xlsx` (not CSV — engineering will edit it directly; xlsx avoids CSV-encoding round-trip issues). Once ≥20 rows come back labeled, compute precision for Model 1 and feed confirmed-fault windows into `model1_config.yaml`'s `exclude_windows`.

---

## Run order (concrete commands)

```bash
# Phase 0 (blocking)
python src/labels/run_replay_batch.py --output outputs/$(date +%s)/

# Phase 1 (parallel with Phase 0)
python src/model1_anomaly_raw/run_model1.py --output outputs/$(date +%s)/

# Phase 2 (after Phase 0)
python src/model2_forecaster/run_model2.py --daily-profile outputs/<task0_ts>/daily_consumption_profile_v2.csv

# Phase 3 (after Phase 0, benefits from Phase 1)
python src/model3_triage/run_model3.py --daily-profile outputs/<task0_ts>/... --anomaly-events outputs/<task1_ts>/anomaly_events.parquet

# Phase 4
python src/common/build_review_queue.py --model1 outputs/<t1>/anomaly_review_raw.csv --model3 outputs/<t3>/anomaly_review_triage.csv
```

Every script writes `run_metadata.json` on completion — promote a run to `ml_outputs_v2/` only after its DoD checklist is manually confirmed by the task owner.
