# Task 4 — engineering review loop: SPECIFICATION (v7) — ASSIGNMENT FROZEN

**Status: implemented 2026-09-20. The unlabelled package is built and ready for engineering. No label has been invented and no validation metric has been computed.** Every count below was recomputed from the frozen Model 1 and Model 3 artifacts.

**v3 applies a second set of corrections of 2026-09-20** — the precision uncertainty statement, the Model 3 validation design, `Unsure` reporting and workbook editability. **v2 applied the first set** — the recall estimand, population
reconciliation, the 200-label allocation, and stronger blinding. Each is marked **[1]–[4]**
where it lands.

Task 4 is the first point in this project where **ground truth enters**. Everything before
it — Model 1's severities, Model 2's WAPE, Model 3's ranking — is unlabelled. How the queue
is built therefore determines what can ever be measured.

---

## 0. What Task 4 is, and what it is not

| | |
|---|---|
| **Is** | A labelling instrument, built so the resulting estimates are unbiased and weightable. |
| **Is** | The first ground-truth check either model has had. |
| **Is not** | A ranked worklist. A worklist and an estimation sample are different objects. |
| **Is not** | Owned by the ML engineer. Engineering owns the judgements; ML owns the instrument. |

---

## 1. Corrections to the provided Task 4 instructions

| # | Provided instruction | Problem | Correction |
|---|---|---|---|
| 1 | `combined.sort_values(["severity"], ascending=False)` | **Severity is a string.** Descending lexicographic order is `Review Required > Problematic > Critical > Anomaly` — the *least* urgent first, every Critical buried third. | §5 |
| 2 | `pd.concat([anomaly_review_raw, anomaly_review_triage])` | **Grain mismatch.** Model 1 rows are episodes; Model 3 rows are meter-days. | §3 |
| 3 | Queue = all of Model 1 | **3,928 events** is not a reviewable quantity. | §3, §7 |
| 4 | "at least 20 labeled events" | 20 labels give **±21.9 pp** worst-case, and ~1 label per family × severity cell. | §7 |
| 5 | "compute precision for Model 1" | A flagged-only queue estimates precision but says nothing about what was missed. | §8 |
| 6 | "feed confirmed-fault windows into `exclude_windows`" | Would **reintroduce a fixed defect** — masking starved T4's baseline and hid the ZN.16-PB repair. Model 1 is frozen. | §10 |

---

## 2. Population reconciliation **[2]**

The v1 draft stated **2,834** Model 1 meter-days. **That figure was wrong.** It counted
distinct `(meter, event_START date)` pairs, so an episode spanning 500 days contributed a
single meter-day. Corrected below.

### The observed universe

The observed meter-day universe is a property of `gold.energy_raw` and is identical for both
models; Model 3's feature table is simply where it is already materialised.

| Population | Full history | Within Model 3's scored universe |
|---|---:|---:|
| Observed meter-days (31 meters) | **15,759** | 14,130 |
| Warm-up excluded (Model 3 only) | — | 1,629 |

### Model 1 populations

| Population | Full history | Within M3 scored |
|---|---:|---:|
| **Finding** population (meter × phase × detector) | **405** | — |
| **Event** population (episodes) | **3,928** | — |
| Expanded event-days (meter × day × family) | 20,056 | — |
| Unique **electrical-fault** meter-days | **9,404** | **8,332** |
| Unique **non-commissioning** electrical-fault meter-days | **9,404** | **8,332** |
| **Unflagged** observed meter-days | **6,356** | 5,798 |

Two things that look like errors and are not:

**The two "unique … meter-days" rows are identical by construction.** Model 1's severity
stage rewrites `event_class` to `COMMISSIONING` for any commissioning episode, so no
`ELECTRICAL_FAULT` row carries `commissioning = True`. The two rows measure the same set
under that encoding; they are shown separately only because the correction asked for both.

**Flagged meter-days are not a strict subset of observed meter-days.** 9,404 flagged but
only **9,403** are observed: ZN.19-PB.1 on 2025-10-31 lies inside a Model 1 episode whose
start and end bracket a day on which that meter reported nothing (its next observed day,
2025-11-01, has 11 readings). Hence `9,403 + 6,356 = 15,759` exactly.

> **The sampling frame is therefore `observed ∩ flagged` = 9,403 and `observed − flagged`
> = 6,356.** A day with no telemetry cannot be shown to a reviewer.

By family (non-commissioning electrical-fault meter-days):

| Family | Full history | Within M3 scored |
|---|---:|---:|
| T1 polarity | 3,098 | 2,771 |
| T2 current/power | 1,265 | 1,106 |
| T3 power factor | 7,693 | 6,896 |
| T5 register | 605 | 474 |

Excluded from "flagged" and carried only as context: `COMMISSIONING` 88 meter-days,
`DATA_AVAILABILITY` 2,119, `ELECTRICAL_CHANGE` 1,420.

### Which universe the control stratum draws from **[2]**

The estimand concerns **Model 1**, so the frame is **Model 1's own applicable history**:
the 15,759 observed meter-days, giving **6,356 unflagged**. Model 3's warm-up-restricted
14,130 is *not* used, because Model 3's warm-up is a property of Model 3's training window
and has nothing to do with what Model 1 did or did not flag. The 5,798 figure is recorded
only so the two are never confused.

---

## 3. The review unit, and four strata

Two review units, never blended:

- **Finding-level** for Model 1 — *"is ZN.12-PB phase 3's reverse power a real fault?"* is
  one judgement, not 18 about 18 episodes. 405 findings exist; **255 assert a fault** and
  form the stratum A frame (§7.1).
- **Meter-day-level** for Model 3 and the control — *"was this meter's behaviour on this day
  genuinely unusual?"*

