# Task 0A — leakage-safe replay specification

**Status:** implemented. Input contract and reconstructions approved 2026-09-18.
**Authority:** the live table `silver.fact_energy_consumption_validated` (exposed as
`gold.energy_consumption_validated`). Pipeline §6.7 is the prose description of it. The
recovered draft SQL in `DATABASE/05_recovered_history/` is a cancelled log artifact and is
**not** authoritative — the live build does not implement three of its branches.

---

## 1. Input contract

**Replay input — source columns only.**

| Object | Columns |
|---|---|
| `gold.energy_raw` | `energy_meter_key`, `reading_timestamp_utc`, `active_energy_cumulative_kwh` |
| `gold.meter` | `energy_meter_key` → `meter_label` |

**Scope filter:** `meter_label NOT LIKE 'ZN.13-%'` (rule 1).

Verified row identity: 4,535,918 raw − 275,069 Zone 13 = **4,260,849**, with 0 NULL
cumulative-kWh rows.

**Comparison target — opened only after the replay has finished.**
`gold.energy_consumption_validated` → `validated_kwh_consumption`, `interval_quality`,
`gap_minutes`, `consumption_cleaning_status`.

Everything else is derived in code and never read: `previous_valid_timestamp`,
`previous_valid_kwh`, `validated_kwh_consumption`, `consumption_cleaning_status`,
`interval_quality`, `gap_minutes`, `reading_timestamp_saudi`, `reading_date_saudi`.

---

## 2. Classification rules, in evaluation order

Per meter, readings ordered by `reading_timestamp_utc`. `prev` = reading i−1, `next` = i+1.

| # | Condition | `consumption_cleaning_status` |
|---|---|---|
| 1 | `meter_label LIKE 'ZN.13-%'` | out of scope — row not emitted |
| 2 | `active_energy_cumulative_kwh IS NULL` | `MISSING_KWH` (0 rows live) |
| 3 | `ZN.1-PB.1` and `ts < 2024-12-10 17:16:15.655` | `STARTUP_EXCLUDED` |
| 4 | `ZN.4-PB.1` and `ts < 2024-12-10 21:46:39.010` | `STARTUP_EXCLUDED` |
| 5 | prev and next exist, `kwh < prev`, `next >= prev` | `ISOLATED_LOW_BAD` |
| 6 | prev and next exist, `kwh > prev`, `kwh > next`, `next >= prev` | `ISOLATED_HIGH_BAD` |
| 7 | otherwise | `KEEP` |

Rules 3 and 4 use **strict `<`**, so the reading at exactly the cutoff timestamp falls
through to `KEEP`. This is verified against the live table: ZN.1-PB.1 at 46.5 kWh and
ZN.4-PB.1 at 150.4 kWh both read `KEEP`, and the live table has zero `STARTUP_BASELINE`
rows. The 46.5 / 150.4 values are consequences of the timestamp predicates, not predicates
themselves.

There is **no** `HIGH_SPIKE_RECOVERY` and **no** `UNRESOLVED_DECREMENT` branch: both are
absent from the live table. A decrement that no rule explains stays `KEEP` and is handled
by the delta step below, which yields NULL consumption for it.

## 3. Valid sequence and deltas

Valid sequence = rows with `consumption_cleaning_status = 'KEEP'`. Over that subsequence:

```
previous_valid_timestamp = LAG(reading_timestamp_utc)
previous_valid_kwh       = LAG(active_energy_cumulative_kwh)
gap_minutes              = ROUND((ts - previous_valid_timestamp) seconds / 60, 2)

validated_kwh_consumption =
    NULL                      if previous_valid_kwh IS NULL
    kwh - previous_valid_kwh  if kwh >= previous_valid_kwh
    NULL                      otherwise            -- unexplained decrement
```

## 4. `interval_quality`

```
IGNORED_READING      if status in (ISOLATED_LOW_BAD, ISOLATED_HIGH_BAD,
                                  STARTUP_EXCLUDED, MISSING_KWH)
FIRST_VALID_READING  elif previous_valid_timestamp IS NULL
LONG_GAP             elif gap_minutes >= 15
NORMAL_INTERVAL      otherwise
```

## 5. Point-in-time semantics — the actual subject of Task 0A

Only rules 5 and 6 need `next`. Rules 2–4 need a constant or the row itself; the delta step
needs only earlier rows. So the replay is backward-safe except for the isolated-point pair.

At `as_of` = end of Saudi day D, reading *i* is **confirmable** when its successor exists and
falls on or before that cut. Otherwise the isolated-point rules cannot be evaluated and the
reading is carried forward unflagged as `KEEP` — Instructions V2 §0.2's "not yet confirmed"
behaviour — and re-resolved on a later pass.

Emitted per row:

- `provisional_at_own_day_close` — true when the successor is absent or falls on a later
  Saudi day, so the row was not confirmable at its own day's close.
