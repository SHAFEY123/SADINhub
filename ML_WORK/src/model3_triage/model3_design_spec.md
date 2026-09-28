# Model 3 — daily triage: DESIGN SPECIFICATION (v2)

**Status: design only, approved in principle 2026-09-20 with five decisions resolved and
four corrections applied. No Isolation Forest is fitted, no score is produced, no threshold
is chosen.** Every number was measured read-only against the live database from
`gold.energy_raw` + `gold.meter` alone, with no dependency on Task 0A or Task 0B.

**Revision v2 applies corrections A–D of 2026-09-20** — cross-refit ranking, artifact
separation from Model 1, corrected feature-range assumptions, and base rates recomputed on
the real scored universe. Each is marked **[A]**, **[B]**, **[C]**, **[D]** where it lands.

---

## 0. What Model 3 is, and what it is not

| | |
|---|---|
| **Is** | A secondary daily triage score that ranks meter-days by how unusual their raw electrical behaviour was, so limited engineering review time goes to the most unusual days first. |
| **Is not** | The primary anomaly detector. That is Model 1 — deterministic, evidence-carrying, frozen. |
| **Is not** | A ground-truth classifier. No engineering labels exist; nothing here establishes that a day contains a fault. |
| **Is not** | A consumption model. It reads no register-derived quantity and does not depend on Task 0A or 0B. |

Model 3 produces a **ranking**, never a verdict.

---

## 1. The ten decisions

### Decision 1 — Zone 13 stays in scope. **31 meters.**

Model 3 uses **no register-derived feature**, so Zone 13's cumulative-kWh integrity concern
does not reach any input it consumes.

| | Zone 13 (2 meters) | Other 29 |
|---|---:|---:|
| Median readings/day | 269 | 287 |
| Median **ungated** PF-Critical rate, phase 1 | **0.3204** | **0.0105** |
| Median **load-gated** PF-Critical rate, phase 1 | **0.0000** | **0.0000** |
| Days the 5% CB gate opens | 83.4% | 72.2% |

The 5.6% cadence difference is far smaller than the 23.8% shift the whole facility underwent
over time (§3), which rates already neutralise. The 30× PF gap **disappears entirely under
load gating** — it was measuring how lightly loaded those meters run.

> Conditional on the PF feature being load-gated (Decision 2). Ungated, Zone 13's two meters
> would look permanently anomalous and consume review capacity every day for a non-issue.

### Decision 2 — exact numerator and denominator for every rate

| Denominator | Meaning | Used by |
|---|---|---|
| `R` = `readings_reported` | reading packets that meter produced that Saudi day | per-reading and per-phase-channel rates |
| `3R` | phase-channels, three per reading | rates pooled across the three phases |
| `G_k` = `gated_readings_phase_k` | readings where phase *k* is ≥ 5% of breaker rating **and** carries forward power | the load-gated power-factor rate |

Full definitions in §4. Every **rate** is a proportion whose numerator is a subset of its
denominator, so every rate is in [0, 1] and is unchanged if the meter reports twice as
often. Features that are *not* rates are not so bounded — see Decision 11 **[C]**.

### Decision 3 — partial and missing days

| Case | Treatment |
|---|---|
| **No readings at all** | No row. A day with no telemetry has no electrical behaviour to rank. Absence is Model 1 T4's `data_availability` job, already detected there. |
| **Before a meter's first reading / after its last** | Excluded — outside the meter's life, not a gap. |
| **Interior gap day** | No row; counted as `missing_interior_days` in run metadata. |
| **Partial day (few readings)** | **Retained**, with `coverage_ratio` — Decision 4. |

Measured: **15,759 meter-days exist** of 17,980 possible (580 × 31), so **2,221 are
absent**. Largest contributors: ZN.17-PB (227 interior gap days, its 201-day outage) and
ZN.9-PB (215). Fourteen calendar dates have **no meter reporting at all**.

### Decision 4 — low-reading-count days are **retained, with a coverage feature**

1. Exclusion needs an arbitrary threshold and the distribution offers no natural cut:
   0.22% of meter-days are below 10 readings, 0.47% below 50, 1.15% below 200.
2. The thinnest days are often the most interesting.
3. A rate handles cadence; what it does not convey is *confidence*, which is what coverage
   carries.

```
coverage_ratio = readings_reported / median(readings_reported over all meters that Saudi date)
```

Data-derived, so it absorbs the 286 → 354 cadence regime change automatically and survives
any one meter being down. `low_coverage_day` (`coverage_ratio < 0.5`) is carried **for
reporting only** and is never a filter.

### Decision 5 — one **global** Isolation Forest, not one per meter

| | Global | Per meter |
|---|---|---|
| Scores comparable across meters | ✅ | ❌ |
| Sees a meter faulty for its whole history | ✅ | ❌ |
| Training rows available | ~14,130 | ~450 per meter |

The second row is decisive and not hypothetical: a per-meter model learns that meter's own
history as normal, the exact blind spot Model 1's T4 hit on ZN.16-PB, whose fault covers
95.37% of readings across 18 of 19 months. A per-meter Model 3 would rank ZN.16-PB's
faulted days unremarkable for eighteen months.

### Decision 6 — meter identity is **not** a feature

An Isolation Forest scores a point by how few splits isolate it. A meter id — one-hot or
ordinal — is isolable in one split, so the score drifts toward "which meter is this" and
rare meters score anomalous for being rare.