| Stratum | Grain | Source | Population | Estimand |
|---|---|---|---:|---|
| **A** | finding | Model 1 **ELECTRICAL_FAULT** findings, T1/T2/T3/T5 (§7.1) | **255** | Model 1 **precision**, by family and severity |
| **B** | meter-day | Model 3 Top-100 high-ranked **plus same-meter reference days** (§7A) | 99 high / 671 refs | whether Model 3's ranking tracks confirmed faults, **within meter** |
| **C** | meter-day | Model 3 List C, unexplained | **1** | whether Model 3 surfaces anything Model 1 misses |
| **D** | meter-day | Model 1 **unflagged** observed meter-days | **6,356** | `unflagged_fault_rate` — §4 |

Stratum C is kept although it holds a single item; its size *is* the finding — at Top-100,
Model 1 explains 99 of Model 3's 100 highest-ranked meter-days.

---

## 4. The recall estimand, corrected **[1]**

The v1 draft called stratum D a measure of "false negatives / recall". **That was wrong.**

Stratum D estimates one quantity and only one:

```
unflagged_fault_rate  =  P( engineering confirms a fault | Model 1 did not flag that meter-day )
```

This is a **false omission rate**. It is *not* a false-negative rate and *not* Model 1
recall. The difference is not terminological:

| Quantity | Denominator | Obtainable from D? |
|---|---|---|
| `unflagged_fault_rate` (false omission rate) | **unflagged** meter-days | **yes** |
| False-negative rate | **all true faults** | no |
| Recall = TP / (TP + FN) | **all true faults** | no |

Recall needs the count of true faults, which requires labelling flagged **and** unflagged
units *at the same grain*. Stratum A is finding-level and stratum D is meter-day-level, so:

> **Strata A and D must never be combined into a recall calculation.** A precision computed
> over the **255 ELECTRICAL_FAULT finding frame** (§7.1) and an omission rate computed over
> 6,356 meter-days have different denominators, different units and no common divisor.
> Dividing one by the other produces a number with no meaning.

**If meter-day recall is wanted later** it requires a separately designed, same-grain sample
drawing from *both* the 9,403 flagged and the 6,356 unflagged observed meter-days, with
known inclusion probabilities in each. That is a different instrument and is explicitly out
of scope for Task 4 v1.

---

## 5. Ordering, and the severity bug

```python
SEVERITY_RANK = {"Critical": 0, "Problematic": 1, "Anomaly": 2, "Review Required": 3}
worklist.sort_values("severity", key=lambda s: s.map(SEVERITY_RANK))
```

The provided `sort_values(["severity"], ascending=False)` yields
`Review Required → Problematic → Critical → Anomaly`.

**The estimation samples are not sorted by severity at all** — they are randomised (§6).
Ordering a sample by the thing it measures invites reviewers to stop early and truncates the
tail the estimate depends on. Severity ordering belongs to the operational worklist (§9).

---

## 6. Blinding **[4]**

Two **separate randomised sheets**, because the two grains need different blinding regimes.

### Sheet 1 — finding-level estimation sample (stratum A)

Every row here is flagged by definition; there is no flag status to conceal. What is
concealed is the model's **verdict**.

| Shown | Withheld to the key |
|---|---|
| meter, phase, date range | severity |
| measured electrical evidence | magnitude band, corroboration verdict |
| concurrent production classifier status | Model 1's own confidence ordering |

> **Stated limitation.** At finding level the detector family cannot be fully blinded,
> because the evidence a reviewer needs — negative kW with positive current, or a frozen
> register under load — identifies the family by itself. What is blinded is severity and the
> model's confidence. Claiming full blinding here would be false.

### Sheet 2 — meter-day estimation sample (strata B + C + D)

Flagged and unflagged rows are mixed and **must expose exactly the same visible schema**,
or the control is worthless.

**Withheld without exception:**

- Model 1 flag status
- detector family
- severity
- Model 3 score and rank
- stratum
- **any model-written description**, because a sentence like *"reverse power from
  2026-06-03"* reveals the row was flagged

**Shown:** a neutral row identifier, meter, Saudi date, and raw electrical evidence computed
**uniformly for every row from Gold** — reading count, coverage, mean load %CB, per-phase
current and power summaries, power-factor summaries, negative-power counts, production
classifier status counts.

> **Design consequence.** Because the evidence must be computed the same way for flagged and
> unflagged rows, it **cannot** be lifted from Model 1 event records — those exist only for
> flagged rows and their presence would be the tell. Sheet 2's evidence columns are derived
> from the Model 3 feature table and raw Gold aggregates, which exist for every observed
> meter-day.

The key (`task4_queue_key.parquet`) is held by the ML side and joined back only after labels
return.

---

## 7. Allocation, and the frozen stratum A design

### 7.1 Stratum A frame — a correction

Stratum A asks *"is this a confirmed fault?"*. That question only applies to findings that
**assert** a fault, and not every Model 1 finding does:

| Family | ELECTRICAL_FAULT | COMMISSIONING | ELECTRICAL_CHANGE | DATA_AVAILABILITY |
|---|---:|---:|---:|---:|
| T1 | 14 | 16 | 0 | 0 |
| T2 | 72 | 12 | 0 | 0 |
| T3 | 137 | 0 | 0 | 0 |
| T5 | 32 | 3 | 0 | 0 |
| **T4** | **0** | 0 | **88** | **31** |

**T4 asserts no fault at all** — its 119 findings are level shifts and telemetry outages.
Asking engineering to confirm a telemetry outage as a fault is a category error, so T4 is
excluded from stratum A and routed to the operational worklist instead.

The 31 commissioning findings are also held out: Model 1 explicitly does not assert them as
faults and caps them at Review Required. Testing the 2024-12-31 commissioning assumption is
worthwhile but is a **different estimand** needing its own sub-sample — recorded as an open
item (§14) rather than silently folded into a precision figure.

