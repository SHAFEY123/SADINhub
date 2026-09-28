# SADINhub — Founder Briefing
**What we built, what we found, what it means for the business, and what's next**
*Written for a non-technical read. No SQL, no model names required to follow this.*

---

## 1. The one-paragraph version

We took ~19 months of raw electricity meter data from the facility (31 meters, over 4.5 million individual readings) and turned it into three things: (1) a trustworthy, cleaned dataset you can actually rely on, (2) a set of dashboards showing consumption, cost drivers, and equipment health, and (3) an early-stage AI layer that tries to forecast next-day energy use and flag unusual meter behavior automatically. The data-cleaning and dashboard work is solid and verified. The AI forecasting work honestly isn't beating a simple guess yet — and we know exactly why, and exactly what to do about it. That's not a setback; it's the normal, useful first result of doing this rigorously instead of rushing to a headline number.

---

## 2. What problem this solves

Before this project, the facility's electricity data sat in raw form across ~109 million individual sensor readings — not usable for reporting, not usable for spotting problems, not usable for prediction. This project turns that raw stream into:

- **Reliable reporting** — "how much electricity did we use, where, and when" — that you can trust down to the decimal, because every number has been independently checked at least twice.
- **Problem-finding** — surfacing electrical issues (faulty wiring, misconfigured sensors, overloaded circuits) that were previously invisible, some of which likely represent real maintenance or safety items.
- **Early prediction** — a first attempt at forecasting tomorrow's energy use and flagging days that look abnormal, which is the foundation for cost forecasting, anomaly alerts, and eventually automated recommendations.

---

## 3. What's solid and ready to use today

**The data pipeline itself.** Every number in the dashboards has been checked five different ways and they all agree exactly. If a dashboard says a meter used X kWh in a given month, that number is trustworthy — not an estimate, not a rough aggregation.

**The dashboards (Power BI, 8 pages).** These are live and usable now for day-to-day reporting: consumption by meter/zone, weekday vs. weekend patterns, daytime usage cycles, and — importantly — a dedicated view for flagging meters with abnormal or negative power readings, so maintenance/engineering can investigate specific equipment.

**Electrical problem-finding.** This is arguably the most immediately valuable output so far. We found:
- **One confirmed wiring fault** (a meter called ZN.16), already verbally confirmed by the engineering team — it's been drawing power incorrectly across all three of its electrical phases.
- **Three more strong candidates** for similar issues on other meters, not yet confirmed but backed by consistent evidence across multiple independent measurements — worth an engineering walk-through.
- **One meter (ZN.20) with the single largest data-quality issue in the whole facility** — its current sensor readings don't match its power readings about 19% of the time on one phase. This alone is worth prioritizing for an electrician's visit.
- **A confirmed ~7-month data gap** on one meter (ZN.17) — not a real outage necessarily, but a sensor/reporting gap that should be closed if that meter matters for billing or capacity planning.

**Voltage and frequency across the whole facility are essentially perfect** — out of 31.75 million individual checks, only 13 came back outside normal range. That's a genuinely clean result and worth knowing, since it rules out supply-quality issues as an explanation for anything else found.

---

## 4. What's still early-stage — the AI/forecasting layer

Here's the honest part. We built a first version of a system to (a) predict next-day electricity consumption per meter, and (b) automatically flag unusual daily consumption. The result: **a dead-simple rule — "assume tomorrow looks like today" — currently predicts better than the trained AI models did.**

This is not a wasted effort, and it's not a red flag about the team's work. It's actually a well-run experiment that told us something true and useful: **the facility's day-to-day electricity use is dominated by patterns the AI didn't have access to yet** — most likely weather (cooling load) and possibly a production or occupancy schedule we haven't fed into the model. Two supporting clues already point this direction:
- Weekend usage is *higher* than weekday usage, which is unusual for most facilities and strongly suggests something schedule-driven is happening that we haven't captured yet.
- There's a clear daily up-and-down usage cycle tied to time of day, consistent with a cooling or occupancy-driven load.

**The fix is understood and scoped**, not a mystery. We know exactly what changed to make the next version work harder for its keep:
1. Combine data across all meters into one smarter model instead of 29 separate small ones (small per-meter models were starved of enough data to learn anything beyond the obvious).
2. Bring in weather data and, if available, a production/shift schedule — this is very likely the missing piece.
3. Only let the AI's predictions replace the "assume tomorrow looks like today" fallback where it's *proven*, meter by meter, to actually do better — not on faith.
4. Fix a subtle technical issue where the training data was built in a way that could make the AI look slightly better than it would in real, live use — this needs to be corrected before any forecasting number is trusted or shown externally.

**The anomaly-flagging piece** (spotting unusual days automatically) is being redesigned to work directly off the electrical signals that already found real issues (see §3) instead of a generic statistical trick — this reuses proven ground rather than starting from scratch.

---

## 5. Business risks and gaps worth knowing about now

| Item | Why it matters |
|---|---|
| No one is formally assigned as "owner" of this data long-term | Fine during active project work; becomes a real risk once this needs to run unattended, or if the current team member moves on |
| Billing/cost figures are not yet trustworthy | The underlying tariff/billing rules haven't been independently verified — don't use this system for cost claims yet |
| The forecasting number (currently ~12% average error) has a known asterisk | Explained in §4, point 4 — treat any current forecast accuracy figure as provisional until that's resolved |
| Several electrical findings are candidates, not confirmed faults | Three of the four "problem meters" need an actual engineer/electrician to confirm before treating them as maintenance tickets |

None of these are alarming on their own — they're normal for a project at this stage — but they're the honest list of "don't act on this yet" items.

---

## 6. What happens next (in plain terms)

1. **Get an electrician to look at the 1–4 flagged meters**, starting with ZN.20 (biggest, newest finding) and ZN.16 (already confirmed) — this is the fastest, highest-confidence win available right now and doesn't require any more data work.
2. **Fix the technical issue in the AI training data** (the "peeking at the future" problem) — about a week of engineering work, and it's the prerequisite for trusting any forecasting number going forward.
3. **Rebuild the forecasting model to pool data across all meters and add weather** — this is the real shot at actually beating the simple "assume tomorrow = today" rule, rather than adding more AI horsepower to a model that's starved of the right inputs.
4. **Redesign the anomaly-flagging tool to build on the electrical findings that already worked**, rather than a generic statistical approach that missed real problems in the first pass.
5. **Assign a data owner**, even informally — the single biggest non-technical gap right now.

---

## 7. Bottom line

The foundation — trustworthy data, working dashboards, and a genuinely useful list of electrical problems worth fixing — is done and already delivering value today. The AI forecasting layer isn't there yet, but that's because we tested it honestly rather than declaring victory on a number that wouldn't have held up. The path to a working version is clear, scoped, and doesn't require guessing — it requires pooling the data properly and feeding the model the one or two real-world signals (weather, schedule) it's currently missing.