Per-meter context enters as **behaviour**: `<rate>_dev28` = the rate minus that meter's
trailing 28-day median, 0 with `dev28_available = False` when fewer than 14 prior days
exist. Tier 2 only (Decision 12).

### Decision 7 — rolling window: **180 days, refit daily, minimum 60 distinct prior dates** **[D]**

| Parameter | Value | Definition |
|---|---|---|
| `train_window_days` | 180 | training rows are all meter-days with `D − 180 ≤ day < D` |
| `min_train_dates` | 60 | **60 distinct prior Saudi calendar dates carrying observed training data** — *not* 60 meter-day rows. A single date contributing 31 meter-days counts as **one**. |
| Refit cadence | daily | the scored day is always out of sample |

The distinction matters: 60 meter-day rows could be two calendar dates, which would
calibrate a forest against essentially one moment. Sixty distinct dates guarantee the
reference spans two months of facility behaviour.

Measured consequence: the first scorable Saudi date is **2025-02-07**; 60 observed dates
(2024-12-09 → 2025-02-06) fall in warm-up; **506 of 566 observed dates are scorable**; and
the minimum `distinct_prior_dates` among scorable days is exactly 60.

> **180 days is a pre-specified, unvalidated v1 parameter** (resolved §11.1). It will not be
> chosen from alternatives by maximising Model 1 overlap — that would make the cross-check
> circular and turn a concordance measure into a fitting objective.

### Decision 8 — `contamination='auto'`, and it is **not** a prevalence estimate

`contamination` sets the **decision threshold** that converts scores into a binary
`predict()` output. It does not change the fitted forest and does not estimate how many
faults exist.

Model 3 **never calls `predict()`**. It takes `score_samples()`, ranks, and reviews the top
N, so the threshold is irrelevant to every output. `contamination='auto'` is chosen so no
number in the configuration can be mistaken for a prevalence claim.

This has already been misread once: the earlier prototype used `contamination=2%` and
flagged 3.9% of days. Neither is an estimate of how many faulty days exist — **both are
properties of a threshold applied to a ranking**, on data with no labels.

### Decision 9 — score normalisation and ranking **[A]**

**The correction.** `daily_rank_pct` is a percentile *within* one Saudi day. Exactly one
meter per day attains 1.0, so a global historical Top-50 taken on it would be ~506 rows all
tied at 1.0 and resolved by nothing but tie-break order. It cannot rank across days and must
never be used to.

Two scores are produced, with separate jobs:

| Score | Comparable across | Used for |
|---|---|---|
| `daily_rank_pct` | within one Saudi day | within-day facility ranking, "who was worst today" |
| **`window_anomaly_pct`** | **across refits** | **global historical Top-25/50/100 and per-meter historical ranking** |
| `window_anomaly_z` | across refits | **deterministic secondary tie-break only** |

**`window_anomaly_pct`** — for each daily forest `F_D`:

1. `train_scores = −F_D.score_samples(W_D)` — score the forest's own 180-day training rows,
   same sign convention as everything else.
2. For each meter *m* present on *D*: `raw_score = −F_D.score_samples(x_{m,D})`.
3. `window_anomaly_pct = |{t ∈ train_scores : t ≤ raw_score}| / |train_scores|`.

The result is an empirical percentile against **that forest's own reference distribution**,
so a 0.98 on one date means the same thing as a 0.98 on another even though the two forests
differ. Convention fixed explicitly: `≤`, so a score above every training row gives exactly
1.0.

The training scores are **in-sample**. With `max_samples=256` most training rows are out of
most trees' subsamples, so the bias is small, but this is a **calibration reference, not a
performance estimate**, and is recorded as such.

**`window_anomaly_z` is a tie-break, and nothing more.** `window_anomaly_pct` has a
ceiling: a genuinely extreme day scores above every training row and saturates at 1.0, and
several meters can saturate on the same day, reintroducing the tie problem one level up.

```
window_anomaly_z = (raw_score − mean(train_scores)) / std(train_scores)
```

> **What it is not.** It is **not** a calibrated probability, **not** a confidence, and
> **not** an independent anomaly measure. It is a deterministic ordering device for rows
> whose `window_anomaly_pct` is equal — above all at the 1.0 saturation point. Isolation
> Forest scores are not normally distributed, so a z-value here carries no distributional
> meaning and must never be read as "how many sigmas anomalous". `window_anomaly_pct`
> remains the primary cross-refit historical ranking score; nothing is ranked, selected or
> reported on `window_anomaly_z` alone.

Ranking order is
`(window_anomaly_pct desc, window_anomaly_z desc, day_saudi, meter_label)` — fully
deterministic, with the two label fields guaranteeing byte-identical order between runs.

Retained for audit: `raw_score`, `train_score_mean`, `train_score_std`, `n_train_rows`,
`n_train_dates`, `window_start`, `window_end`, `n_meters_scored_that_day`.

### Decision 10 — cross-check against Model 1, on the scored universe **[B][D]**

**Model 1 outputs never touch the fit.** Stronger than "excluded by allow-list": the fitting
and scoring stage does not open a Model 1 artifact at all (§5). The join happens afterwards,
into a separate cross-check artifact. Circularity is prevented by process, not by discipline.

**Base rates come from the scored universe, not all meter-days.** Warm-up removes 1,629
meter-days, so the preliminary denominators were wrong:

| Model 1 family | base rate, all 15,759 | base rate, **scored 14,130** | Δ |
|---|---:|---:|---:|
| T1 polarity | 19.66% | **19.61%** | −0.05 |
| T2 current/power | 8.03% | **7.83%** | −0.20 |
| T3 power factor | 48.81% | **48.80%** | −0.01 |
| T5 register | 3.84% | **3.35%** | −0.48 |
| **any family** | 59.67% | **58.97%** | −0.70 |
| Critical or Problematic | 50.52% | **49.58%** | −0.93 |

The shifts are small but they are the correct denominators, and T5 moves most because many
stuck-register days sit in the commissioning-era warm-up. **These values are recomputed by
the run from its own scored population and are never hard-coded**, so any future change to
warm-up or scope re-derives them automatically.

The metric is **lift over base rate**, because the "any family" base rate of 58.97% means a
random top-50 would "agree with Model 1" about 59% of the time:

```
overlap_f@N = share of the top-N meter-days carrying >= 1 Model 1 event of family f
lift_f@N    = overlap_f@N / base_rate_f        # 1.0 is chance
```

with a permutation null: 10,000 random N-draws **from the scored universe**, reporting the
95th percentile.

Three standing rules: agreement is **concordance, not precision** — neither model has
labels; **disagreement is an output, not a failure**; and **no Model 3 parameter is ever
selected by maximising lift** (§11.1, §11.3).

### Decision 11 — feature ranges: only genuine rates are bounded **[C]**

The v1 draft asserted every feature lies in [0, 1]. That is wrong, and measurably so.

| Feature group | Range | Measured |
|---|---|---|
| The ten **rate** features | **[0, 1]** | numerator ⊆ denominator by construction |
| `coverage_ratio` | **[0, ∞)** | min 0.0035, **max 2.0000, exceeds 1 on 3,173 of 15,759 meter-days (20.13%)** |
| `mean_load_pct_cb` | **[0, ∞)** | min 0.00, max 41.89, p99 25.90 — never exceeds 100 in this history, but **may in principle and must not be clipped** |
| `*_dev28` | **[−1, +1]** for rate deviations | measured −1.0000 to +0.9563, negative on 4.99% of meter-days |

`coverage_ratio > 1` on a fifth of meter-days is not an anomaly — the denominator is the
facility *median*, so roughly half the meters sit at or above it by definition. A [0, 1]
assertion would have failed on 20% of the table for an entirely mundane reason.

**The only universal constraint on the fitted matrix is that every value is finite.** No
feature is clipped, winsorised or rescaled: an Isolation Forest is scale-invariant, and
clipping `mean_load_pct_cb` at 100 would silently erase precisely the overload condition
most worth surfacing.

### Decision 12 — Tier 1 is the canonical v1 fitted set (resolved §11.3)

Tier 1 alone is fitted for v1. Tier 1 + Tier 2 may be run as a **sensitivity variant**, with
the ranking change reported. **No winner is chosen on Model 1 overlap.**

---

## 2. Exact live columns and joins

```sql
FROM gold.energy_raw            e
JOIN gold.meter                 m USING (energy_meter_key)
LEFT JOIN gold.zone             z USING (zone_key)
LEFT JOIN silver.dim_meter_cb_rating r USING (energy_meter_key)
GROUP BY m.meter_label, (e.reading_timestamp_utc + interval '3 hours')::date
```

Saudi-local date derived from UTC in the query. Saudi time is UTC+3 with no DST, so the
Saudi day closes at `D 21:00:00 UTC`. **No Task 0A or 0B artifact is read.**

| Column | Used for |
|---|---|
| `e.reading_timestamp_utc` | Saudi-date grouping, `readings_reported` |
| `e.active_power_total_kw` | `negative_total_power_rate` |
| `e.active_power_phase_1_kw` … `_3_kw` | phase reversal rate, PF load gate, current/power rates |
| `e.current_phase_1_a` … `_3_a` | load gate, current/power rates, `mean_load_pct_cb` |
| `e.power_factor_phase_1` … `_3` | gated PF-Critical rates |
| `e.status_amp1` … `_amp3` | `major_issue_rate`, `major_problem_rate` |
| `e.status_pf1` … `_pf3` | ungated PF-Critical rate (diagnostic only) |
| `e.status_v1`…`_v3`, `status_vn1`…`_vn3` | `voltage_not_acceptable_rate` |
| `e.status_hz` | `frequency_not_acceptable_rate` |
| `m.meter_label` | grouping key and output label (`gold.energy_raw` has none) |
| `z.zone_name` | reporting only, never a feature |
| `r.cb_max_rating_a` | the 5% load gate and `mean_load_pct_cb` |

Not used: `active_energy_cumulative_kwh` and anything derived from it, and the eight columns
verified empty over the full history.

Verified: **`status_amp*` and `status_pf*` are NULL on zero readings**;
`active_power_total_kw` is present on all 4,535,918; every meter has a `cb_max_rating_a`.
No denominator needs a NULL guard.

---

## 3. Why rates rather than counts — the measured case

| Period | Median readings/day |
|---|---:|
| 2024-12 → 2026-03 | 286–287 |
| from **2026-04-11** | 309–315 |
| 2026-07 | **354** |

