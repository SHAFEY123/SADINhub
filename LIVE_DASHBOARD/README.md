# SADINhub live dashboard

A dashboard that queries your database directly, so it can show **individual
readings** rather than pre-computed buckets, and so its numbers **match your
Power BI report by construction**.

## Run it

```bat
cd "<path-to-repo>\LIVE_DASHBOARD"
"..\ML_WORK\.venv\Scripts\python.exe" serve.py
```

Then open <http://localhost:8770>. Stop with Ctrl-C.

It uses the `ML_WORK` venv because that is the interpreter with `psycopg`
installed. The connection is forced `default_transaction_read_only = on` and
verified before any query runs, so the server cannot modify the warehouse.

Startup resolves the 31-meter dimension cache and two exact row counts, which
takes a few seconds; after that the UI is responsive.

---

## What changed, and why the numbers now match

The previous build computed consumption itself, with its own rule
(`LAG()` delta, a 15-minute gap cap, a breaker-derived plausibility gate).
That was the mistake. **Your gold layer already computes consumption**, and
your Power BI simply sums the result:

```sql
SELECT sum(validated_kwh_consumption) FROM gold.energy_consumption_validated;
--  2020697.5
```

This dashboard uses that same column, unfiltered. The headline figure is
therefore **2,020,697.5 kWh**, identical to your report, because it is
literally the same arithmetic on the same column rather than a reconstruction
that happens to land nearby.

Its composition, shown on the Overview page as a ledger:

| interval_quality | kWh | meaning |
|---|---:|---|
| `NORMAL_INTERVAL` | 1,666,455.0 | reading followed its predecessor within cadence |
| `LONG_GAP` | 354,242.5 | meter was away; the register still moved |
| **Total** | **2,020,697.5** | what your Power BI reports |

Your gold layer keeps long-gap energy in the total, so this dashboard keeps it
too. It is shown as a separate stack in the daily chart rather than hidden.

---

## Your logic, not mine

Every threshold comes from your own `silver.classify_*_v2` functions rather
than from anything I chose:

| Signal | Acceptable | Review Required | Problematic | Critical |
|---|---|---|---|---|
| Voltage neutral | 215–245 V | 209.94–215, 245–250.06 | 207–209.94, 250.06–253 | <207 or >253 |
| Voltage line | 380–420 V | 371.2–380, 420–428.8 | 360–371.2, 428.8–440 | <360 or >440 |
| Power factor | 0.80–1.00 | 0.78–0.80 | 0.60–0.78 | <0.6 or >1 |
| Frequency | 59.3–60.5 Hz | — | 59–59.3, 60.5–61 | <59 or >61 |
| Current | within 15% margin of CB | outer third | remaining | <0 or >CB rating |
| Accumulated energy | — | — | — | `Invalid` on NULL or decrement |

Note the PF threshold is **0.80**, which is what your classifier uses. The
earlier build used 0.85 (the Saudi tariff penalty point) and so disagreed with
your report.

`overall_status` is `silver.worst_status` across Vn1-3, VL1-3, Hz, PF1-3, PFa
and kWh — ranked by `silver.status_rank`
(Acceptable 1 → Review 2 → Anomaly 3 → Problematic 4 → Critical 5 → Invalid 6).
It **excludes the three current channels by design**, which is why per-phase
current status is reported separately instead of being folded in.

---

## Pages

| # | Page | What it answers |
|---|---|---|
| 01 | Overview | Consumption as your gold layer computes it, every zone, monthly totals |
| 02 | Energy & Demand | Power per reading, and both cumulative registers |
| 03 | Current | L1/L2/L3 per reading, phase balance against each meter's CB rating |
| 04 | Voltage & Frequency | Phase-neutral **and line-to-line**, frequency per reading |
| 05 | Power Factor | PF1/PF2/PF3/PFa per reading, negatives included, distribution |
| 06 | Readings | Every individual reading, 26 columns, paginated and filterable |
| 07 | Data & Status | Every `status_*` column, signal availability, NULL vs zero |
| 08 | Bill Check | `gold.energy_bill` invoice against metered consumption |

Filters apply to every page: zone (multi-select), meter, date range, five period
presets, and a **time-of-day window** for narrowing to specific reading times.