> **Stratum A frame = 255 ELECTRICAL_FAULT findings across T1, T2, T3, T5.**

### 7.2 The frozen allocation algorithm

Fixed before any sampling, and fully deterministic:

1. `base = floor(110 / 4) = 27`. Give each family `min(base, N_family)`.
2. Redistribute any shortfall one unit at a time to the family with the most unused room,
   ties broken by family name.
3. Within a family, give every non-empty severity cell `min(2, N_h)`, then award the
   remainder one unit at a time to the cell with the most unused room, ties broken by cell
   size then severity name.
4. `pi_h = n_h / N_h` is the inclusion probability for **every finding** in cell *h*.

**Frozen allocation and inclusion probabilities:**

| Family | Severity | N_h | n_h | pi_h | weight 1/pi_h |
|---|---|---:|---:|---:|---:|
| T1 | Anomaly | 1 | 1 | 1.0000 | 1.00 |
| T1 | Critical | 12 | 12 | 1.0000 | 1.00 |
| T1 | Review Required | 1 | 1 | 1.0000 | 1.00 |
| T2 | Anomaly | 24 | 7 | 0.2917 | 3.43 |
| T2 | Critical | 2 | 2 | 1.0000 | 1.00 |
| T2 | Problematic | 13 | 2 | 0.1538 | **6.50** |
| T2 | Review Required | 33 | 16 | 0.4848 | 2.06 |
| T3 | Anomaly | 40 | 11 | 0.2750 | 3.64 |
| T3 | Critical | 38 | 9 | 0.2368 | 4.22 |
| T3 | Problematic | 48 | 20 | 0.4167 | 2.40 |
| T3 | Review Required | 11 | 2 | 0.1818 | 5.50 |
| T5 | Critical | 32 | 27 | 0.8438 | 1.19 |
| | **total** | **255** | **110** | | |

Family totals: **T1 14 of 14 (a census)**, T2 27 of 72, T3 42 of 137, T5 27 of 32.
Inclusion probabilities span **0.1538 to 1.0000**, so design weights span **1.00 to 6.50**.

### 7.3 The precision interval — corrected

**The v2 draft claimed +/-6.9 pp from 200 labels. That was wrong.** The 200-label budget is
the whole project; **only stratum A's 110 labels estimate Model 1 precision.**

| Statement | Status |
|---|---|
| +/-6.9 pp from 200 labels | **withdrawn** |
| +/-9.3 pp from 110 simple-random observations | **intuition only, not the reported interval** |
| **Survey-weighted linearisation with FPC** | **the reported interval** |
| FPC-aware stratified bootstrap | secondary cross-check only |

Stratum A is stratified with **unequal inclusion probabilities spanning 6.5x**, so a simple
binomial interval is the wrong variance. The point estimate is a weighted ratio estimator
over resolved cases,

```
precision_hat = sum(w_i * y_i) / sum(w_i),    w_i = 1 / pi_h(i)
```

**The reported interval is survey-weighted linearisation with a finite-population
correction.** For a ratio estimator under stratified sampling without replacement,

```
Var(R) ~= (1 / (sum w)^2) * sum_h [ N_h^2 * (1 - f_h) / n_h * s2_h ],   f_h = n_h / N_h
```

with `e_i = y_i - R` and `s2_h` the within-cell sample variance of `e`. The `(1 - f_h)`
factor is **exactly zero when `f_h = 1`**, so a census cell contributes **no sampling
variance at all** — which is correct, because every unit in it was examined. Four of the
twelve cells are censuses (all three T1 cells and T2 Critical).

A **finite-population-aware stratified bootstrap** runs as a **secondary cross-check**: it
holds census cells **fixed** across replicates rather than resampling them, and rescales
each non-census cell's deviations by `sqrt(1 - f_h)`. It is reported alongside the primary
interval, never in place of it.

**A simple binomial interval is never the reported figure.** Quoting
`1.96*sqrt(p(1-p)/n)` would treat a stratified design with inclusion probabilities spanning
6.5x as though it were a simple random sample, and would additionally attribute sampling
variance to cells that have none.

The +/-9.3 pp figure appears once, labelled *"simple-random intuition only"*, and is never
used as the interval.

### 7.4 Full allocation

| Stratum | Rule | Today | Population | Limitation |
|---|---|---:|---:|---|
| **A** | fixed 110, per §7.2 | 110 | 255 | none; T1 is a census at 14 of 14 |
| **D** | fixed 40 | 40 | 6,356 | none |
| **C** | census, capped at 20 | **1** | 1 | **population-limited** — one unexplained item at Top-100 |
| **B** | **50 - C**, split high-ranked / reference | **49** = 25 + 24 | 99 high, 671 refs | none |
| | **total** | **200** | | |

Any stratum unable to fill its allocation records `allocation_requested`,
`allocation_available` and `allocation_drawn`, and is **never back-filled** from another
stratum — that would break the inclusion probabilities.

### 7.5 What the other strata buy

For stratum D, 40 controls with zero confirmed faults put the 95% upper bound on
`unflagged_fault_rate` at **7.2%**; at 20 controls it would be only 13.9%.

Per-family precision at 27 labels is directional only and is always reported with its
linearised FPC interval.

---

## 7A. Stratum B — the Model 3 validation design

**Stratum D is not the Model 3 control.** D is a uniform random draw from the 6,356
Model-1-unflagged meter-days; its estimand is `unflagged_fault_rate`, and it is spread
thinly across all 31 meters, so it cannot answer "did Model 3 rank the right days *within a
meter*".