A **23.8% shift**, plus per-day variation from 1 reading to 354. A count feature inherits
all of it: the same condition yields a 24% larger count after 2026-04-11 purely because the
meter reports more often, and the forest would learn the regime change as an anomaly.

Honestly stated: within the *current* data a raw count correlates only **+0.021** with
cadence, because cadence is nearly constant on most days. The case for rates rests on the
**temporal regime change** and on **partial days**, not on a large cross-sectional
correlation — and being structural, it holds regardless.

---

## 4. Exact feature definitions

Let `R` = `readings_reported`, and for phase *k*:

```
gated_k = count of readings where current_phase_k_a >= 0.05 * cb_max_rating_a
                             AND active_power_phase_k_kw > 0
```

The 5% gate is the production classifier's own `third = margin / 3 = 0.05 * CB`. No new
constant is introduced.

### Tier 1 — canonical v1 fitted set

| # | Feature | Numerator | Denominator | Bounded [0,1]? |
|---:|---|---|---|---|
| 1 | `coverage_ratio` | `R` | facility median `R` that date | **no** |
| 2 | `major_issue_rate` | Σ_k `status_amp_k = 'Major Issue'` | `3R` | yes |
| 3 | `major_problem_rate` | Σ_k `status_amp_k = 'Major Problem'` | `3R` | yes |
| 4–6 | `pf_critical_rate_gated_k` | phase *k* gated **and** `0 <= pf_k < 0.6` | `gated_k` | yes |
| 7–9 | `pf_gate_open_rate_k` | `gated_k` | `R` | yes |
| 10 | `negative_total_power_rate` | `active_power_total_kw < 0` | `R` | yes |
| 11 | `negative_phase_power_rate` | Σ_k `active_power_phase_k_kw < 0` | `3R` | yes |
| 12 | `current_without_power_rate` | Σ_k `current_k > 0 AND kw_k = 0` | `3R` | yes |
| 13 | `power_without_current_rate` | Σ_k `current_k = 0 AND kw_k <> 0` | `3R` | yes |
| 14 | `voltage_not_acceptable_rate` | Σ over 6 voltage statuses `<> 'Acceptable'` | `6R` | yes |
| 15 | `frequency_not_acceptable_rate` | `status_hz <> 'Acceptable'` | `R` | yes |
| 16 | `mean_load_pct_cb` | mean over readings of `(Σ_k current_k)/3` | `cb_max_rating_a`, ×100 | **no** |

Features 7–9 exist for a specific reason. When `gated_k = 0` the PF rate is **undefined**,
and an Isolation Forest cannot take NaN. Imputing 0 would silently assert "power factor was
fine" when the truth is "we never had enough load to judge". Carrying `pf_gate_open_rate_k`
alongside distinguishes *rate 0 because PF was good* from *rate 0 because the gate never
opened*. This is not a corner case: **4,262 of 15,759 meter-days (27.04%) never open the
phase-1 gate.** Convention: `gated_k = 0` ⇒ both are `0.0`, and the pair is unambiguous.

Features 14–15 are retained for v1 (resolved §11.5) despite being all but constant —
measured, **12 non-acceptable of 27,215,508 voltage classifications and 1 of 4,535,918
frequency classifications**, 13 in 31,751,426. They cost two columns and would be the only
signal if a voltage problem ever appeared.

### Tier 2 — per-meter deviation, sensitivity variant only

`*_dev28` for features 2, 3, 4–6, 10, 11, plus `dev28_available`. Nine columns. Not in the
canonical v1 fit.

### Diagnostic columns, never fitted

`pf_critical_rate_ungated_k` (three) so the gated-vs-ungated comparison in §1 is reproducible
on any future run and a reviewer can see why a day was *not* flagged.

---

## 5. Artifacts and schema **[B]**

Model 1 is kept out of the Model 3 pipeline by **separating the artifacts**, not merely by
column selection. The fit-and-score stage never opens a Model 1 file.

| # | Artifact | Contents | Model 1? |
|---:|---|---|---|
| 1 | `model3_feature_table.parquet` | raw Gold-derived features only | **none** |
| 2 | `model3_scores.parquet` | `daily_rank_pct`, `window_anomaly_pct`, `window_anomaly_z`, `raw_score`, window provenance | **none** |
| 3 | `model3_model1_crosscheck.csv` | artifact 2 joined to the frozen Model 1 events, base rates, lift, permutation null | produced **after** scoring |
| 4 | `model3_review_lists.csv` | lists A, B and C (§8) | C needs artifact 3 |
| 5 | `model3_coverage_report.csv` | coverage and scored-universe distributions | none |

### `model3_feature_table.parquet`

| Column | Type | Role |
|---|---|---|
| `energy_meter_key` | str (uuid) | key |
| `meter_label`, `short_label` | str | key / label |
| `zone_name`, `is_zone13` | str / bool | reporting |
| `cb_max_rating_a` | float | reporting; builds the gate |
| `day_saudi` | date | key |
| `readings_reported` | int | provenance |
| `gated_readings_phase_1..3` | int | provenance, the PF denominators |
| Tier 1 features 1–16 | float | **fitted** |
| Tier 2, 9 columns | float / bool | fitted in the sensitivity variant only |
| `pf_critical_rate_ungated_1..3` | float | diagnostic, never fitted |
| `low_coverage_day` | bool | reporting, never a filter |
| `scorable` | bool | passes the warm-up rule (Decision 7) |

