# SADINhub database — recovered SQL

The SQL that builds `sadinhub` (bronze → silver → gold), recovered from the
running PostgreSQL 18.4 server on 2026-09-08 after the original scripts were
lost. 3.1 MB of SQL, ready to commit.

Rebuild or refresh it at any time:

```bash
python export_database.py
```

Read-only throughout — the connection sets `default_transaction_read_only` and
verifies it before any query runs. No password is stored; you are prompted, or
set `SADINHUB_PASSWORD` in your environment.

---

## Why this was recoverable

PostgreSQL keeps the **source text** of every view, materialised view, function
and trigger in its own catalog, so those came back in full. Table, index and
constraint definitions came from `pg_dump`, which is authoritative.

What is *not* stored anywhere is a one-off script — a `CREATE TABLE AS` or
`INSERT INTO ... SELECT` run once in a query window. Those were recovered from a
second source: the **PostgreSQL server logs**. `log_statement` is `none` on this
server, so only statements that raised an error were written to the log — but
most of those errors are `canceling statement due to user request`, meaning a
slow query was cancelled, not that it was wrong. Several of your build scripts
were long-running, got cancelled at least once, and were captured as a result.

The log copies are better than the catalog copies: they keep your original
comments, named constants and layout, which PostgreSQL reformats away.

pgAdmin's query history was a third source, but it retains only the last 20
queries per database, so the August build work had already rotated out. What
survived is 49 exploratory queries, kept for reference.

---

## What is here

| Folder | Contents | Count |
|---|---|---|
| `01_bronze/functions` | source-system functions and procedures | 29 |
| `01_bronze/triggers` | source-system triggers | 7 |
| `02_silver/landing_views` | one view per bronze table | 107 |
| `02_silver/staging_views` | the real transformation layer | 8 |
| `02_silver/views` | `fact_energy_readings_flagged` | 1 |
| `02_silver/materialized_views` | data-quality staging | 3 |
| `02_silver/classify_functions` | `classify_*`, `status_rank`, `worst_status` | 21 |
| `03_gold/views` | the presentation layer | 10 |
| `04_reference_data` | rows of tables no view can rebuild | 3 |
| `05_recovered_history/original_ddl` | build scripts recovered from the logs | 13 |
| `05_recovered_history/analysis_queries` | your EDA queries, recovered | 122 |
| `pg_dump` | full and per-schema schema dumps | 4 |

`INVENTORY.md` lists every object with row counts and sizes.
`APPLY_ORDER.sql` lists the views in dependency order.

To restore the structure into an empty database, use `pg_dump/schema_full.sql` —
it already handles ordering. The per-object files are for reading, reviewing and
diffing in git.

---

## The pipeline

```
bronze  107 tables, the source application (originally the database "ssbms",
        renamed to bronze on 2026-07-23)
   |
   |  silver/landing_views  — one view per bronze table, no logic
   v
silver  fact_energy_readings_staging   pivots raw telemetry key/value rows into
        (view)                         one row per reading with 32 measurements
   |
   |    fact_energy_readings_flagged   adds a quality status per measurement via
   |    (view)                         the silver.classify_* functions
   v
        fact_energy_readings_snapshot  materialised: staging measurements joined
        (table, 4.5M rows)             to flagged statuses
   |
   v
        fact_energy_consumption_validated   cumulative kWh turned into per-interval
        (table, 4.26M rows)                 consumption, with cleaning rules
   |
   |    agg_energy_30min → 1h → 4h → 1d → 3d → 1week → 1month  (cascading)
   v
gold    10 views — energy_consumption_validated is the one the ML model reads
```

`dim_meter_cb_rating` sits beside this: a hand-maintained table of breaker
ratings that every `classify_current_v2` call depends on. Its 31 rows are in
`04_reference_data`, because no view can rebuild them.

---

## Load scripts: what is recovered, and what is verified

Twelve tables in silver and gold are materialised and therefore need a load
script. Four were recovered from the logs:

| Table | Load script | Status |
|---|---|---|
| `silver.fact_energy_consumption_validated` | recovered | **verified exactly** |
| `silver.fact_energy_readings_snapshot` | recovered (2 versions) | **verified exactly** |
| `silver.agg_energy_3d` | recovered | not verified |
| `silver.dim_meter_cb_rating` | recovered | rows also exported |
| `silver.agg_energy_30min`, `1h`, `4h`, `1d`, `1week`, `1month` | **missing** | see below |
| `silver.data_quality_summary` | **missing** | 31 rows exported instead |
| `gold.energy_reading_gaps` | **missing** | 963 rows exported instead |

### "Verified" means checked, not assumed

A script found in a log is plausible, not proven — so the two that matter most
were re-run against the live database and compared row by row:

```bash
python verify_recovered_sql.py
```

For each script it strips the `CREATE TABLE ... AS` wrapper, runs the remaining
`SELECT`, and compares every logic column against the rows the table actually
holds. Result on the two largest meters, 327,859 rows each:

```
consumption   327,859 rows,  8 columns,  0 differences   VERIFIED
snapshot      327,859 rows, 10 columns,  0 differences   VERIFIED
```

The comparison is restricted to whole meters for speed, and that is exact rather
than approximate: every window clause in both scripts partitions by
`energy_meter_key`, so restricting to whole meters cannot change their results.
The script re-checks that property before it runs and refuses to proceed if it
ever stops holding.

`agg_energy_3d` is not verified because it is an *incremental* loader — it reads
a watermark from the table it is filling, so re-running it against a populated
table produces nothing to compare.

### The six missing aggregate loaders

`agg_energy_3d` is a complete, commented incremental loader: epoch-anchored
buckets, a `MAX(bucket_start_utc)` watermark, `ON CONFLICT ... DO NOTHING`, and
it reads from `agg_energy_1d`. The aggregates cascade
(`30min → 1h → 4h → 1d → 3d → 1week → 1month`), so this one file is the exact
pattern for the other six — the bucket width and the source table change, the
structure does not. Rewriting them from it is mechanical; nothing has to be
guessed at from scratch. The tables themselves are intact either way, so this is
a reproducibility gap, not a data loss.

`silver.agg_energy_5min` also appears in the recovered scripts. That table no
longer exists in the database, so it was an earlier design that was dropped.

---

## Business rules worth knowing

These were recovered with the consumption script and are worth reading before
anyone changes the pipeline — the ML forecasting work in `../ML_WORK` depends on
them:

- **Zone 13 is excluded from consumption entirely** (`meter_label LIKE 'ZN.13-%'`
  → `EXCLUDED_ZONE13`). This is why `ZN.13-PB.1` and `ZN.13-PB.2` are absent from
  validated kWh and from the forecasting model.
- **Two meters have installation/startup baselines.** `ZN.1-PB.1` before
  2024-12-10 17:16:15.655 and `ZN.4-PB.1` before 2024-12-10 21:46:39.010 are
  `STARTUP_EXCLUDED`; the reading at exactly that timestamp is the
  `STARTUP_BASELINE`.
- **Isolated meter glitches are ignored, not smoothed.** A single reading that
  dips below its neighbours (`ISOLATED_LOW_BAD`) or spikes above them
  (`ISOLATED_HIGH_BAD`) is dropped, and the reading after a spike is marked
  `HIGH_SPIKE_RECOVERY`. Any decrement that none of these rules explains becomes
  `UNRESOLVED_DECREMENT`, and a single such reading marks its whole meter
  `REVIEW_REQUIRED`.
- **A gap of 15 minutes or more is `LONG_GAP`**, below that `NORMAL_INTERVAL`.
  Observed range confirms it: normal intervals run 0.77–14.99 minutes, long gaps
  15.00–289,953 minutes.
- `validated_kwh_consumption = active_energy_cumulative_kwh − previous_valid_kwh`,
  which holds for 4,260,792 of 4,260,849 rows; the other 57 are the 29
  `FIRST_VALID_READING` and 28 `IGNORED_READING` rows, where it is NULL by design.

---

## Suggested repo layout

```
SADINhub/
  DATABASE/     this folder — the SQL that builds the warehouse
  ML_WORK/      the forecasting system
  reports/      the assessment, dictionary and EDA reports
```

Add a `.gitignore` for `pg_dump/*.sql` only if you consider the bronze schema
sensitive; it is the vendor application's structure, not your own work. Nothing
in this folder contains credentials.