The Model 3 budget stays at **50**: `C` = census of unexplained Top-100 items (capped at
20), and the remaining `50 - C` is a **blinded mixture of high-ranked days and same-meter
lower-ranked reference days**. Today C = 1, giving **25 high-ranked + 24 reference**.

### The reference-selection rule, frozen before any label is seen

A reference day must:

1. come from the **same meter** as a selected high-ranked day;
2. lie in that meter's **own bottom quartile** of `window_anomaly_pct`;
3. be **at least 14 days** from every high-ranked day selected for that meter, so a
   reference cannot fall inside the same episode;
4. come from the 14,130-day scored universe.

**Why the contrast is relative, not absolute.** The v2 sketch implied an absolute gap
("sufficiently lower"). Measured, an absolute 0.40 gap is **impossible** for two of the six
meters involved:

| Meter | min `window_anomaly_pct` | q25 | refs under an absolute 0.40 gap | refs under the bottom-quartile rule |
|---|---:|---:|---:|---:|
| ZN.10-PB.1 | **0.707** | 0.855 | **0** | 117 |
| ZN.11-PB.2 | 0.370 | 0.809 | 3 | 106 |
| ZN.12-PB | 0.044 | 0.646 | 50 | 113 |
| ZN.10-PB.2 | 0.009 | 0.422 | 125 | 96 |
| ZN.1-PB.1 | 0.003 | 0.560 | 123 | 123 |
| ZN.16-PB | 0.306 | 0.907 | 14 | 116 |

ZN.10-PB.1 has never scored below 0.707 in its entire history, so no day of that meter is
0.40 below its high-ranked days. An absolute floor would silently drop the meter from the
validation altogether. The bottom-quartile rule yields **671 available references against
the 24 needed**.

**The realised contrast is recorded per pair, not assumed.** Minimum realised contrast by
meter: ZN.10-PB.2 0.577, ZN.1-PB.1 0.440, ZN.12-PB 0.353, ZN.11-PB.2 0.190,
ZN.10-PB.1 0.144, ZN.16-PB 0.091. The ZN.16-PB pair is thin and is reported as such rather
than dropped, since that meter contributes a single high-ranked item.

### Analysis — within meter, never pooled

For each meter, compare confirmed-fault outcomes for its high-ranked days against its own
reference days, then combine across meters with a **stratified (per-meter) procedure** — an
exact conditional test such as Mantel-Haenszel, or a per-meter paired bootstrap.

A pooled rank-versus-label statistic is **forbidden**. The corrected permutation null
already demonstrated that pooling recovers meter composition rather than day selection: T1
and T3 significance reversed entirely once composition was held fixed, and only T2 survived.

---

## 8. What labels can and cannot establish

| Quantity | Estimable? | From |
|---|---|---|
| Model 1 precision, overall | **yes** | A, weighted ratio estimator + survey-weighted linearisation with FPC (§7.3) |
| Model 1 precision, per family | directional only, with its linearised FPC interval | A |
| `unflagged_fault_rate` (false omission rate) | **yes** | **D alone** |
| Model 1 **recall** | **no** — needs a same-grain flagged+unflagged design (§4) | — |
| Model 3 ranking validity | **yes, within meter** | **B only** — high-ranked vs same-meter reference days (§7A). **Not D.** |
| Model 2 forecast accuracy | **no** — forecasting is not fault detection | — |

The Model 3 row carries a constraint from the corrected permutation null: Model 3's apparent
agreement with Model 1 was **largely meter composition, not day selection** — T1 and T3
significance reversed once composition was held fixed, and only T2 survived. Any label-based
validation of Model 3 must therefore be computed **within meter**, or it recovers the same
artifact.

---

## 9. Two outputs, not one

| Artifact | Purpose | Ordering | Blinded |
|---|---|---|---|
| `task4_labelling_sample.xlsx` — sheet 1 (findings), sheet 2 (meter-days) | estimation | randomised within each sheet | **yes**, per §6 |
| `task4_worklist.xlsx` | fixing things | severity rank, then Model 3 rank | **no** |

`.xlsx` for both: engineering edits directly and it avoids CSV encoding round-trips.

**Editability, resolved.** One workbook is generated **per reviewer**, with `reviewer_id`
**pre-populated and locked** — if reviewers could type it, the 10% double-labelled overlap
sample could be mis-attributed and the kappa estimate would be meaningless. The file name and
the key both carry the same reviewer id, so attribution is verifiable without trusting a cell.

| Column | Locked? |
|---|---|
| `review_id`, all context and evidence columns | locked |
| `reviewer_id` | **locked, pre-populated** |
| `confirmed_fault`, `fault_type`, `notes`, `reviewed_at` | **unlocked** |

`reviewed_at` is unlocked because only the reviewer knows when they judged a row, and a
locked cell cannot be auto-stamped without macros. If it is returned blank, ingest falls
back to the workbook's return timestamp and sets `reviewed_at_imputed = True` rather than
inventing a date silently.

---

## 10. The feedback loop, corrected

Feeding confirmed faults into `model1_config.yaml`'s `exclude_windows` **must not be
implemented**. Model 1 v1 is frozen, and masking known fault windows is precisely what
starved T4's baseline and made the ZN.16-PB repair undetectable; the frozen implementation
deliberately uses an unmasked trailing baseline with `baseline_gap_days: 7`.

Labels instead feed: the **acceptance set** (a confirmed Tier-B finding is promoted to Tier
A with an engineering reference); the **commissioning boundary** (2024-12-31 is currently an
assumption); the **severity definition** (whether confirmed faults cluster by band); and a
**future Model 1 v2**, which would need its own freeze.

---

## 11. Label schema