Row key `(energy_meter_key, day_saudi)`, unique. **15,759 rows** at current history, of
which **14,130 are `scorable`**. No `m1_*` column exists in this file — asserted by test.

---

## 6. Row counts, coverage and the scored universe

| | |
|---|---:|
| Observed meter-days | **15,759** |
| Meters | **31** (2 in Zone 13) |
| Calendar span | 2024-12-09 → 2026-07-11 (580 days) |
| Distinct Saudi dates with any data | **566** (14 dates have none) |
| Complete grid would be | 17,980 |
| Absent meter-days | **2,221** |
| Warm-up dates excluded | **60** (2024-12-09 → 2025-02-06) |
| First scorable Saudi date | **2025-02-07** |
| Scorable dates | **506 of 566** |
| **Model 3 scored universe** | **14,130 meter-days** |

**Readings per meter-day**

| percentile | 1% | 5% | 25% | 50% | 75% | 95% | 99% | max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| all meters | 157 | 269 | 286 | 287 | 287 | 316 | 354 | 354 |
| Zone 13 only | 204 | 268 | 269 | 269 | 270 | 299 | 354 | 354 |

**Low-coverage days**: < 10 readings on 35 meter-days (0.22%), < 50 on 74 (0.47%), < 100 on
114 (0.72%), < 200 on 182 (1.15%), < 250 on 292 (1.85%).

**Candidate rate distributions**

| feature | mean | median | p90 | non-zero days |
|---|---:|---:|---:|---:|
| `major_issue_rate` | 0.0027 | 0.0000 | 0.0000 | 1.57% |
| `major_problem_rate` | 0.0034 | 0.0000 | 0.0000 | 6.66% |
| `pf_critical_rate_1` **ungated** | 0.3328 | 0.0185 | 1.0000 | **54.16%** |
| `pf_critical_rate_1` **gated** | 0.0402 | 0.0000 | 0.0392 | **12.84%** |
| `negative_total_power_rate` | 0.0621 | 0.0000 | 0.0209 | 11.49% |

The ungated PF rate correlates **−0.648** with `pf_gate_open_rate_1`. A feature that moves
inversely with load is measuring load, not power quality. Gating cuts non-zero days from
54.16% to 12.84% and is the single most consequential choice in this design.

---

## 7. Isolation Forest fitting strategy

| Setting | Proposed | Note |
|---|---|---|
| Scope | one **global** forest per scoring day | Decision 5 |
| Training rows | preceding 180 days, all meters | strictly before the scored day |
| Warm-up rule | ≥ 60 **distinct prior Saudi dates** | Decision 7 |
| `n_estimators` | 200 | fixed in advance, not tuned |
| `max_samples` | 256 | library default and the original paper's recommendation |
| `contamination` | `'auto'` | never read as prevalence; `predict()` never called |
| `random_state` | fixed | required for stable ranking |
| Features | Tier 1 by allow-list | Tier 2 as a separate sensitivity variant |
| Scaling | none | scale-invariant; clipping would erase real overload |

Procedure for Saudi day *D*:

1. Assemble training rows for `[D − 180, D − 1]`; require ≥ 60 distinct dates or skip *D*.
2. Fit one forest `F_D`.
3. `train_scores = −F_D.score_samples(training rows)` — the calibration reference.
4. Score the meters present on *D* — out of sample by construction.
5. Emit `daily_rank_pct`, `window_anomaly_pct`, `window_anomaly_z`, `raw_score` and the
   window provenance.

**Nothing is fitted yet.** Parameters are a proposal for review.

---

## 8. Review lists and the Model 1 overlap metric

| List | Definition | Ranked on | Size |
|---|---|---|---:|
| **A — facility** | most unusual meter-days over the whole history | `window_anomaly_pct` **[A]** | N ∈ {25, 50, 100}, default 50 |
| **B — per meter** | each meter's own most unusual days | `window_anomaly_pct` | 2 per meter (62) |
| **C — unexplained** | list A entries where **the same `(meter_label, day_saudi)`** carries no relevant Model 1 electrical event | — | variable, reported separately **(§11.4)** |

N = 50 is a **historical reporting default only**; operational review capacity is TBD
(§11.2). All three lists carry the standing caveat that these are review candidates.

**List C is produced as its own artifact** and is never folded into A. It is the only output
that can surface something no deterministic rule covers, and its review quota is TBD.

#### What "unexplained" means, exactly

"Explained" is judged **per meter-day, never facility-wide**: a Model 3 item is explained
only if *that same meter* carried a relevant Model 1 event on *that same Saudi day*. Another
meter having an event that day explains nothing about this one.

A Model 1 event counts as explaining an electrical anomaly only when **all** hold:

| Condition | Reason |
|---|---|
| Same `(meter_label, day_saudi)` | a facility-wide reading would mark almost everything explained |
| `event_class = 'ELECTRICAL_FAULT'` | the event asserts an electrical condition |
| `commissioning = False` | a commissioning artifact is not an explanation |

`COMMISSIONING` and `DATA_AVAILABILITY` events are **still joined and still shown** as
context columns on every cross-check row, because a reviewer needs to know a day was an
outage or a commissioning window. They simply never satisfy "Model 1 explains this". A day
whose only Model 1 event is a telemetry outage is therefore **unexplained**, which is the
correct reading: the outage says why data is thin, not why the electrical behaviour was
unusual.

