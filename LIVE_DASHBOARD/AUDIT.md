# Audit — live dashboard vs Power BI vs database

Date: 2026-09-10. Every figure the dashboard shows was checked against the
database directly, and against the 52 DAX measures in
`Sadin_Gold_DATA_AI_Dashboard.SemanticModel`.

**Result: one real defect found and fixed, one semantic gap closed, everything
else reconciles exactly.**

---

## 1. Consumption — matches Power BI to the decimal

| Power BI measure | DAX | Database | Dashboard | |
|---|---|---:|---:|---|
| `Total Validated Consumption kWh` | `SUM(validated_kwh_consumption)` | 2,020,697.50 | 2,020,697.5 | ✅ |
| `Consumption by Time Period kWh` | same, filtered `NORMAL_INTERVAL` | 1,666,455.00 | 1,666,455.0 | ✅ |
| `Meters Included` | `DISTINCTCOUNT(energy_meter_key)` | 29 | 29 | ✅ |
| `Average Daily Consumption kWh` | `AVERAGEX(VALUES(date), [Total])` | 3,570.14 | 3,570.14 | ✅ |
| — | distinct `reading_date_saudi` | 566 | 566 | ✅ |
| — | `LONG_GAP` share | 354,242.50 | 354,242.5 | ✅ |

Because the dashboard sums the same column rather than re-deriving it, these
agree by construction.

### Internal consistency

Each breakdown independently re-sums to the headline:

| Breakdown | Rows | Sum |
|---|---:|---:|
| Daily | 566 | 2,020,697.5 ✅ |
| Monthly | 20 | 2,020,697.5 ✅ |
| By zone | 20 | 2,020,697.5 ✅ |
| By meter | 31 | 2,020,697.5 ✅ |

---

## 2. Electrical measures — all match

| Power BI measure | Database | Dashboard | |
|---|---:|---:|---|
| `Reading Count` | 4,535,918 | 4,535,918 | ✅ |
| `Total Meters` / `Active Meters` | 31 | 31 | ✅ |
| `Peak Active Power kW` | 62.8120 | 62.812 | ✅ |
| `Average Active Power kW` | 4.293006 | 4.293 | ✅ |
| `kWh Counter Decrements` | 63 | 63 | ✅ |
| `Negative active power TkW Readings` | 281,484 | 281,484 | ✅ |
| `Negative PF P1 / P2 / P3` | 467,488 / 336,702 / 243,679 | identical | ✅ |
| `Negative active power P1 / P2 / P3` | 468,061 / 338,822 / 247,511 | identical | ✅ |
| `PF1 / PF2 / PF3 Critical %` | 33.065 / 37.572 / 32.489 | identical | ✅ |
| `Amp1 / Amp2 / Amp3 Mismatch Readings` | 34,479 / 17,524 / 27,426 | identical | ✅ (after fix) |

---

## 3. DEFECT FOUND AND FIXED — status page was hiding 79,429 readings

**What happened.** To make the status page fast I replaced a
`SELECT DISTINCT` over 4.5M rows with a hardcoded list of status values, taken
from `silver.status_rank`:

```
Acceptable, Review Required, Anomaly, Problematic, Critical, Invalid
```

That ladder is **not the full domain**. The three-argument
`silver.classify_current_v2` also emits two values that `status_rank` never
mentions:

```sql
IF value > 0 AND phase_kw = 0 THEN RETURN 'Major Problem';   -- current, no power
IF value = 0 AND phase_kw <> 0 THEN RETURN 'Major Issue';    -- power, no current
```

These are **sensor-disagreement faults** — exactly the kind of thing a data
page exists to surface. The dashboard reported **0** of them.

| | Was shown | Actually |
|---|---:|---:|
| `Major Issue` | 0 | 34,069 |
| `Major Problem` | 0 | 45,360 |
| **Total hidden** | | **79,429** |

**Fix.** The domain is now discovered from the data in one pass at startup
rather than assumed, and the server prints any value it did not expect. If a
classifier is ever changed to emit a new label, the page picks it up instead of
silently dropping those rows.

Verified after the fix — every status total matches the database:

| Status | Database | Dashboard |
|---|---:|---:|
| Acceptable | 58,659,469 | 58,659,469 ✅ |
| Critical | 8,879,543 | 8,879,543 ✅ |
| Problematic | 4,498,237 | 4,498,237 ✅ |
| Review Required | 457,884 | 457,884 ✅ |
| Major Problem | 45,360 | 45,360 ✅ |
| Major Issue | 34,069 | 34,069 ✅ |
| Invalid | 126 | 126 ✅ |

`Anomaly` is in the ladder but never occurs in the data.

---

## 4. Semantic gap closed — negatives counted two different ways

Power BI's `Total Negative PF Readings` sums the three **phase** counts. The
dashboard counted the **total channel**. Both are correct; they are different
quantities, and a reading negative on two phases is counted twice by the first.

| | Value |
|---|---:|
| `power_factor_average < 0` (dashboard's original) | 280,323 |
| L1 + L2 + L3 (the Power BI figure) | 1,047,869 |
| `active_power_total_kw < 0` | 281,484 |
| L1 + L2 + L3 (the Power BI figure) | 1,054,394 |

Both are now shown side by side on the Power Factor page, with the per-phase
breakdown spelled out, so the two reports can be reconciled rather than merely
compared and found to disagree.

---

## 5. Bill page — matches

| | Database | Dashboard |
|---|---:|---:|
| Invoices | 28 | 28 ✅ |
| Billed kWh | 171,240.5 | 171,240.5 ✅ |
| Metered kWh | 132,739.8 | 132,739.8 ✅ |
| Within ±2% | 12 | 12 ✅ |

---

## 6. Zone 13 reconciliation

The dashboard shows 31 meters with readings but 29 with consumption. That gap
is entirely Zone 13, and it accounts exactly for the difference between the two
fact tables:

| Meter | Readings | Consumption |
|---|---:|---|
| ZN.13-PB.1 | 145,533 | excluded |
| ZN.13-PB.2 | 129,536 | excluded |
| **Total** | **275,069** | |

4,535,918 raw − 4,260,849 validated = **275,069** ✅ — the whole difference,
nothing else missing.

---

## 7. Two Power BI observations, not defects

**`meter_label` on `gold energy_raw` is a calculated column**, not a view
column: `RELATED('gold meter'[meter_label])`. Three measures depend on it
(`Active Meters`, `Selected Meter Consumption kWh`, `Selected Meter Max Gap
Days`). It resolves through the model relationship, so it works — but the
column does not exist in the database, and a query written against
`gold.energy_raw` expecting it will fail.

**The Power BI model omits columns the view provides.** Absent from the
imported table: all four `apparent_power_*` columns,
`apparent_energy_cumulative_kvah`, `voltage_neutral_average_v` and
`voltage_line_average_v`. The kVA family is 100% NULL so nothing is lost there,
but the two `*_average_v` columns are also entirely zero in the source, which is
worth knowing before anyone tries to use them.

---

## 8. One latent issue worth raising with whoever owns the silver layer

`silver.status_rank` does not rank `Major Issue` or `Major Problem`, so both
fall to its `ELSE 0` branch — **below `Acceptable`, which ranks 1**.

Today this is harmless, because `worst_status` is only applied across voltage,
frequency, power factor and kWh, and none of those emit those two values. But if
the three current channels are ever folded into `overall_status`, a genuine
sensor-disagreement fault would rank *lower* than a healthy reading and be
invisible in the rollup. Two extra `WHEN` branches in `status_rank` would close
it before it becomes a real problem.

---

## How to re-run this

Every figure above came from one of two places, both re-runnable:

```bash
# the dashboard's own numbers, as JSON
curl "http://localhost:8770/api/kpi?from=2024-12-09&to=2026-07-11"
curl "http://localhost:8770/api/status?from=2024-12-09&to=2026-07-11"

# the database, directly
psql -U postgres -d sadinhub -c "
  SELECT round(sum(validated_kwh_consumption)::numeric,2)
  FROM gold.energy_consumption_validated;"
```

The API returns plain JSON with no rounding beyond what is displayed, so any
figure on screen can be checked in isolation.

---

# Validation of the redesigned UI (`dashboard_updated.html`)

Date: 2026-09-10. Question asked: is the backend still working as it did in the
older file, is any connection changed, and is the data still valid?

**Answers: yes, no, and yes.** One presentation bug found and fixed. Nothing in
the data path was altered.

## 1. Both files share one backend

`dashboard.html` and `dashboard_updated.html` are both static clients of the
same `serve.py`. There is no second data path, so the backend cannot differ
between them. What *could* differ is how each client calls it and what each
computes locally — so that is what was checked.

## 2. API usage is identical

All 12 endpoints, with identical arguments:

| | |
|---|---|
| Endpoints in old but not new | **none** |
| Endpoints in new but not old | **none** |
| `/api/series` extra args | `{limit:6000}` in both |
| `/api/readings` extra args | `{limit, offset, nonzero, status}` in both |

## 3. Client-side computation compared function by function

Normalised (comments and whitespace stripped) and diffed:

| Function | Verdict |
|---|---|
| `qsBuild` — turns filters into query params | **byte-identical** |
| `unbalance` — NEMA MG-1 formula | **byte-identical** |
| `pct`, `fmt`, `tsLabels`, `tickDate`, `tickNum`, `merge` | **byte-identical** |
| `statusTag` | differs — improvement, see below |
| `api` | differs — demo fallback, see below |

`qsBuild` being byte-identical is the important one: it is the single place
where filter state becomes a request, so identical input produces an identical
query on both files.

**`statusTag`** now also colours `Major Problem` and `Major Issue` as warnings
instead of letting them fall through to the neutral style. Cosmetic; no value
changes.

**`api`** gained a fallback branch:

```js
var job = DEMO ? window.SADIN_DEMO.route(path, query, state)
               : fetch(path + '?' + query).then(...)
```

This was worth checking carefully, because a demo path in a dashboard whose
whole point is validated real data would be a serious problem. It is not one:

- `DEMO` initialises to `false`.
- It is only set true inside the `.catch()` of the initial `/api/meta` fetch —
  i.e. only when the API is unreachable — **and** only if `window.SADIN_DEMO`
  exists.
- `window.SADIN_DEMO` is never assigned anywhere in the file, so the branch is
  unreachable. The `else` runs instead and prints an honest "Cannot reach the
  API" message.

Confirmed at runtime, not just by reading:

```
typeof window.SADIN_DEMO  ->  "undefined"
live badge                ->  "live"        (not "demo data")
source stamp              ->  "gold.energy_consumption_validated · gold.energy_raw"
error box                 ->  empty
```

## 4. Every page renders, and every figure matches the database

All 8 pages, 12 charts, 8 tables populated. Values checked against SQL run
directly against the warehouse:

| Page | Figure | Dashboard | Database |
|---|---|---:|---:|
| 01 Command | Validated consumption | 2,020,697.5 | 2,020,697.50 ✅ |
| | Intervals / days / meters / zones | 4,260,849 / 566 / 29 / 20 | identical ✅ |
| | Normal / long-gap split | 1,666,455.0 / 354,242.5 | identical ✅ |
| | Long-gap share, intervals | 17.5%, 875 | 17.53%, 875 ✅ |
| | Mean power factor | 0.6372 | 0.6372 ✅ |
| | Peak single-meter kW | 62.81 | 62.8120 ✅ |
| 02 Energy | Mean active power | 4.293 kW | 4.293006 ✅ |
| | Mean reactive power | −29.700 kVAr | −29.700 ✅ |
| | Max cumulative register | 180,397.2 | 180,397.2 ✅ |
| 03 Current | Mean L1 / L2 / L3 | 10.91 / 9.55 / 7.20 | identical ✅ |
| | NEMA unbalance | 21.9% | 21.91% hand-computed ✅ |
| 04 Voltage | Mean Vn / VL | 227.9 / 394.7 | 227.93 / 394.74 ✅ |
| | Mean frequency | 59.9977 Hz | 59.9977 ✅ |
| 05 Power factor | PF average / min | 0.6372 / −0.990 | identical ✅ |
| | Negative PF, total channel | 280,323 | 280,323 ✅ |
| | Negative PF per phase | 467,488 / 336,702 / 243,679 | identical ✅ |
| | Negative kW per phase | 468,061 / 338,822 / 247,511 | identical ✅ |
| 07 Readings | Total matching | 4,535,918 | 4,535,918 ✅ |
| 08 Bill | Invoices, billed, metered | 28, 171,240.6, 132,739.8 | 28, 171,240.5, 132,739.8 ✅ |

The 0.1 kWh on the bill total is from summing the *displayed* rounded values,
not a data difference.

### Row-level check

First row of the Readings page, verified column by column against
`gold.energy_raw` — `ZN.7-PB` at 2024-12-11 01:59:42:

A1/A2/A3 0.00 · Vn 227.4 / 228.4 / 227.5 · VL 394.7 / 394.8 / 393.9 ·
60.020 Hz · PFa 1.000 · 0.000 kW · 0.000 kVAr · cumulative 17.0 kWh /
0.0 kVArh · status_amp1, status_pfa, overall all `Acceptable`. **All 26 columns
matched.**

### The status fix carried over

The `Major Issue` / `Major Problem` defect fixed earlier in `serve.py`
propagates correctly into the new UI. Its status chart now totals all seven
values:

| Status | Dashboard | Database |
|---|---:|---:|
| Acceptable | 58,659,469 | 58,659,469 ✅ |
| Critical | 8,879,543 | 8,879,543 ✅ |
| Problematic | 4,498,237 | 4,498,237 ✅ |
| Review Required | 457,884 | 457,884 ✅ |
| Major Problem | 45,360 | 45,360 ✅ |
| Major Issue | 34,069 | 34,069 ✅ |
| Invalid | 126 | 126 ✅ |

Signal availability, spot-checked: `active_energy_cumulative_kwh` 4,535,918
transmitted / 4,496,915 non-zero / 39,003 zero ✅;
`active_power_phase_1_kw` 4,457,895 non-zero / 78,023 zero / 468,061 negative ✅.

## 5. One bug found and fixed

`el('stRange').textContent = state.from.slice(5) + ' → ' + state.to.slice(5)`

stripped the year from the window label, so the full 19-month range displayed as
**"12-09 → 07-11"** — ambiguous, since those ends are 2024 and 2026. Now the
year is kept whenever the window crosses one, and same-year windows keep the
compact form the design intends.

## 6. Server change made during this session

`/` previously always served `dashboard.html`. It now prefers
`dashboard_updated.html` when that file exists, so `http://localhost:8770`
lands on the current UI. The older file remains reachable at `/dashboard.html`.
No endpoint, query or filter semantics were touched.

## Note on how the files must be opened

Neither dashboard can be opened by double-clicking it in Explorer. That loads
`file:///C:/…`, where `fetch('/api/meta')` resolves to `file:///api/meta` and
fails — the page renders but shows no data. Both must be served over
`http://localhost:8770`.

---

# Defect: "Negative PF readings" reported 0 against a chart full of negatives

Reported from the UI: meter `ZN.10-PB.1`, 2025-02-10 → 2025-02-12. The card read
**0** while the chart plainly showed PF2 below zero across most of the window.

## The numbers were right; the metric was wrong

Verified against the database for that exact selection:

| | Value |
|---|---:|
| Readings | 860 |
| `power_factor_average < 0` | **0** |
| `power_factor_phase_2 < 0` | **587** |
| any phase PF < 0 | **587** |
| `min(power_factor_average)` | 0.370 |
| `min(power_factor_phase_2)` | **−0.070** |

So the card was arithmetically correct and analytically useless. The average
channel cannot go negative while a single phase reverses —
`avg(0.56, −0.04, 0.71) = 0.41` — so a count on it returns 0 even though
**587 of 860 readings (68%) had a reversed L2**.

The `Lowest PF` card had the same fault: it showed **0.370**, the minimum of the
*average*, while captioned "negatives included". The true minimum was −0.070.

## Fix

Three cards now lead with the quantity the chart actually plots, and keep every
alternative definition visible in the subtitle rather than choosing silently:

| Card | Was | Now |
|---|---:|---:|
| Negative PF — any phase | 0 | **587** |
| Negative power — any phase | 0 | **595** |
| Lowest PF — any phase | 0.370 | **−0.070** |

Subtitles now spell out all three readings of the question, e.g.

> readings with any phase PF < 0 · L1 0 L2 587 L3 0 · on the average channel
> only: 0 · phase sum 587 (the Power BI figure)

"Any phase" is deliberately not the sum of the three phase counts: a reading
negative on two phases would be counted twice. The phase sum is still shown,
because that is what Power BI's `Total Negative PF Readings` computes.

All three cards also now turn red when non-zero, instead of showing a
reassuring zero.

Verified in the UI at the reported selection: 587, 595, −0.070, all flagged
critical.

## Same fault exists in the superseded `dashboard.html`

That file is kept only for comparison and is no longer served at `/`. It has
not been changed.