| Column | Filled by | Values |
|---|---|---|
| `review_id` | ML | stable opaque id; the only join key |
| neutral context and evidence columns | ML | §6 |
| **`confirmed_fault`** | **engineering** | `Y` / `N` / `Unsure` |
| **`fault_type`** | **engineering** | free text or short controlled list |
| **`notes`** | **engineering** | free text |
| `reviewer_id` | **pre-populated per copy, locked** | see below |
| `reviewed_at` | **engineering, unlocked** | date |

`Unsure` is a first-class outcome and is **never silently discarded**. Four quantities are
reported together, always:

| Reported quantity | Definition |
|---|---|
| **resolved-case estimate** | weighted precision over `Y` and `N` only, `Unsure` excluded from the denominator |
| **weighted `Unsure` rate** | design-weighted share of sampled findings labelled `Unsure` |
| **conservative bound** | every `Unsure` counted as `N` |
| **optimistic bound** | every `Unsure` counted as `Y` |

The conservative and optimistic bounds bracket the truth whatever the unresolved cases turn
out to be, so a high `Unsure` rate widens the reported range rather than quietly improving
the headline. Reporting only the resolved-case figure would inflate precision by removing
exactly the hardest cases.

A **10% overlap sample** is double-labelled to estimate Cohen's kappa; a precision figure is
only as good as the reproducibility of the judgement behind it.

**A named engineering adjudicator is required before collection begins** (approved). They
resolve `Unsure` and inter-reviewer disagreement.

---

## 12. Tests

| Area | Criterion |
|---|---|
| Severity ordering | `Critical` sorts first; a string sort is asserted **wrong**, so the bug cannot return |
| Estimand separation | no artifact or function combines stratum A with stratum D into a recall figure |
| Naming | the string `recall` never appears on a stratum-D output; the field is `unflagged_fault_rate` |
| Control frame | stratum D draws from the **6,356** full-history unflagged meter-days, not the 5,798 scored subset |
| Frame integrity | every sampled meter-day is an **observed** meter-day; the ZN.19-PB.1 2025-10-31 case is excluded |
| Reconciliation | 9,403 observed-flagged + 6,356 unflagged = 15,759, asserted |
| Allocation | requested total is exactly 200 for any C in 0..20; `B = 50 − C` |
| Shortfall | a stratum unable to fill its allocation records it and is never back-filled |
| Blinding, sheet 2 | contains no flag status, family, severity, Model 3 score/rank, stratum or model-written description |
| Schema identity | flagged and unflagged rows in sheet 2 have identical column sets and no tell-tale nulls |
| Sheet separation | finding-level and meter-day-level rows never share a sheet |
| Inclusion probabilities | every sampled row carries a non-zero recorded probability; weights sum to the stratum population |
| Join integrity | every returned label re-joins to exactly one key row; unmatched labels fail loudly |
| `Unsure` | all four quantities reported: resolved-case, weighted rate, conservative (all N), optimistic (all Y) |
| `Unsure` | no code path drops an `Unsure` row without recording it |
| Stratum A frame | contains only `ELECTRICAL_FAULT` findings in T1/T2/T3/T5; no T4 and no commissioning finding |
| Allocation determinism | the frozen algorithm reproduces the §7.2 table exactly from the findings file |
| Inclusion probabilities | every sampled finding carries `pi_h = n_h / N_h`; weights span 1.00 to 6.50 |
| Precision interval | the reported interval comes from **survey-weighted linearisation with FPC**, never from `1.96*sqrt(p(1-p)/n)` |
| Precision interval | a census cell (`pi_h = 1`) contributes **exactly zero** sampling variance |
| Precision interval | the FPC-aware bootstrap is a **secondary cross-check** and holds census cells fixed |
| Precision interval | the simple +/-9.3 pp figure is labelled "simple-random intuition only" wherever it appears |
| Stratum B references | every reference is the **same meter**, in that meter's own bottom quartile, and >= 14 days from every high-ranked day for that meter |
| Stratum B contrast | the realised contrast is recorded per pair, and no absolute gap floor is imposed |
| Stratum B analysis | no pooled rank-vs-label statistic is computed; the test is stratified by meter |
| Stratum D isolation | stratum D rows are never used in the Model 3 ranking validation |
| Workbook editability | `reviewer_id` is pre-populated and locked; `confirmed_fault`, `fault_type`, `notes` and `reviewed_at` are unlocked; every other cell is locked |
| Workbook editability | a returned blank `reviewed_at` sets `reviewed_at_imputed = True` rather than inventing a date |
| Idempotence | rebuilding from the same artifacts and seed is byte-identical |
| No write-back | Task 4 writes nothing into `model1_config.yaml` or any frozen artifact |

---

## 13. Definition of Done

### 13.1 Built, tested and frozen

- [x] `src/review_loop/build_queue.py` — strata, recorded inclusion probabilities, blinding,
      both workbooks
- [x] `config/task4_config.yaml` — budget, the frozen allocation rule, seed, quotas,
      reference-selection rule, assignment contract
- [x] `outputs/<ts>/task4_allocation_stratum_a.csv` and `task4_allocation_stratum_b.csv` —
      the frozen family x severity table with `N_h`, `n_h` and `pi_h`, written **before** any
      row is drawn, alongside `task4_allocation_report.csv` (requested / available / drawn)
- [x] `outputs/<ts>/task4_worklist.xlsx` — un-blinded, severity-ordered
- [x] `outputs/<ts>/task4_queue_key.parquet` — withheld key, updated with assignments
- [x] `src/review_loop/assignment.py` — reviewer assignment frozen: 200 unique units,
      20 double-reviewed, 110 / 110 workload, reproducible from seed `20260926`