### Overlap metric

Per family and for Critical/Problematic only, at N ∈ {25, 50, 100}:

| Quantity | Definition |
|---|---|
| `base_rate_f` | share of the **scored universe** with ≥ 1 Model 1 event of family *f* |
| `overlap_f@N` | share of list A with ≥ 1 such event |
| `lift_f@N` | `overlap_f@N / base_rate_f` — **1.0 is chance** |
| `null_p95_f@N` | 95th percentile of `overlap_f@N` over 10,000 random N-draws from the scored universe |
| `unexplained@N` | size of list C |

The headline is **lift**, never raw overlap.

---

## 9. Tests

### Cadence normalisation

| Test | Criterion |
|---|---|
| A meter-day duplicated to twice the reading count, same conditions, gives **identical** rates | every Tier 1 rate equal to within 1e-12 |
| Doubling reading count changes only `coverage_ratio` and `readings_reported` | all other features unchanged |
| A raw-count version of the same feature **does** change | proves the test has teeth |
| The 2026-04-11 cadence regime change produces no step in any rate's facility median | median shift < 1 standard deviation |

### Feature ranges **[C]**

| Test | Criterion |
|---|---|
| The ten **rate** features lie in [0, 1] | enumerated by name, not by "all features" |
| `coverage_ratio` is **allowed** to exceed 1 | a fixture above 1 passes validation; measured on 20.13% of real rows |
| `mean_load_pct_cb` is **allowed** to exceed 100 and is **not clipped** | a 150% fixture survives unmodified into the fitted matrix |
| `*_dev28` is **allowed** to be negative | a −0.4 fixture passes |
| Every fitted value is **finite** | no NaN, no ±inf — the one universal constraint, asserted before fitting |
| No feature is winsorised or rescaled | fitted matrix equals the table's own values |

### Missing-day behaviour

| Test | Criterion |
|---|---|
| A meter-day with no readings produces **no row** | absent from the table |
| Days before a meter's first reading and after its last are excluded | row count equals observed meter-days |
| Interior gap days are counted in metadata | `missing_interior_days` non-zero |
| A 4-reading day is **retained** | present, not filtered |
| `gated_k = 0` ⇒ `pf_critical_rate_gated_k = 0` **and** `pf_gate_open_rate_k = 0` | unambiguous pair, no NaN reaches the fit |

### Saudi-date grouping

| Test | Criterion |
|---|---|
| `2026-03-01 20:59:59 UTC` → Saudi day 2026-03-01; `21:00:00 UTC` → 2026-03-02 | exact boundary |
| Every Saudi day spans 86,400 seconds | no DST in the history |
| SQL grouping and pandas grouping agree on every meter-day | identical for all 15,759 rows |

### Warm-up and the scored universe **[D]**

| Test | Criterion |
|---|---|
| `min_train_dates` counts **distinct Saudi dates**, not meter-day rows | a window of 2 dates × 31 meters = 62 rows is **not** scorable |
| First scorable date is 2025-02-07 with the configured window | exact |
| Scored universe is 14,130 meter-days | exact, asserted |
| Base rates are computed from the scored universe, never from all 15,759 | recomputed in-run, not hard-coded |
| The permutation null draws from the scored universe only | sampled population equals the scored population |

### Ranking **[A]**

| Test | Criterion |
|---|---|
| `daily_rank_pct` is a permutation within each day, in [0, 1] | no gaps or duplicates per day |
| **Exactly one meter per day attains `daily_rank_pct = 1.0`** | demonstrates it cannot rank globally |
| **A global Top-N by `window_anomaly_pct` is NOT the set of daily winners** | the two orderings differ on a fixture where every day has a rank-1.0 meter |
| **Global Top-N is not determined by daily-rank ties** | on a fixture where 50 days each have a 1.0 daily rank, the Top-50 by `window_anomaly_pct` selects a different set, ordered by score not by date |
| `window_anomaly_pct` is comparable across refits | two forests with different windows give the same percentile for the same relative position in their own training distributions |
| `window_anomaly_pct` uses `≤` | a score equal to the maximum training score gives exactly 1.0 |
| `window_anomaly_z` breaks ceiling ties | two meters at `window_anomaly_pct = 1.0` order by z, deterministically |
| `raw_score` orientation is correct — a synthetic extreme outlier ranks **first** | catches the sklearn sign convention |
| Two runs on identical input give byte-identical ranks | full-table equality |
| Ties resolve by `(day_saudi, meter_label)` | synthetic ties resolve identically across runs |

### Scope and independence **[B]**

| Test | Criterion |
|---|---|
| `model3_feature_table.parquet` contains **no** `m1_*` column | column-name assertion |
| `model3_scores.parquet` contains **no** Model 1 column | column-name assertion |
| The fit-and-score stage opens **no** Model 1 artifact | no read of any `model1_*` path during fit/score |
| The cross-check artifact is produced only **after** scoring | ordering enforced by the code path |
| No Task 0A/0B artifact is read | nothing outside `gold.*` and `silver.dim_meter_cb_rating` |
| No register-derived column is used | `active_energy_cumulative_kwh` absent from the feature list |
| Read-only, REPEATABLE READ verified before any query | connection facts recorded |
| Row count equals 15,759, scored 14,130, both asserted and failing loudly | scope assertion |

---

## 10. Definition of Done