---

## API

The UI is a thin client. Every endpoint returns JSON and can be called directly,
which makes any number on screen checkable in isolation.

| Endpoint | Returns |
|---|---|
| `/api/meta` | meters, zones, date bounds, enum domains |
| `/api/kpi` | headline consumption + electrical aggregates |
| `/api/daily` `/api/monthly` `/api/zones` | consumption series |
| `/api/meters` | per-meter table, consumption joined to electricals |
| `/api/readings` | **individual readings**, paginated |
| `/api/series` | per-reading time series for charting |
| `/api/status` | every `status_*` column broken down |
| `/api/nonzero` | non-zero / zero / negative / NULL per signal |
| `/api/pfdist` | PF distribution per phase |
| `/api/bill` | invoice reconciliation |

All accept `from`, `to`, `zone` (repeatable), `meter` (repeatable);
`/api/readings` also accepts `t1`, `t2`, `status`, `nonzero`, `limit`, `offset`.

---

## Performance notes

Three things were needed to keep live querying fast over 4.5M rows:

1. **Do not join the fact tables to `gold.meter` / `gold.zone` / `gold.facility`.**
   Those are views over silver staging views over bronze; joining them to 4.5M
   rows re-derives that whole stack per query and turned a 4-second aggregate
   into a 90-second one. They are 31 and 21 rows, so they are resolved once at
   startup and the facts are filtered on plain UUID keys instead.
2. **Keep date predicates sargable.** Filtering on
   `(reading_timestamp_utc + interval '3 hours')::date` cannot use
   `pk_energy_readings_snapshot`. The server compares the bare column against a
   shifted bound instead. Saudi is a fixed UTC+3 with no DST, so this is exact.
3. **Serve on threads.** Each page fires four or five requests at once; on a
   single-threaded `HTTPServer` they serialize and one slow aggregate leaves
   every panel showing an em-dash, which looks like a broken dashboard rather
   than a queued one.

Results are cached by exact query string. The warehouse is a static snapshot,
so this is safe, and revisiting a view is instant. The full 19-month window
takes about 15 seconds on first request and is immediate thereafter.

---

## Verified

Row-level check against the database, `ZN.2-PB` at 2026-07-05 01:05:13 — every
column on the Readings page matched `gold.energy_raw` exactly: A1 1.00,
A2 0.50, A3 2.00, Vn1 233.5, VL1 404.2, 59.980 Hz, PF1 0.280, PF2 1.000,
PF3 0.740, PFa 0.540, 0.380 kW, −8.700 kVAr, cumulative 60,821.5 kWh,
status_amp1 Acceptable, status_pfa Critical, overall Critical.

Aggregate check: `/api/kpi` over the full period returns 2,020,697.5 kWh,
1,666,455.0 normal + 354,242.5 long-gap, 4,535,918 raw readings.

Contrast: every series colour clears 3:1 against its ground in both themes
(dark 6.8–8.4:1, light 3.3–5.4:1), and `color-scheme` is declared so the date
pickers render correctly in dark mode.

---

## One caveat worth knowing

`gold.energy_consumption_validated` holds **29 meters and 20 zones**, not 31
and 21 — Zone 13's two meters are excluded by your own business rule. So
consumption figures cover 29 meters while the electrical signals on the other
pages cover all 31 from `gold.energy_raw`. That asymmetry is your gold layer's,
and matching your Power BI requires preserving it; the Overview states it
plainly as "29 of 31".

`reactive_power_total_kvar` also reads oddly (−8.7 kVAr against 0.38 kW in the
verified row above). It is displayed as recorded, without correction, but it is
worth raising with the metering vendor before anyone sizes capacitors from it.

---

## Round 2 fixes

Eight items raised after first review, plus two factual errors those items exposed.