- [x] `tests/test_task4.py`, `tests/test_task4_assignment.py` — §12 passing
- [x] `run_metadata.json` — population reconciliation, allocation requested/available/drawn
      per stratum, seed, and explicit statements that no label exists yet,
      that no precision or recall is claimed, that stratum D measures
      `unflagged_fault_rate` only, and that the precision interval will come from a
      survey-weighted linearisation with finite-population correction, cross-checked by
      an FPC-aware stratified bootstrap, and never from a simple binomial

### 13.2 Blocked on the named reviewer and adjudicator identities

These stay unchecked **by design**, not because work is outstanding on my side. Each one
needs the two real reviewer identifiers and the named adjudicator; none of them requires a
model rerun, a redraw, or a change of assignment.

- [ ] `config/task4_config.yaml` — real reviewer identifiers replacing `reviewer_1` and
      `reviewer_2`, and the named adjudicator replacing `adjudicator: TBD`
- [ ] `run_metadata.json` — named adjudicator recorded
- [ ] `outputs/<ts>/task4_labelling_sample_<reviewer>.xlsx` — one per reviewer, two
      randomised sheets, `reviewer_id` pre-populated and locked. **Built and verified, but
      written only as `_DRAFT` copies under placeholder identifiers**: `issuable` is `false`
      and `issue_workbooks.py` exits non-zero until the identities are supplied
- [ ] Delivered to engineering; **collection is theirs**

Estimation from returned labels is a **separate stage**.

---

## 14. Decisions

| # | Decision | Status |
|---|---|---|
| 1 | Target 200 labels | **approved** |
| 2 | Blinding | **approved** |
| 3 | Blind control stratum | **approved** |
| 4 | Model 1 review unit = finding | **approved** |
| 5 | Labels cannot modify frozen Model 1 v1 | **approved** |
| 6 | Named engineering adjudicator required before collection | **approved** |
| 7 | Stratum D estimand is `unflagged_fault_rate`, never recall | **corrected in v2** |
| 8 | Control frame is Model 1's own 15,759-day universe | **corrected in v2** |
| 9 | `A=110, D=40, C=census≤20, B=50−C` | **corrected in v2** |
| 10 | Sheet-2 blinding withholds family, description and flag status | **corrected in v2** |
| 11 | Precision interval: +/-9.3 pp is intuition only; +/-6.9 pp withdrawn | **corrected in v3** |
| 11a | Primary CI is **survey-weighted linearisation with FPC**; the FPC-aware stratified bootstrap is a **secondary cross-check**; a simple binomial CI is never reported | **corrected in v7** |
| 12 | Stratum A frame = 255 ELECTRICAL_FAULT findings; T4 and commissioning findings excluded | **corrected in v3** |
| 13 | Family x severity allocation and every inclusion probability frozen before sampling | **corrected in v3** |
| 14 | Stratum B = 25 high-ranked + 24 same-meter bottom-quartile references; D is not the Model 3 control | **corrected in v3** |
| 15 | Reference contrast is within-meter relative, not an absolute gap | **corrected in v3** |
| 16 | `Unsure` reported four ways, never discarded | **corrected in v3** |
| 17 | `reviewer_id` pre-populated and locked per copy; `reviewed_at` unlocked | **corrected in v3** |
| 18 | Commissioning-assumption check needs its own sub-sample | **open** |

---

## 15. Final contract corrections, v4

### 15.1 Abnormality is not the same thing as a fault

Model 3 is an **anomaly-triage ranker**, not a fault classifier. Asking "was this a
confirmed fault?" about a Model 3 item measures the wrong thing: a day can be genuinely
abnormal — a shutdown, a commissioning visit, a telemetry outage — without being an
electrical fault, and Model 3 is not claiming otherwise.

The meter-day sheet therefore carries **three** label columns:

| Column | Values |
|---|---|
| `engineering_abnormality` | `Y` / `N` / `Unsure` |
| `electrical_fault` | `Y` / `N` / `Unsure` |
| `abnormality_type` | Electrical fault / Data availability / Operational change / Commissioning / Normal / Other |

| Estimand | Outcome used |
|---|---|
| Stratum D `unflagged_fault_rate` | **`electrical_fault`** |
| Stratum B within-meter high vs reference, **primary** | **`engineering_abnormality`** |
| Stratum B electrical-fault enrichment, **secondary** | `electrical_fault` |

The four-way `Unsure` reporting (resolved-case, weighted rate, conservative, optimistic) is
applied **separately to whichever outcome is being estimated**, never pooled across the two.

The findings sheet keeps `confirmed_fault`, because Model 1 *does* assert a fault and that
is the claim under test.

### 15.2 The allocation is integer-exact

`base = floor(110 / 4) = 27`, then the documented one-unit-at-a-time redistribution. It
reproduces the frozen table exactly and is asserted on every run:

**T1 = 14, T2 = 27, T3 = 42, T5 = 27, total 110**, over the 255-finding frame, with
inclusion probabilities from **0.1538 to 1.0000**. The build refuses to continue if either
the family totals or the total differ from the frozen values.

### 15.3 The precision interval is finite-population aware

A naive with-replacement bootstrap is **wrong for this design**. Four of the twelve cells
are censuses — all three T1 cells and T2 Critical — and a census has **zero sampling
variance**, because every unit was examined. Resampling it would invent variability that
does not exist and inflate the interval.

| Property | Implementation |
|---|---|
| Point estimate | weighted ratio `sum(w·y) / sum(w)`, unchanged |
| Primary interval | survey-weighted linearisation with FPC: the `(1 − f_h)` factor is exactly 0 when `f_h = 1` |
| Cross-check | stratified bootstrap that holds census cells **fixed** across replicates and rescales non-census cells by `sqrt(1 − f_h)` |
| Singleton non-census cells | reported by name, never silently dropped |
| `Unsure` bounds | unchanged, applied per outcome |

Tested: a census-only design returns `se = 0.0` and a bootstrap interval of zero width; a
high sampling fraction yields a strictly narrower interval than a low one.