- [ ] `src/model3_triage/features.py` — daily feature table, rates only, from
      `gold.energy_raw` + `gold.meter`, no Task 0A/0B dependency, **no Model 1 read**
- [ ] `config/model3_config.yaml` — every threshold, window and parameter; none in code
- [ ] `outputs/<ts>/model3_feature_table.parquet` — 15,759 rows, 14,130 `scorable`, §5 schema
- [ ] `outputs/<ts>/model3_coverage_report.csv` — §6 distributions and the scored universe
- [ ] `tests/test_model3.py` — every test in §9 passing
- [ ] `run_metadata.json` — connection facts, scope assertion, config fingerprint, the
      explicit statement that `contamination` is not a prevalence estimate, that
      `window_anomaly_pct` is calibrated in-sample, and that no precision or recall is claimed
- [ ] No Isolation Forest fitted, no score produced, no review list emitted

Fitting, scoring, the review lists and the overlap metric are the **next** stage.

---

## 11. Resolved decisions, 2026-09-20

| # | Question | Resolution |
|---|---|---|
| 1 | 180-day window | **Pre-specified, unvalidated v1 parameter.** Not chosen among alternatives by maximising Model 1 overlap. |
| 2 | N = 50 | **Historical reporting default only.** N = 25/50/100 all reported; operational capacity TBD. |
| 3 | Tier 2 deviation features | **Tier 1 is canonical v1.** Tier 1+2 may run as a sensitivity variant; no winner chosen on overlap. |
| 4 | List C review budget | **Produced separately and kept visible.** It holds candidate findings Model 1 does not explain; quota TBD. |
| 5 | Voltage and frequency features | **Kept in v1.** |

### Corrections applied in v2

| | Correction | Where |
|---|---|---|
| **A** | `daily_rank_pct` cannot rank across days; added `window_anomaly_pct` (+ `window_anomaly_z` for the ceiling) | Decision 9, §7, §8, §9 |
| **B** | Model 1 excluded from the feature and score artifacts entirely; joined only afterwards | Decision 10, §5, §9 |
| **C** | Only genuine rates are bounded in [0, 1]; `coverage_ratio`, `mean_load_pct_cb` and `*_dev28` are not, and nothing is clipped | Decision 11, §4, §9 |
| **D** | Base rates recomputed on the 14,130-meter-day scored universe; `min_train_dates` defined as distinct Saudi dates | Decision 7, Decision 10, §6, §9 |

---

## 12. Implementation record, 2026-09-20

Implemented in the approved sequence. Model 3 is **v1 complete**.

| Stage | Artifact | Model 1 opened? |
|---|---|---|
| 1 — features | `model3_features_20260920T083853Z/` | **no** |
| 2 — fit and score | `model3_20260920T085615Z/model3_scores.parquet` | **no** |
| 3 — cross-check | `model3_20260920T085615Z/model3_model1_crosscheck.parquet` | yes, after all scoring |

**Reconciliation, all 8 exact**: 4,535,918 readings (total and re-summed from the daily
table), 31 meters, 15,759 meter-days, 566 distinct Saudi dates, 14,130 scored, first
scorable date 2025-02-07, row key unique. Warm-up removed 60 dates / 1,629 meter-days.

**Correction A is confirmed empirically.** `daily_rank_pct == 1.0` on exactly **506** rows —
one per scored date — so a historical Top-50 taken on it would have drawn from 506 tied
values. `window_anomaly_pct` has **13,934 distinct values** across 14,130 rows and **8
saturate at 1.0**; `window_anomaly_z` orders those eight (4.25 → 3.63). The ceiling was real
and small, and the tie-break handles it.

**Determinism**: a full refit from scratch produced byte-identical frames,
`max |raw_score delta| = 0.000e+00`.

### Three implementation bugs, each found by a test or a run

1. **Ambiguous join.** `zone_key` exists on both `gold.energy_raw` and `gold.meter`, so
   `USING (zone_key)` raised `AmbiguousColumn`. Joined explicitly through `gold.meter`.
2. **Label/position index mismatch.** `groupby(...).index` returns pandas *labels* while the
   feature matrix is indexed *positionally*. These coincide for a clean `RangeIndex` from
   parquet, so the full run worked by accident; any filtered input raised `IndexError` or —
   worse — would have silently selected the wrong training rows. `score_all_days` now resets
   the index and uses positions throughout.
3. **Object-dtype boolean.** `merge(...).fillna(False)` leaves an *object* column, and `~` on
   an object Series of Python bools performs integer bitwise negation (`True → -2`) rather
   than logical NOT, which broke List C with a `KeyError`. All join flags are now cast with
   `.astype(bool)` and a regression test asserts `~flag` is logical.

Bug 2 is the one worth remembering: it produced correct output on the real data and would
only have surfaced later, on a subset or a re-indexed frame.

### What the results say

Model 3's top of list is concentrated on the **intermittent** polarity meters — ZN.11-PB.2,
ZN.10-PB.2, ZN.10-PB.1 and ZN.12-PB take 84 of the Top-100 — and largely not on the chronic
ones (ZN.16-PB 5, ZN.8-PB.2 2, ZN.5-PB 1). That is the expected consequence of Decision 5:
a constant fault sits in the training window every day and is therefore *normal* to the
forest, while an intermittent fault produces genuinely unusual days.