| # | Raised | Done |
|---|---|---|
| 1 | Still slow | See below — every endpoint now 1.6–3.3 s |
| 2 | No reset for date/time | Three buttons: **reset** on date range, **reset** on time-of-day, **reset all** |
| 3 | Charts can't zoom; axes poor | Scroll to zoom, drag to select, double-click to reset. Compact ticks (`1.2M` / `45k`), capped at 12 x-ticks and 7 y-ticks |
| 4 | Imbalance formula wrong | Replaced with **NEMA MG-1 / IEEE 141** |
| 5 | Date wrong on hover card | Labels now carry the full timestamp; the axis abbreviates, the tooltip does not |
| 6 | Bar hover inexact | Tooltip callbacks with units and sensible precision; `axis:'x'` so a bar reports its own value |
| 7 | Signal availability order / 100% | Alphabetical, and **Availability split into two columns** |
| 8 | Readings and intervals identical | `Intervals` removed; `Cadence s`, `Expected`, `Coverage` added |

### 1 — Speed

The cause was query *shape*, not data volume. Three endpoints read the whole
table once per column:

| Endpoint | Passes before | Now | Full-period time |
|---|---:|---:|---:|
| `/api/status` | 16 (UNION ALL per status column) | 1 | ~2.1 s |
| `/api/nonzero` | 26 (UNION ALL per signal) | 1 | ~2.0 s |
| `/api/pfdist` | 4 (one per PF phase) | 1 (`LATERAL VALUES` unpivot) | 7.0 s → **1.6 s** |

Also: every raw query now names the meter keys even when unfiltered.
`pk_energy_readings_snapshot` is `(energy_meter_key, reading_timestamp_utc)`, so
a timestamp-only range cannot lead with the index. Naming the keys turns one
4.5M-row sequential scan into 31 index range searches — **28 ms against 103 ms**
on the same aggregate.

### 4 — Imbalance was the wrong quantity

Old: `(max − min) ÷ max`. That is capped at 100%, blind to *which* phase
deviates, and reads high on lightly loaded boards.

New, NEMA MG-1 / IEEE 141:

```
unbalance % = max |I_phase − I_mean| / I_mean × 100
```

This is what motor derating and switchgear limits are written against, so it can
legitimately be compared to a threshold. Bands are now **2%** (usual operating
limit; NEMA derates motors above 1%) and **10%** — not the 15/30% that suited the
old formula. Blank below 0.5 A mean, where the ratio is noise.

Worked example, ZN.20-PB.1 over 7 days: L1 4.87 A, L2 19.51 A, L3 2.29 A.
Mean 8.89 A, largest deviation 10.62 A → **119.5%**. The old formula reported
88.3% for the same board. Note the NEMA figure can exceed 100% — that is
correct, and is precisely the sensitivity the old one lacked.

### 7 — "Availability 100%" was misleading

It measured `NOT NULL`, which for these meters is almost always true. Split into:

- **Transmitted %** — the meter sent a value at all
- **Non-zero %** — that value carried information

The case that proves it: `reactive_energy_cumulative_kvarh` is **100%
transmitted but only 42% non-zero** — 42,135 of 72,632 rows are exactly zero.
"100% available" meant "always sent", never "always meaningful". The five kVA
columns sit at **0% transmitted**: never ingested, which is not the same as zero.

### 8 — Readings and intervals were genuinely the same number

`gold.energy_consumption_validated` holds exactly one interval per raw reading,
so the two columns were identical by construction. Verified over multiple
windows: they agree row for row for all 29 mapped meters, and differ only for
Zone 13's two meters, which the view excludes. Those two account for the entire
275,069-row difference between 4,535,918 raw and 4,260,849 validated.

`Intervals` is gone. In its place: **Cadence s** (that meter's measured median
gap), **Expected**, **Coverage**, and a column marking whether the meter is in
the consumption view at all.

### Two factual errors these fixes exposed

**The cadence is not 5 minutes.** The measured median inter-reading gap is
**244.2 s (~4.07 min)**, so about **354 readings per meter-day, not 288**. I had
asserted 5 minutes in the footer, on two panels, and in the coverage
calculation. A hardcoded 288 understated the denominator by 23% and produced
coverage figures above 100% — which is how the error surfaced. `Expected` is now
derived from each meter's *own* measured median gap rather than any assumed rate.

**A patch script had silently not applied.** The first attempt at the NEMA
formula failed on its last edit and, because the file write came after all edits,
none of them were saved — while the explanatory panel text (applied separately)
already described NEMA. The page briefly claimed one formula and computed
another. Fixed, and confirmed by recomputing the top row by hand against the
displayed figure.