- `as_of_confirmed_utc` — the UTC instant of the end of the Saudi day containing the
  successor; NULL when the meter has no later reading.
- `realtime_status` — the classification using only readings up to the end of the row's own
  Saudi day.
- `realtime_differs` — `realtime_status != consumption_cleaning_status`.

`pct_rows_replay_differs_from_retrospective` = 100 × mean(`realtime_differs`).

**Scope of that figure.** It measures exactly one mechanism: the upstream isolated-point
look-ahead in the §6.7 cleaning rule, evaluated for a forecast issued at the close of Saudi
day D. A result of 0% means the retrospective cleaning gave this history no information a
same-day-close replay could not also have had. It does **not** establish that any downstream
model is leakage-free — feature construction, lag alignment and train/test splits are
separate mechanisms with their own tests, owned by Task 2.

Saudi local time is UTC+3 with no DST, so the end of Saudi day D is `D 21:00:00 UTC` and the
day window is the half-open UTC interval `[D−1 21:00, D 21:00)`.

## 6. Output schema

One row per in-scope raw reading — **4,260,849 rows**, including the 57 rows that carry no
consumption (29 `FIRST_VALID_READING` + 28 `IGNORED_READING`). Task 0B needs the ignored
rows to identify boundary days and the long-gap rows to mark touched dates, and row-for-row
parity with the comparison target is otherwise impossible to state.

**17 columns = 12 gold-equivalent + 5 new.** Verified against the produced artifact, in
order:

| # | Column | Arrow type | Origin |
|---:|---|---|---|
| 1 | `energy_meter_key` | large_string | gold-equivalent |
| 2 | `meter_label` | large_string | gold-equivalent |
| 3 | `reading_timestamp_utc` | timestamp[ns] | gold-equivalent |
| 4 | `reading_timestamp_saudi` | timestamp[ns] | gold-equivalent (derived, UTC+3) |
| 5 | `reading_date_saudi` | timestamp[ns] | gold-equivalent (derived) |
| 6 | `active_energy_cumulative_kwh` | double | gold-equivalent (source) |
| 7 | `previous_valid_timestamp` | timestamp[ns] | gold-equivalent (derived) |
| 8 | `previous_valid_kwh` | double | gold-equivalent (derived) |
| 9 | `validated_kwh_consumption` | double, nullable | gold-equivalent (derived) |
| 10 | `gap_minutes` | double, nullable | gold-equivalent (derived, 2 dp) |
| 11 | `consumption_cleaning_status` | large_string | gold-equivalent (derived) |
| 12 | `interval_quality` | large_string | gold-equivalent (derived) |
| 13 | `realtime_status` | large_string | **new** — point-in-time |
| 14 | `realtime_differs` | bool | **new** — point-in-time |
| 15 | `provisional_at_own_day_close` | bool | **new** — point-in-time |
| 16 | `as_of_confirmed_utc` | timestamp[ns], nullable | **new** — point-in-time |
| 17 | `label_source` | large_string | **new** — constant `replay` |

Three Gold columns are deliberately **not** carried: `facility_key`, `zone_key` and
`grid_billing_account_key`. They are foreign keys, not replay inputs or outputs, and Task 0B
works per meter, so it needs none of them. Any task that wants them joins `gold.meter`.

### Reading `provisional_at_own_day_close`

It is a procedural state, not an anomaly. It marks the final reading of each meter-day,
which by definition has no later reading yet available to confirm whether it is an isolated
point. The expected count is therefore roughly one per meter-day (measured: 14,753, exactly
the number of meter-days with readings). **The result that matters is that none of them
changed classification once the next reading arrived** — see `realtime_differs`.

## 7. Definition of Done

- [ ] Emits exactly 4,260,849 rows over 29 meters.
- [ ] `interval_quality` distribution matches Gold exactly:
      4,259,917 / 875 / 29 / 28.
- [ ] `consumption_cleaning_status` distribution matches Gold exactly:
      4,260,821 KEEP / 22 ISOLATED_LOW_BAD / 5 STARTUP_EXCLUDED / 1 ISOLATED_HIGH_BAD.
- [ ] Total consumption = 2,020,697.5 kWh; LONG_GAP 354,242.5; NORMAL 1,666,455.0.
- [ ] Row-for-row equality with Gold on `validated_kwh_consumption` and `interval_quality`.
- [ ] All 23 forward-looking corrections reproduced individually.
- [ ] Strict point-in-time function proven never to read a row beyond `as_of`.
- [ ] Synthetic end-of-day spike test shows the documented provisional behaviour.
- [ ] `run_metadata.json` carries divergence and reconciliation results.

**Comparison caveat.** The equality test compares `validated_kwh_consumption` and
`interval_quality`. `consumption_cleaning_status` is compared separately and is expected to
agree on all rows against the live table — but it is the one field where the recovered draft
SQL would have differed (on 3 rows), so it is reported rather than asserted blindly.