Model 1 explains **99 of the Top-100**. As a triage layer Model 3 is therefore adding
ordering within days Model 1 already flags, rather than surfacing much that Model 1 misses.
T5 lift is **1.19 with an empirical p-value of 0.43–0.57** — indistinguishable from chance,
so Model 3 does not preferentially surface register-integrity days.

No precision, recall, accuracy or confirmed-fault detection is claimed anywhere.

---

## 13. Corrected permutation null, and Model 3 FROZEN

**Status: Model 3 is FROZEN as of 2026-09-20.** The Isolation Forest, features, scores,
rankings, Top-N lists and Tier-2 sensitivity results are fixed. The correction below touches
the post-score cross-check only; the frozen artifacts were digest-checked before and after
and are byte-identical.

### The problem with the original null

The global null draws arbitrary meter-days from anywhere in the facility, so it tests "is
this better than picking random meter-days?". But Model 3's Top-N is heavily concentrated,
and the meters it concentrates on have Model 1 prevalence far above the facility average:

| Meter | Top-100 rows | own T1 % | own T3 % | own any-family % |
|---|---:|---:|---:|---:|
| ZN.11-PB.2 | 24 | 85.1 | 98.5 | **100.0** |
| ZN.10-PB.2 | 22 | 0.0 | 6.7 | 49.6 |
| ZN.10-PB.1 | 20 | 98.6 | 100.0 | **100.0** |
| ZN.12-PB | 18 | 97.9 | 100.0 | **100.0** |
| *facility base* | — | *19.6* | *48.8* | *59.0* |

When the selected meters are individually explained on ~100% of their days, almost **any**
day drawn from them counts as explained. The global null was therefore mostly testing which
meters Model 3 chose, not which days.

### Three nulls, so each assumption is separable

| Null | Holds fixed | Isolates |
|---|---|---|
| `global` | nothing | the original descriptive result |
| `meter_preserving_iid` | Top-N meter composition | the contribution of **meter composition** |
| `meter_preserving_block` | composition **and** local date runs | the additional effect of **temporal dependence** |

Block length is derived from Model 3's own selections rather than imposed: the mean run of
consecutive selected dates within a meter is 1.14 days at N=25, 1.25 at N=50 and 1.59 at
N=100, giving block lengths of 1, 1 and 2. **At N=25 and N=50 the block null is therefore
identical to the iid null by construction**, because the data show no clustering to
preserve — the two columns agreeing there is a property of the data, not a bug.

All p-values use `(exceedances + 1) / (B + 1)`, so with B = 10,000 the smallest reportable
value is 9.999e-05 and no result can claim more certainty than the draws support.

### The answer: yes, the original significance was largely meter composition

| N | Population | observed | global p | meter-preserving p | verdict |
|---:|---|---:|---:|---:|---|
| 25 | **T1** | 76.0% | 0.0001 | **0.915** | **reverses** |
| 50 | **T1** | 70.0% | 0.0001 | **0.960** | **reverses** |
| 100 | **T1** | 61.0% | 0.0002 | **0.967** | **reverses** |
| 25 | **T3** | 92.0% | 0.0001 | **0.107** | **reverses** |
| 50 | **T3** | 82.0% | 0.0001 | **0.080** | **reverses** |
| 100 | **T3** | 68.0% | 0.0002 | **0.209** | **reverses** |
| 25 | critical/problematic | 88.0% | 0.0003 | **0.994** | **reverses** |
| 50 | critical/problematic | 80.0% | 0.0001 | **0.991** | **reverses** |
| 25 | any family | 100.0% | 0.0001 | **0.227** | **reverses** |
| 25 | **T2** | 44.0% | 0.0001 | **0.007** | survives |
| 50 | **T2** | 58.0% | 0.0001 | **0.0001** | survives |
| 100 | **T2** | 61.0% | 0.0001 | **0.0001** | survives |
| 50 | any family | 100.0% | 0.0001 | **0.0001** | survives |
| 100 | any family | 99.0% | 0.0001 | **0.0001** | survives |
| 100 | critical/problematic | 77.0% | 0.0001 | **0.018** | survives |
| all | T5 | 4.0% | 0.44–0.57 | 0.94–0.99 | never significant |

**Nine of the eighteen population × N combinations lose their significance.** For T1 the
reversal is emphatic: the meter-preserving null's mean overlap (81.0% at N=25) is *higher*
than what Model 3 achieved (76.0%), so within those meters Model 3's choice of days is, if
anything, marginally worse than chance for polarity.

**What survives is T2.** Observed overlap of 44/58/61% against a meter-preserving null mean
of 21.9/29.0/30.4% — roughly double, at p ≤ 0.007 throughout. That is a genuine day-level
signal: within the meters it selects, Model 3 really does concentrate on current-vs-power
inconsistency days. `any_family` and `critical_or_problematic` also survive at the larger N.

Blocking changed almost nothing (p-values move by at most ~0.04 at N=100). **Meter
composition, not temporal dependence, is what the original null was missing.**

### Standing caveat

This null was computed after Model 3 was frozen and was **not** used to select any feature,
parameter, window or threshold. It changes how the cross-check should be read, not what
Model 3 does. The original global-null lift figures are preserved in
`model3_overlap_lift.csv` as descriptive statistics; the corrected comparison is in
`model3_overlap_lift_corrected_null.csv`. No precision, recall or accuracy is claimed.