### 15.4 Stratum B sampling, frozen before any row was drawn

| Decision | Rule | Result |
|---|---|---|
| High rows from the 99 | eligible meters only (≥2 high pool **and** ≥2 reference pool), floor 2, cap 6, remainder by most unused room | **25 across 7 meters** |
| High rows per meter | ZN.10-PB.1 4, ZN.10-PB.2 4, ZN.11-PB.2 4, ZN.12-PB 4, ZN.16-PB 3, ZN.17-PB 4, ZN.8-PB.2 2 | π from 0.1667 to 1.0000 |
| Reference rows | floor 1 per participating meter, remainder by most unused room, capped at 3× that meter's high allocation | **24** |
| Reference pool | same meter, that meter's own bottom quartile, ≥14 days from every high-ranked day of that meter | π from 0.0081 to 0.0746 |
| Seeds | `stratum_b_high: 20260922`, `stratum_b_reference: 20260923` | fixed in config |

Selection is **random within each frozen cell**: the allocation decides how many, the seed
decides which. Three meters (ZN.1-PB.1, ZN.5-PB, ZN.7-PB) contribute a single high-ranked
row each and are excluded, because one row cannot support a within-meter comparison.

**No selection decision anywhere depends on an engineering label**, and none could — the
label columns are empty.

---

## 16. Build record, 2026-09-20

| Stratum | Requested | Available | Drawn | Shortfall |
|---|---:|---:|---:|---:|
| A — Model 1 findings | 110 | 255 | **110** | 0 |
| B — Model 3 high + reference | 49 | 1,121 | **49** | 0 |
| C — unexplained census | 20 | **1** | **1** | 19 (population-limited) |
| D — blind control | 40 | 6,356 | **40** | 0 |
| | | | **200** | |

Population reconciliation, asserted at build time: 15,759 observed meter-days = 9,403
observed-and-flagged + 6,356 unflagged, with one flagged day (ZN.19-PB.1, 2025-10-31)
falling on a day that meter reported nothing.

**Artifacts** — `outputs/task4_20260920T102354Z/`:

| File | Contents |
|---|---|
| `task4_allocation_stratum_a.csv` / `_b.csv` | the frozen allocations, written **before** sampling |
| `task4_allocation_report.csv` | requested / available / drawn / shortfall per stratum |
| `task4_labelling_sample_reviewer_1.xlsx`, `_reviewer_2.xlsx` | blinded, two sheets, protected |
| `task4_worklist.xlsx` | un-blinded, all 405 findings, severity-ordered |
| `task4_queue_key.parquet` | withheld key, 200 rows |
| `run_metadata.json` | reconciliation, allocations, digests of every frozen artifact |

Sheet shapes: findings 110 rows × 13 visible + 4 label columns; meter_days 90 rows × 21
visible + 5 label columns. All label cells are empty and unlocked; every other cell is
locked; `reviewer_id` is pre-populated and locked.

**Still blocking collection:** the adjudicator is recorded as `TBD` and must be named
before the workbooks are issued.

---

## 17. Reviewer assignment contract

The 200 sampled units, their inclusion probabilities and the allocation tables are **frozen
and untouched**. Assignment decides *who* reviews a unit; it cannot change which units exist
or what any of them weighs. The build verifies that explicitly and refuses to re-issue if a
single inclusion probability moves.

### 17.1 The rule

Assignment is stratified by **(sheet, stratum)**, so neither reviewer receives a skewed mix
and the overlap sample spans strata rather than landing entirely in one:

1. Allocate the ~10% overlap across (sheet, stratum) in proportion to size, by largest
   remainder, ties broken on stratum size then position.
2. Within each group, permute with the fixed seed; the first `n_overlap` become
   double-reviewed.
3. Alternate the remainder between the two reviewers, flipping which reviewer starts on
   each group so workloads stay level.

Seed `20260926`, fixed in `config/task4_config.yaml`. Re-running reproduces the assignment
exactly; a different seed produces a different one. Both are tested.

### 17.2 What was assigned

| | Units | Sole | Double-reviewed |
|---|---:|---:|---:|
| findings — reviewer 1 | 61 | 50 | 11 |
| findings — reviewer 2 | 60 | 49 | 11 |
| **findings, unique** | **110** | 99 | **11** |
| meter_days — reviewer 1 | 49 | 40 | 9 |
| meter_days — reviewer 2 | 50 | 41 | 9 |
| **meter_days, unique** | **90** | 81 | **9** |
| **total unique** | **200** | **180** | **20** |

**20 of 200 double-reviewed — exactly the 10% target.** Total assignments 220. Reviewer 1
holds 110 units, reviewer 2 holds 110: neither receives all 200. **The union of reviewer
assignments covers all 200 unique units; 20 units are intentionally assigned to both
reviewers.**

Overlap by stratum: findings **A 11**, meter-days **B 4**, **C 1**, **D 4**.

### 17.2a Stratum C is forced into the overlap

Proportional allocation gave the single stratum C unit no overlap. Because it is the
**only unexplained Model-3 Top-100 item**, it is now forced into the double review as a
**governance and quality check**, and the total is held at exactly 20 by releasing one
stratum B overlap.

Which B unit is released follows from the seed already in use, not a new decision: the
per-group permutation is unchanged, so reducing B's overlap count by one drops exactly
the **last unit B had admitted** — its most marginal inclusion. Measured, the swap is
one-for-one:

| | review_id | meter | date | stratum |
|---|---|---|---|---|
| promoted to double review | **D0050** | ZN.10-PB.2 | 2025-05-31 | C |
| released to single review | **D0043** | ZN.17-PB | 2025-03-30 | B |

D0043 is still reviewed — by one reviewer instead of two. Nothing is dropped.

> **The C double review is a quality check, not an estimate.** With n = 1 there is no
> agreement to measure, and `agreement_report` refuses to produce one: any breakdown with
> fewer than `min_pairs_for_agreement` (5) pairs is returned as **NOT ESTIMABLE** with
> `kappa = NaN`, rather than printing a number that would read as 100% or 0% agreement.
> What the double review buys is the assurance that two people looked at the one item
> Model 3 surfaced and Model 1 cannot explain.

A double-reviewed unit keeps **one `review_id`** across both copies, so the two judgements
join on it directly. Assignments live in the withheld key
(`assigned_to`, `is_overlap`) and in `task4_reviewer_assignment.csv`.

### 17.3 Agreement reporting

Both statistics are reported, per sheet and per label column, because they answer different
questions:

| Statistic | What it says |
|---|---|
| **raw agreement** | the share of double-reviewed units the two reviewers labelled the same. Needs no assumption and is easy to read. |
| **Cohen's kappa** | agreement corrected for what chance would produce. Matters when one category dominates. |
| **bootstrap interval on kappa** | reported so the instability is visible rather than implied. |

Both are **DIAGNOSTIC**. With 11 double-reviewed findings and 9 meter-days the intervals are
very wide, and kappa is additionally subject to the *kappa paradox*: with one dominant
category it can sit near zero at 90% raw agreement. They indicate whether the labelling task
is reproducible enough to estimate from — not what the agreement is.

### 17.4 Identities — the remaining blocker

`reviewer_1`, `reviewer_2` and `adjudicator: TBD` are **placeholders**, and the issuance
script treats them as a hard gate:

* `identity_status()` refuses to mark the package issuable;
* the workbooks are written with a **`_DRAFT` suffix**;
* the exit code is non-zero.

This is not bookkeeping. A placeholder reviewer id makes the 20 double-labelled units
un-attributable, which is the one thing the overlap design exists to support; and an unnamed
adjudicator leaves `Unsure` and disagreement with no owner.

**Supplying the real names is a config edit plus one re-run of
`issue_workbooks.py`.** No unit is redrawn, no probability changes, and the assignment is
reproduced identically from the seed.

---

## 18. Status

**ASSIGNMENT FROZEN — DRAFT pending named reviewer/adjudicator identities.**

| Component | State |
|---|---|
| 200 sampled units, inclusion probabilities, allocation tables | frozen, verified unchanged |
| Reviewer assignment | complete, 20 overlap, seed-reproducible |
| Blinded workbooks | built, partitioned, label cells empty and unlocked |
| Un-blinded worklist | built, severity-ordered, all 405 findings |
| Withheld key | updated with assignments |
| Models 1, 2, 3 | frozen, byte-identical |
| Reviewer and adjudicator names | **outstanding** |
| Precision, `unflagged_fault_rate`, Model 3 validation, agreement | **not computed** — no labels exist |

---

## 19. Assignment freeze, v6

The reviewer assignment is **FROZEN**. The adjustment changed who reviews two units and
nothing else.

| | |
|---|---|
| Sampled units | **200, unchanged** — none redrawn |
| Inclusion probabilities | **unchanged**, verified before and after |
| Allocation tables | **unchanged** |
| Models 1, 2, 3 | **frozen, byte-identical** |
| Overlap | **20**: A 11, B 4, C 1, D 4 |
| Workload | reviewer 1 **110**, reviewer 2 **110** |
| Reproducibility | identical on re-run from seed `20260926`; a different seed differs |

### A bug the adjustment surfaced

Naming the donor stratum as its own forced stratum made the forcing **silently cancel**: the
+1 and the −1 offset exactly, C ended with no overlap, and nothing complained. The
implementation now refuses that configuration with an explicit error, and a test locks it.
It was never live in this package — the configured donor has always been B — but the failure
mode would have been invisible.

### Remaining blocker, unchanged

`reviewer_1`, `reviewer_2` and `adjudicator: TBD` are placeholders. The package stays
**`_DRAFT`**, `issuable` is `false`, and the issuance script exits non-zero. Supplying the
two real reviewer identifiers and the named adjudicator is a config edit plus one re-run;
the assignment reproduces identically from the seed.

**No precision, `unflagged_fault_rate`, Model 3 validation or agreement has been computed.**
All of them wait for returned labels.

---

## 20. Precision-interval contract, v7

One documentation and test-contract cleanup. **Nothing was recomputed**: no unit redrawn, no
assignment changed, no inclusion probability moved, no model rebuilt, and no statistical
metric calculated — there are still no labels.

The v3 wording made the stratified bootstrap the primary interval and demoted linearisation
to "an acceptable alternative". That was backwards, and it mattered: a with-replacement
bootstrap across census cells invents sampling variance that does not exist.

| Role | Method |
|---|---|
| **Primary reported CI** | survey-weighted linearisation with finite-population correction |
| **Census cells (`pi_h = 1`)** | contribute **exactly zero** sampling variance and are excluded from the variance sum |
| **Secondary cross-check** | FPC-aware stratified bootstrap: census cells held fixed, non-census cells rescaled by `sqrt(1 - f_h)` |
| **Never reported** | simple binomial `1.96*sqrt(p(1-p)/n)` |
| Unchanged | the weighted ratio point estimate, and the four-way `Unsure` bounds |

Aligned in §7.3, §7.5, §8, the test table in §12, the Definition of Done, the decisions
table, and the run metadata. The implementation in `src/review_loop/estimation.py` already
matched this contract — `linearised_variance` is the primary and
`fpc_stratified_bootstrap` the cross-check — so only the prose and the test wording were
out of step.

**Status: `ASSIGNMENT FROZEN — DRAFT pending named reviewer/adjudicator identities`**
