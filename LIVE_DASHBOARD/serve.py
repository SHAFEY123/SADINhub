"""SADINhub live dashboard server.

Queries the gold layer directly, read-only, so the dashboard can show
INDIVIDUAL READINGS for any window instead of pre-aggregated buckets.

Every consumption figure comes from gold.energy_consumption_validated's own
validated_kwh_consumption column -- the same column the Power BI report sums --
so the numbers match by construction rather than by coincidence.

Run:   python serve.py            (then open http://localhost:8770)
Stop:  Ctrl-C

The connection is forced read-only and verified before any query runs, so this
process cannot modify the warehouse.
"""
import json
import os
import re
import sys
import threading
import traceback
import urllib.parse
import uuid
from datetime import date, datetime, timedelta
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

try:
    import psycopg
    from psycopg.rows import dict_row
except ImportError:
    sys.exit(
        'psycopg is not importable by this interpreter.\n'
        'Use the project venv, which already has it:\n'
        r'  "..\ML_WORK\.venv\Scripts\python.exe" serve.py'
    )

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = int(os.environ.get('SADIN_PORT', '8770'))
DSN = os.environ.get(
    'SADIN_DSN',
    'host=localhost port=5432 dbname=sadinhub user=postgres',
    # The password comes from PGPASSWORD (libpq reads it automatically); never hard-code it.
)

_local = threading.local()

# Exact row counts, resolved once. Quoted as fact in the UI, so an estimate will
# not do; a full scan per request would be.
COUNTS = {'raw': 0, 'validated': 0}


# gold.meter / gold.zone / gold.facility are views over silver staging views
# over bronze. Joining 4.5M fact rows to them re-evaluates that whole stack per
# query and turns a 4-second aggregate into a 90-second one. They are only 31
# and 21 rows, so resolve them ONCE and filter the facts on plain UUID keys.
DIM = {'meters': [], 'by_label': {}, 'by_key': {}, 'zone_keys': {}, 'zones': [],
       'cadence': {}}


def load_dims():
    rows = q("""
        SELECT m.energy_meter_key::text AS mk, m.meter_label, m.meter_serial_number,
               m.phase_count, m.energy_meter_type_name, m.is_meter_active,
               m.zone_key::text AS zk, COALESCE(z.zone_name,'(unmapped)') AS zone_name,
               z.zone_type_name, f.facility_name, cb.cb_max_rating_a
        FROM gold.meter m
        LEFT JOIN gold.zone z ON z.zone_key = m.zone_key
        LEFT JOIN gold.facility f ON f.facility_key = m.facility_key
        LEFT JOIN silver.dim_meter_cb_rating cb ON cb.energy_meter_key = m.energy_meter_key
        ORDER BY z.zone_name, m.meter_label
    """)
    DIM['meters'] = clean(rows)
    DIM['by_label'] = {r['meter_label']: r for r in DIM['meters']}
    DIM['by_key'] = {r['mk']: r for r in DIM['meters']}
    zk = {}
    for r in DIM['meters']:
        zk.setdefault(r['zone_name'], set()).add(r['zk'])
    DIM['zone_keys'] = {k: sorted(v) for k, v in zk.items()}
    DIM['zones'] = sorted(zk)
    return DIM


def keys_for(qs):
    """Resolve the zone/meter filter to a list of energy_meter_key UUIDs.

    Returns None when no meter/zone filter is set, so the caller can skip the
    predicate entirely rather than passing all 31 keys."""
    zones = [z for z in (qs.get('zone') or []) if z]
    meters = [m for m in (qs.get('meter') or []) if m]
    if not zones and not meters:
        return None
    sel = DIM['meters']
    if zones:
        zs = set(zones)
        sel = [r for r in sel if r['zone_name'] in zs]
    if meters:
        ms = set(meters)
        sel = [r for r in sel if r['meter_label'] in ms]
    return [r['mk'] for r in sel]


def load_cadence():
    """Median inter-reading gap per meter, resolved ONCE at startup.

    Cadence is a property of the DEVICE, not of the selected window.
    Measured over the full history, over a 16-month window and over a
    single month it is identical to within 1 s for all 31 meters, so the
    per-request LAG() window + percentile_cont that used to compute it was
    12.3 s of a 27 s /api/meters -- 62% of the endpoint -- for an answer
    that never changed. Sampled over the most recent 30 days of data:
    index-friendly, and enough rows for a stable median.
    """
    rows = q("""
        WITH b AS (SELECT max(reading_timestamp_utc) AS hi FROM gold.energy_raw),
        g AS (
            SELECT r.energy_meter_key,
                   EXTRACT(EPOCH FROM (r.reading_timestamp_utc
                     - LAG(r.reading_timestamp_utc) OVER (
                         PARTITION BY r.energy_meter_key
                         ORDER BY r.reading_timestamp_utc))) AS gap_s
            FROM gold.energy_raw r, b
            WHERE r.reading_timestamp_utc >= b.hi - interval '30 days'
        )
        SELECT energy_meter_key::text AS mk,
               percentile_cont(0.5) WITHIN GROUP (ORDER BY gap_s) AS median_gap_s
        FROM g WHERE gap_s IS NOT NULL AND gap_s > 0
        GROUP BY 1
    """)
    cad = {r['mk']: float(r['median_gap_s']) for r in rows if r['median_gap_s']}
    # A meter that stopped reporting before that 30-day window gets no row.
    # Fall back to the fleet median rather than dropping its coverage figure.
    if cad:
        vals = sorted(cad.values())
        fleet = vals[len(vals) // 2]
        for m in DIM['meters']:
            cad.setdefault(m['mk'], fleet)
    DIM['cadence'] = cad
    return cad


def load_counts():
    COUNTS['raw'] = q('SELECT count(*) AS n FROM gold.energy_raw')[0]['n']
    COUNTS['validated'] = q(
        'SELECT count(*) AS n FROM gold.energy_consumption_validated')[0]['n']
    return COUNTS


def conn():
    """One read-only connection per thread, verified read-only."""
    c = getattr(_local, 'conn', None)
    if c is not None and not c.closed:
        return c
    c = psycopg.connect(DSN, row_factory=dict_row, connect_timeout=10)
    c.execute('SET default_transaction_read_only = on')
    c.commit()
    mode = c.execute('SHOW transaction_read_only').fetchone()['transaction_read_only']
    if mode != 'on':
        c.close()
        raise RuntimeError('refusing to serve: connection is not read-only')
    _local.conn = c
    return c


def q(sql, params=None):
    c = conn()
    with c.cursor() as cur:
        cur.execute(sql, params or {})
        rows = cur.fetchall()
    c.rollback()
    return rows


def jsonable(v):
    if isinstance(v, (datetime, date)):
        return v.isoformat(sep=' ')[:19]
    if isinstance(v, timedelta):
        return v.total_seconds()
    if isinstance(v, uuid.UUID):
        # Most endpoints cast ::text in SQL, but /api/quality and
        # /api/bill use SELECT *, so a raw uuid column arrives here.
        return str(v)
    if hasattr(v, 'normalize'):          # Decimal
        return float(v)
    return v


def json_default(v):
    """Hook for json.dumps. MUST NOT return v unchanged.

    json only calls default() for objects it cannot already encode, so
    handing the same object back makes it call default() again on the same
    object forever -- which surfaces as 'Circular reference detected', not
    as a recursion error. A raw uuid from SELECT * did exactly that and
    turned /api/quality into a 500. Stringify anything still unknown.
    """
    out = jsonable(v)
    return out if out is not v else str(v)


def clean(rows):
    return [{k: jsonable(v) for k, v in r.items()} for r in rows]


# ---------------------------------------------------------------- filters ----
UUID_RE = re.compile(r'^[0-9a-fA-F-]{36}$')
DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def flt(qs):
    """WHERE fragment + params for gold.energy_consumption_validated.

    Filters on energy_meter_key, resolved from the dimension cache, so no join
    to gold.meter / gold.zone is needed on the fact scan.
    """
    p, w = {}, []
    d1 = (qs.get('from') or [''])[0]
    d2 = (qs.get('to') or [''])[0]
    if DATE_RE.match(d1):
        w.append('c.reading_date_saudi >= %(d1)s')
        p['d1'] = d1
    if DATE_RE.match(d2):
        w.append('c.reading_date_saudi <= %(d2)s')
        p['d2'] = d2
    mk = keys_for(qs)
    if mk is not None:
        if not mk:
            return 'FALSE', p
        w.append('c.energy_meter_key = ANY(%(mk)s::uuid[])')
        p['mk'] = mk
    iq = [x for x in (qs.get('iq') or []) if x]
    if iq:
        w.append('c.interval_quality = ANY(%(iq)s)')
        p['iq'] = iq
    return (' AND '.join(w) if w else 'TRUE'), p


# ------------------------------------------------------------------- joins ----
# Every fact query goes through this join, so zone / facility / meter context is
# always available. These are the join keys the gold model actually uses.
# Bare fact scans. Zone / meter / facility context is attached in Python from
# the 31-row dimension cache, which is far cheaper than making the planner
# re-derive those view stacks for every one of 4.5M rows.
J_VAL = "FROM gold.energy_consumption_validated c"
J_RAW = "FROM gold.energy_raw r"

# Which channels each page of the dashboard actually plots. A 7-day series with
# every reading is 12.98 MB when all 26 channels are serialised; the Current
# page reads three of them. This is a projection only -- it never changes a
# row, a value or a filter.
SERIES_PROFILE = {
    'power':   ['kw1', 'kw2', 'kw3', 'kw', 'kvar1', 'kvar2', 'kvar3', 'kvar',
                'cum_kwh', 'cum_kvarh'],
    'current': ['a1', 'a2', 'a3'],
    'volt':    ['vn1', 'vn2', 'vn3', 'vl1', 'vl2', 'vl3', 'hz'],
    'pf':      ['pf1', 'pf2', 'pf3', 'pfa'],
}
# alias -> the raw column it comes from
SERIES_COL = {
    'a1': 'current_phase_1_a', 'a2': 'current_phase_2_a', 'a3': 'current_phase_3_a',
    'vn1': 'voltage_neutral_1_v', 'vn2': 'voltage_neutral_2_v', 'vn3': 'voltage_neutral_3_v',
    'vl1': 'voltage_line_1_v', 'vl2': 'voltage_line_2_v', 'vl3': 'voltage_line_3_v',
    'hz': 'frequency_hz',
    'pf1': 'power_factor_phase_1', 'pf2': 'power_factor_phase_2',
    'pf3': 'power_factor_phase_3', 'pfa': 'power_factor_average',
    'kw1': 'active_power_phase_1_kw', 'kw2': 'active_power_phase_2_kw',
    'kw3': 'active_power_phase_3_kw', 'kw': 'active_power_total_kw',
    'kvar1': 'reactive_power_phase_1_kvar', 'kvar2': 'reactive_power_phase_2_kvar',
    'kvar3': 'reactive_power_phase_3_kvar', 'kvar': 'reactive_power_total_kvar',
    'cum_kwh': 'active_energy_cumulative_kwh',
    'cum_kvarh': 'reactive_energy_cumulative_kvarh',
}
# Decimal places per channel, matching the precision the meter reports at.
SERIES_DP = {'a1': 2, 'a2': 2, 'a3': 2, 'vn1': 1, 'vn2': 1, 'vn3': 1,
             'vl1': 1, 'vl2': 1, 'vl3': 1, 'hz': 3,
             'pf1': 3, 'pf2': 3, 'pf3': 3, 'pfa': 3,
             'cum_kwh': 1, 'cum_kvarh': 1}


def AGG(k):
    """Combine the meters that reported at ONE exact instant. Never over time.

    Measured over the whole warehouse: 4,535,598 instants carry exactly one
    meter's reading, 160 carry two, none carry three. So this decides 160
    points out of 4,535,758 -- at every other instant avg() is handed a single
    value and gives it back unchanged, which is why these are still raw
    readings.

    Every channel takes the arithmetic MEAN, power included. Power is
    extensive and summing it did keep the three phase traces additive against
    the total, but this panel is 'power by phase', not a fleet total: a point
    that is one meter here and two meters added together there is not a
    reading of anything. The mean stays on the same scale as its neighbours.
    Fleet totals are the tables' job and those still sum.
    """
    return 'round(avg(r.%s)::numeric,%d) AS %s' % (
        SERIES_COL[k], SERIES_DP.get(k, 3), k)


def flt_raw(qs):
    """WHERE fragment + params for gold.energy_raw, key-filtered and sargable."""
    p, w = {}, []
    d1 = (qs.get('from') or [''])[0]
    d2 = (qs.get('to') or [''])[0]
    # Compare the bare timestamp column: wrapping it in +3h/::date is not
    # sargable and discards pk_energy_readings_snapshot. Saudi is a fixed
    # UTC+3 with no DST, so the day boundary is a plain 3-hour shift.
    if DATE_RE.match(d1):
        w.append("r.reading_timestamp_utc >= (%(d1)s::date - interval '3 hours')")
        p['d1'] = d1
    if DATE_RE.match(d2):
        w.append("r.reading_timestamp_utc < (%(d2)s::date + interval '1 day' - interval '3 hours')")
        p['d2'] = d2
    mk = keys_for(qs)
    if mk is None:
        # Supply every key even when unfiltered. pk_energy_readings_snapshot is
        # (energy_meter_key, reading_timestamp_utc), so a timestamp-only range
        # cannot lead with it and degrades to a sequential scan. Naming the keys
        # turns one 4.5M-row scan into 31 index range searches -- measured at
        # 28 ms against 103 ms for the same 7-day aggregate.
        mk = [r['mk'] for r in DIM['meters']]
    if not mk:
        return 'FALSE', p
    w.append('r.energy_meter_key = ANY(%(mk)s::uuid[])')
    p['mk'] = mk
    return (' AND '.join(w) if w else 'TRUE'), p


# ------------------------------------------------------------- endpoints ----
def ep_meta(qs):
    return {'meters': DIM['meters'],
            'bounds': clean(q("""
                SELECT (SELECT min(reading_date_saudi)::text
                          FROM silver.fact_energy_consumption_validated) AS d1,
                       (SELECT max(reading_date_saudi)::text
                          FROM silver.fact_energy_consumption_validated) AS d2
            """))[0] | {'validated_rows': COUNTS['validated']},
            'raw_rows': COUNTS['raw'],
            # Fixed by the classifier definitions, not discovered from data:
            # a SELECT DISTINCT over 4.5M unindexed text rows costs ~25 s and
            # can only ever return this same set.
            'enums': {
                'interval_quality': ['NORMAL_INTERVAL', 'LONG_GAP', 'FIRST_VALID_READING',
                                     'IGNORED_READING', 'UNRESOLVED_DECREMENT'],
                'consumption_cleaning_status': ['KEEP', 'ISOLATED_LOW_BAD',
                                                'ISOLATED_HIGH_BAD', 'STARTUP_EXCLUDED'],
                'overall_status': ['Acceptable', 'Review Required', 'Anomaly',
                                   'Problematic', 'Critical', 'Invalid'],
            }}


def ep_kpi(qs):
    w, p = flt(qs)
    # Consumption straight from the gold column Power BI sums.
    k_sql = f"""
        SELECT round(sum(c.validated_kwh_consumption)::numeric,2)          AS kwh,
               count(*)                                                     AS intervals,
               count(DISTINCT c.energy_meter_key)                           AS meters,
               count(DISTINCT c.zone_key)                                   AS zones,
               count(DISTINCT c.reading_date_saudi)                         AS days,
               min(c.reading_date_saudi)::text                              AS d1,
               max(c.reading_date_saudi)::text                              AS d2,
               round(sum(c.validated_kwh_consumption) FILTER
                    (WHERE c.interval_quality='NORMAL_INTERVAL')::numeric,2) AS kwh_normal,
               round(sum(c.validated_kwh_consumption) FILTER
                    (WHERE c.interval_quality='LONG_GAP')::numeric,2)        AS kwh_longgap,
               count(*) FILTER (WHERE c.interval_quality='LONG_GAP')         AS n_longgap,
               count(*) FILTER (WHERE c.consumption_cleaning_status<>'KEEP') AS n_excluded,
               round(max(c.gap_minutes)::numeric,1)                          AS max_gap_min
        {J_VAL} WHERE {w}
    """
    wr, pr = flt_raw(qs)
    e_sql = f"""
        SELECT round(max(r.active_power_total_kw)::numeric,3)   AS kw_max_single,
               round(avg(r.active_power_total_kw)::numeric,3)   AS kw_avg,
               round(avg(r.reactive_power_total_kvar)::numeric,3) AS kvar_avg,
               -- Per-phase means. The total channels above answer 'how much',
               -- these answer 'from which phase' -- the same question the
               -- current and PF pages already let the reader ask.
               round(avg(r.active_power_phase_1_kw)::numeric,3)     AS kw1_avg,
               round(avg(r.active_power_phase_2_kw)::numeric,3)     AS kw2_avg,
               round(avg(r.active_power_phase_3_kw)::numeric,3)     AS kw3_avg,
               round(avg(r.reactive_power_phase_1_kvar)::numeric,3) AS kvar1_avg,
               round(avg(r.reactive_power_phase_2_kvar)::numeric,3) AS kvar2_avg,
               round(avg(r.reactive_power_phase_3_kvar)::numeric,3) AS kvar3_avg,
               round(avg(r.power_factor_average)::numeric,4)    AS pf_avg,
               round(min(r.power_factor_average)::numeric,4)    AS pf_min,
               round(max(r.power_factor_average)::numeric,4)    AS pf_max,
               count(*) FILTER (WHERE r.power_factor_average < 0)      AS n_pf_neg,
               count(*) FILTER (WHERE r.active_power_total_kw < 0)     AS n_kw_neg,
               -- Per-phase negatives. The Power BI measures 'Total Negative PF
               -- Readings' and 'Total active power Negative Readings' sum the
               -- three PHASE counts, which is a different (and larger) quantity
               -- than a count on the total channel: a reading can be negative
               -- on two phases and be counted twice. Both are reported so the
               -- two reports can be reconciled rather than merely compared.
               -- Readings where ANY phase is negative. This is the honest
               -- headline: power_factor_average can stay positive while a
               -- single phase reverses -- avg(0.56, -0.04, 0.71) = 0.41 -- so a
               -- count on the average channel reports 0 while the chart plainly
               -- shows negative excursions. Not a sum of the three phase counts
               -- either: that double-counts a reading negative on two phases.
               count(*) FILTER (WHERE r.power_factor_phase_1 < 0
                                   OR r.power_factor_phase_2 < 0
                                   OR r.power_factor_phase_3 < 0)     AS n_pf_any_neg,
               count(*) FILTER (WHERE r.active_power_phase_1_kw < 0
                                   OR r.active_power_phase_2_kw < 0
                                   OR r.active_power_phase_3_kw < 0)  AS n_kw_any_neg,
               -- true minimum across all four PF channels, so a card captioned
               -- "negatives included" actually shows one
               round(least(min(r.power_factor_phase_1), min(r.power_factor_phase_2),
                           min(r.power_factor_phase_3), min(r.power_factor_average))::numeric,3)
                                                                       AS pf_min_any,
               count(*) FILTER (WHERE r.power_factor_phase_1 < 0)      AS n_pf1_neg,
               count(*) FILTER (WHERE r.power_factor_phase_2 < 0)      AS n_pf2_neg,
               count(*) FILTER (WHERE r.power_factor_phase_3 < 0)      AS n_pf3_neg,
               count(*) FILTER (WHERE r.active_power_phase_1_kw < 0)   AS n_kw1_neg,
               count(*) FILTER (WHERE r.active_power_phase_2_kw < 0)   AS n_kw2_neg,
               count(*) FILTER (WHERE r.active_power_phase_3_kw < 0)   AS n_kw3_neg,
               round(avg(r.voltage_neutral_1_v)::numeric,2)     AS vn1,
               round(avg(r.voltage_neutral_2_v)::numeric,2)     AS vn2,
               round(avg(r.voltage_neutral_3_v)::numeric,2)     AS vn3,
               round(avg(r.voltage_line_1_v)::numeric,2)        AS vl1,
               round(avg(r.voltage_line_2_v)::numeric,2)        AS vl2,
               round(avg(r.voltage_line_3_v)::numeric,2)        AS vl3,
               round(avg(r.frequency_hz)::numeric,4)            AS hz,
               round(avg(r.current_phase_1_a)::numeric,2)       AS a1,
               round(avg(r.current_phase_2_a)::numeric,2)       AS a2,
               round(avg(r.current_phase_3_a)::numeric,2)       AS a3,
               round(max(r.active_energy_cumulative_kwh)::numeric,1) AS cum_kwh_max,
               round(max(r.reactive_energy_cumulative_kvarh)::numeric,1) AS cum_kvarh_max,
               count(*) AS readings
        {J_RAW} WHERE {wr}
    """
    # The two aggregates are independent and each scans millions of rows, so
    # running them back to back made the endpoint cost their SUM (~8.9 s on a
    # long window). Overlapping them costs the SLOWER of the two instead.
    # The worker gets its own connection: conn() is thread-local.
    box = {}

    def _electricals():
        try:
            box['e'] = q(e_sql, pr)[0]
        except BaseException as ex:      # re-raised on the request thread
            box['err'] = ex

    t = threading.Thread(target=_electricals, daemon=True)
    t.start()
    k = q(k_sql, p)[0]
    t.join()
    if 'err' in box:
        raise box['err']
    return {'consumption': clean([k])[0], 'electrical': clean([box['e']])[0]}


def ep_daily(qs):
    w, p = flt(qs)
    return clean(q(f"""
        SELECT c.reading_date_saudi::text AS d,
               round(sum(c.validated_kwh_consumption)::numeric,2) AS kwh,
               round(sum(c.validated_kwh_consumption) FILTER
                    (WHERE c.interval_quality='NORMAL_INTERVAL')::numeric,2) AS kwh_normal,
               round(sum(c.validated_kwh_consumption) FILTER
                    (WHERE c.interval_quality='LONG_GAP')::numeric,2) AS kwh_longgap,
               count(*) AS intervals,
               count(DISTINCT c.energy_meter_key) AS meters
        {J_VAL} WHERE {w}
        GROUP BY 1 ORDER BY 1
    """, p))


def ep_monthly(qs):
    w, p = flt(qs)
    return clean(q(f"""
        SELECT to_char(c.reading_date_saudi,'YYYY-MM') AS ym,
               round(sum(c.validated_kwh_consumption)::numeric,2) AS kwh,
               count(DISTINCT c.reading_date_saudi) AS days,
               count(DISTINCT c.energy_meter_key) AS meters
        {J_VAL} WHERE {w}
        GROUP BY 1 ORDER BY 1
    """, p))


def ep_zones(qs):
    w, p = flt(qs)
    zname = {}
    for m in DIM['meters']:
        zname[m['zk']] = m['zone_name']
    rows = clean(q(f"""
        SELECT c.zone_key::text AS zk,
               round(sum(c.validated_kwh_consumption)::numeric,2) AS kwh,
               count(DISTINCT c.energy_meter_key) AS meters,
               count(*) AS intervals
        {J_VAL} WHERE {w}
        GROUP BY 1 ORDER BY 2 DESC NULLS LAST
    """, p))
    for r in rows:
        r['zone'] = zname.get(r.pop('zk'), '(unmapped)')
    return rows


def ep_meters(qs):
    """Per-meter table: consumption from gold, electricals from raw."""
    w, p = flt(qs)
    # `intervals` is deliberately absent: gold.energy_consumption_validated
    # carries exactly one interval per raw reading for every mapped meter, so an
    # interval count is identical to the reading count and the two columns
    # side by side told the reader nothing. Verified: over any window the two
    # agree row for row for all 29 mapped meters, and differ only for Zone 13's
    # two meters, which the validated view excludes entirely.
    a = q(f"""
        SELECT c.meter_label AS meter,
               round(sum(c.validated_kwh_consumption)::numeric,2) AS kwh,
               count(DISTINCT c.reading_date_saudi) AS days,
               count(*) FILTER (WHERE c.interval_quality='LONG_GAP') AS long_gaps,
               count(*) FILTER (WHERE c.interval_quality='NORMAL_INTERVAL') AS normal_intervals,
               count(*) FILTER (WHERE c.consumption_cleaning_status<>'KEEP') AS excluded,
               round(max(c.gap_minutes)::numeric,1) AS max_gap
        {J_VAL} WHERE {w} GROUP BY 1
    """, p)
    wr, pr = flt_raw(qs)
    b = q(f"""
        SELECT r.energy_meter_key::text AS mk,
               round(avg(r.current_phase_1_a)::numeric,2) AS a1,
               round(avg(r.current_phase_2_a)::numeric,2) AS a2,
               round(avg(r.current_phase_3_a)::numeric,2) AS a3,
               round(greatest(max(r.current_phase_1_a),max(r.current_phase_2_a),
                              max(r.current_phase_3_a))::numeric,2) AS a_max,
               round(avg(r.voltage_neutral_1_v)::numeric,1) AS vn1,
               round(avg(r.voltage_neutral_2_v)::numeric,1) AS vn2,
               round(avg(r.voltage_neutral_3_v)::numeric,1) AS vn3,
               round(avg(r.voltage_line_1_v)::numeric,1) AS vl1,
               round(avg(r.voltage_line_2_v)::numeric,1) AS vl2,
               round(avg(r.voltage_line_3_v)::numeric,1) AS vl3,
               round(avg(r.power_factor_phase_1)::numeric,3) AS pf1,
               round(avg(r.power_factor_phase_2)::numeric,3) AS pf2,
               round(avg(r.power_factor_phase_3)::numeric,3) AS pf3,
               round(avg(r.power_factor_average)::numeric,3) AS pfa,
               round(min(r.power_factor_average)::numeric,3) AS pf_min,
               round(avg(r.active_power_total_kw)::numeric,3) AS kw,
               round(max(r.active_power_total_kw)::numeric,3) AS kw_max,
               round(avg(r.reactive_power_total_kvar)::numeric,3) AS kvar,
               -- Per-phase power, so the reader can see WHICH phase carries the
               -- load rather than only how much the meter draws in total.
               round(avg(r.active_power_phase_1_kw)::numeric,3)     AS kw1,
               round(avg(r.active_power_phase_2_kw)::numeric,3)     AS kw2,
               round(avg(r.active_power_phase_3_kw)::numeric,3)     AS kw3,
               round(avg(r.reactive_power_phase_1_kvar)::numeric,3) AS kvar1,
               round(avg(r.reactive_power_phase_2_kvar)::numeric,3) AS kvar2,
               round(avg(r.reactive_power_phase_3_kvar)::numeric,3) AS kvar3,
               round(avg(r.frequency_hz)::numeric,3) AS hz,
               round(max(r.active_energy_cumulative_kwh)::numeric,1) AS cum_kwh,
               round(max(r.reactive_energy_cumulative_kvarh)::numeric,1) AS cum_kvarh,
               count(*) FILTER (WHERE r.power_factor_average<0) AS pf_neg,
               count(*) FILTER (WHERE r.active_power_total_kw<0) AS kw_neg,
               count(*) AS readings
        {J_RAW} WHERE {wr} GROUP BY 1
    """, pr)
    # attach zone + electricals from the dimension cache and the raw aggregate
    bylabel = {}
    for r in clean(b):
        d = DIM['by_key'].get(r.pop('mk'))
        if d:
            bylabel[d['meter_label']] = r
    # meters with raw readings but no validated rows (Zone 13) must still appear
    seen = set()
    out = []
    for r in clean(a):
        d = DIM['by_label'].get(r['meter']) or {}
        row = dict(r)
        row['zone'] = d.get('zone_name', '?')
        row['cb'] = d.get('cb_max_rating_a')
        row.update(bylabel.get(r['meter']) or {})
        out.append(row)
        seen.add(r['meter'])
    for label, rec in bylabel.items():
        if label in seen:
            continue
        d = DIM['by_label'].get(label) or {}
        row = {'meter': label, 'zone': d.get('zone_name', '?'),
               'cb': d.get('cb_max_rating_a'), 'kwh': None, 'days': None,
               'long_gaps': None, 'normal_intervals': None, 'excluded': None,
               'max_gap': None, 'no_consumption': True}
        row.update(rec)
        out.append(row)
    # Expected readings, derived from each meter's OWN measured cadence rather
    # than an assumed one. The nominal figure looks like 5 minutes but the
    # actual median inter-reading gap is 244 s (~4.07 min), i.e. ~354 readings
    # per day, so a hardcoded 288 understates the denominator by 23% and
    # produced coverage figures above 100%.
    # Resolved once at startup -- see load_cadence(). This was a LAG()
    # window over the whole filtered range on every request: 12.3 s of a
    # 27 s endpoint, recomputing a per-device constant.
    cad = DIM['cadence']
    d1 = (qs.get('from') or [''])[0]
    d2 = (qs.get('to') or [''])[0]
    span_days = 0
    if DATE_RE.match(d1) and DATE_RE.match(d2):
        span_days = (date.fromisoformat(d2) - date.fromisoformat(d1)).days + 1
    for row in out:
        d = DIM['by_label'].get(row['meter']) or {}
        gap = cad.get(d.get('mk'))
        row['cadence_s'] = round(gap, 1) if gap else None
        exp = int(span_days * 86400 / gap) if (gap and span_days) else None
        row['expected'] = exp
        rd = row.get('readings') or 0
        row['coverage'] = round(rd / exp * 100, 1) if exp else None
    return out


def ep_readings(qs):
    """INDIVIDUAL READINGS -- every column, every phase, no aggregation.

    This is the endpoint the pre-aggregated build could not offer. Capped, with
    the cap reported, so a huge window degrades honestly instead of hanging.
    """
    wr, pr = flt_raw(qs)
    try:
        limit = min(int((qs.get('limit') or ['2000'])[0]), 20000)
    except ValueError:
        limit = 2000
    try:
        offset = max(int((qs.get('offset') or ['0'])[0]), 0)
    except ValueError:
        offset = 0
    t1 = (qs.get('t1') or [''])[0]
    t2 = (qs.get('t2') or [''])[0]
    extra = ''
    if re.match(r'^\d{2}:\d{2}$', t1):
        extra += " AND (r.reading_timestamp_utc + interval '3 hours')::time >= %(t1)s"
        pr['t1'] = t1
    if re.match(r'^\d{2}:\d{2}$', t2):
        extra += " AND (r.reading_timestamp_utc + interval '3 hours')::time <= %(t2)s"
        pr['t2'] = t2
    st = [s for s in (qs.get('status') or []) if s]
    if st:
        extra += ' AND r.overall_status = ANY(%(st)s)'
        pr['st'] = st
    if (qs.get('nonzero') or [''])[0] == '1':
        extra += (' AND (r.current_phase_1_a<>0 OR r.current_phase_2_a<>0 OR'
                  ' r.current_phase_3_a<>0 OR r.active_power_total_kw<>0)')
    pr['lim'] = limit
    pr['off'] = offset

    total = q(f'SELECT count(*) AS n {J_RAW} WHERE {wr}{extra}', pr)[0]['n']
    rows = q(f"""
        SELECT r.energy_meter_key::text AS mk,
               (r.reading_timestamp_utc + interval '3 hours') AS ts_saudi,
               r.reading_timestamp_utc AS ts_utc,
               r.active_energy_cumulative_kwh      AS cum_kwh,
               r.reactive_energy_cumulative_kvarh  AS cum_kvarh,
               r.apparent_energy_cumulative_kvah   AS cum_kvah,
               r.current_phase_1_a AS a1, r.current_phase_2_a AS a2, r.current_phase_3_a AS a3,
               r.voltage_neutral_1_v AS vn1, r.voltage_neutral_2_v AS vn2, r.voltage_neutral_3_v AS vn3,
               r.voltage_line_1_v AS vl1, r.voltage_line_2_v AS vl2, r.voltage_line_3_v AS vl3,
               r.frequency_hz AS hz,
               r.power_factor_phase_1 AS pf1, r.power_factor_phase_2 AS pf2,
               r.power_factor_phase_3 AS pf3, r.power_factor_average AS pfa,
               r.active_power_phase_1_kw AS kw1, r.active_power_phase_2_kw AS kw2,
               r.active_power_phase_3_kw AS kw3, r.active_power_total_kw AS kw,
               r.reactive_power_phase_1_kvar AS kvar1, r.reactive_power_phase_2_kvar AS kvar2,
               r.reactive_power_phase_3_kvar AS kvar3, r.reactive_power_total_kvar AS kvar,
               r.apparent_power_total_kva AS kva,
               r.status_vn1, r.status_vn2, r.status_vn3,
               r.status_v1, r.status_v2, r.status_v3,
               r.status_amp1, r.status_amp2, r.status_amp3,
               r.status_hz, r.status_pf1, r.status_pf2, r.status_pf3, r.status_pfa,
               r.status_kwh, r.overall_status
        {J_RAW} WHERE {wr}{extra}
        ORDER BY r.reading_timestamp_utc, r.energy_meter_key
        LIMIT %(lim)s OFFSET %(off)s
    """, pr)
    out = clean(rows)
    for r in out:
        d = DIM['by_key'].get(r.pop('mk')) or {}
        r['meter'] = d.get('meter_label', '?')
        r['zone'] = d.get('zone_name', '?')
    return {'total': total, 'limit': limit, 'offset': offset, 'rows': out}


def ep_series(qs):
    """Time series for charting, straight out of gold.energy_raw.

    Every point this returns is a reading that exists in the warehouse, at the
    timestamp it was recorded, with the value that was recorded. Nothing here
    averages, interpolates or smooths.

    The only question is how many of the readings fit. That is answered by
    counting them, not by guessing from a cadence: the count rides the primary
    key and costs 0.01 s over a week, 1.77 s over the full 4.5M-row history.

      n <= limit   every reading in the window
      n >  limit   every Nth reading SWEEP, kept whole -- the identical query
                   with one extra predicate. All the meters that reported at a
                   kept instant stay together, so the shape of the fleet at
                   that moment is intact.

    Sweeps rather than individual rows because the meters fire in bursts:
    measured median gap between consecutive readings 0.32 s, p90 1.37 s, then a
    ~244 s pause. Thinning by row would cut across a burst and leave a
    misleading partial picture of the fleet at that instant.
    """
    wr, pr = flt_raw(qs)
    # 400,000 makes 1 day / 7 days / 30 days across all 31 meters complete,
    # and makes a SINGLE meter complete over any window the warehouse holds
    # (the widest is 160,303 readings). Only all-meters-across-months still
    # thins, because 4.5M readings is ~135 MB of JSON.
    try:
        limit = min(int((qs.get('limit') or ['400000'])[0]), 400000)
    except ValueError:
        limit = 400000
    single = len([m for m in (qs.get('meter') or []) if m]) == 1

    # Only serialise the channels this page draws. No profile -> everything,
    # so an unaware caller is unaffected.
    prof = (qs.get('profile') or [''])[0]
    keys = SERIES_PROFILE.get(prof) or list(SERIES_COL.keys())

    # How many readings are actually in this selection? Cheap, and it removes
    # the need to guess.
    total = int(q(f"SELECT count(*) AS n {J_RAW} WHERE {wr}", pr)[0]['n'])

    stride = 1
    if total > limit and limit > 0:
        stride = int(-(-total // limit))          # ceil, integer only

    # SWEEP_S is the fleet's measured median inter-reading gap. Bucketing the
    # epoch by it and keeping every Nth bucket keeps whole sweeps together.
    SWEEP_S = 244
    thin = ''
    if stride > 1:
        thin = (f" AND mod(floor(extract(epoch from r.reading_timestamp_utc)"
                f" / {SWEEP_S})::bigint, {stride}) = 0")

    if single:
        sel = ',\n                   '.join(
            'r.%s AS %s' % (SERIES_COL[k], k) for k in keys)
        rows = q(f"""
            SELECT (extract(epoch from r.reading_timestamp_utc) * 1000
                    + 10800000)::bigint AS t,
                   {sel},
                   r.overall_status
            {J_RAW} WHERE {wr}{thin}
            ORDER BY r.reading_timestamp_utc
        """, pr)
    else:
        # Several meters: one point per recorded instant, grouped on the exact
        # timestamp the meter stamped. This is NOT a time bucket -- the group
        # key is the instant itself, so two readings only ever land together
        # if the warehouse really does hold them at the same microsecond.
        # Measured: that happens at 160 instants out of 4,535,758. Where it
        # does, AGG() takes the mean across those meters on every channel.
        sel = ',\n                   '.join(AGG(k) for k in keys)
        rows = q(f"""
            SELECT (extract(epoch from r.reading_timestamp_utc) * 1000
                    + 10800000)::bigint AS t,
                   {sel},
                   count(*) AS n
            {J_RAW} WHERE {wr}{thin}
            GROUP BY 1 ORDER BY 1
        """, pr)

    return {'single_meter': single, 'limit': limit, 'rows': clean(rows),
            'total_readings': total, 'stride': stride,
            # kept for the front end: true when not every reading is drawn.
            # It never means averaged -- nothing in this endpoint averages
            # over time any more.
            'bucketed': stride > 1, 'sampled': stride > 1, 'bucket_s': 0,
            'span_days': None}


STATUS_COLS = ['status_vn1', 'status_vn2', 'status_vn3',
               'status_v1', 'status_v2', 'status_v3',
               'status_amp1', 'status_amp2', 'status_amp3',
               'status_hz', 'status_pf1', 'status_pf2', 'status_pf3', 'status_pfa',
               'status_kwh', 'overall_status']
# The status ladder in silver.status_rank is NOT the full domain. The 3-argument
# silver.classify_current_v2 also emits 'Major Issue' (power recorded but zero
# current) and 'Major Problem' (current flowing but zero power) -- sensor
# disagreement faults that status_rank does not rank at all, so they fall to its
# ELSE 0 branch. Hardcoding the ladder therefore hid 79,429 real exceedances.
# The domain is now discovered from the data once at startup instead of assumed.
STATUS_VALS = ['Acceptable', 'Review Required', 'Anomaly', 'Problematic',
               'Critical', 'Invalid', 'Major Issue', 'Major Problem']


def load_status_domain():
    """One pass to learn every value that actually occurs in any status column.

    Cheap insurance: if a classifier is changed to emit a new label, the status
    page picks it up instead of silently dropping those rows.
    """
    cols = ', '.join("(%r, r.%s)" % (c, c) for c in STATUS_COLS).replace("'", "'")
    rows = q(f"""
        SELECT DISTINCT t.v
        FROM gold.energy_raw r
        CROSS JOIN LATERAL (VALUES {cols}) AS t(col, v)
        WHERE t.v IS NOT NULL
    """)
    found = sorted(r['v'] for r in rows)
    known = [v for v in STATUS_VALS if v in found]
    extra = [v for v in found if v not in STATUS_VALS]
    if extra:
        print('  status values not in the expected ladder: %s' % ', '.join(extra))
    STATUS_VALS[:] = known + extra
    return STATUS_VALS


def ep_status(qs):
    """Per-phase status breakdown, every status_* column.

    One table pass. The obvious shape -- a UNION ALL of 16 GROUP BY queries --
    reads the whole table 16 times; a grid of FILTER counts reads it once, and
    the status domain is fixed by silver.status_rank so the grid is complete.
    """
    wr, pr = flt_raw(qs)
    sel = []
    for ci, col in enumerate(STATUS_COLS):
        for vi, val in enumerate(STATUS_VALS):
            sel.append("count(*) FILTER (WHERE r.%s = '%s') AS c%d_%d" % (col, val, ci, vi))
    row = q('SELECT ' + ', '.join(sel) + f' {J_RAW} WHERE {wr}', pr)[0]
    out = []
    for ci, col in enumerate(STATUS_COLS):
        for vi, val in enumerate(STATUS_VALS):
            n = row['c%d_%d' % (ci, vi)]
            if n:
                out.append({'signal': col, 'status': val, 'n': n})
    out.sort(key=lambda r: (r['signal'], -r['n']))
    return out


# (label, column) pairs, kept in alphabetical order by label so the table the
# user reads is ordered without needing a client-side sort to be applied first.
NZ_SIGNALS = sorted([
    ('Active energy cumulative', 'active_energy_cumulative_kwh'),
    ('Active power L1', 'active_power_phase_1_kw'),
    ('Active power L2', 'active_power_phase_2_kw'),
    ('Active power L3', 'active_power_phase_3_kw'),
    ('Active power total', 'active_power_total_kw'),
    ('Apparent energy cumulative', 'apparent_energy_cumulative_kvah'),
    ('Apparent power L1', 'apparent_power_phase_1_kva'),
    ('Apparent power L2', 'apparent_power_phase_2_kva'),
    ('Apparent power L3', 'apparent_power_phase_3_kva'),
    ('Apparent power total', 'apparent_power_total_kva'),
    ('Current L1', 'current_phase_1_a'),
    ('Current L2', 'current_phase_2_a'),
    ('Current L3', 'current_phase_3_a'),
    ('Frequency', 'frequency_hz'),
    ('Power factor L1', 'power_factor_phase_1'),
    ('Power factor L2', 'power_factor_phase_2'),
    ('Power factor L3', 'power_factor_phase_3'),
    ('Power factor average', 'power_factor_average'),
    ('Reactive energy cumulative', 'reactive_energy_cumulative_kvarh'),
    ('Reactive power L1', 'reactive_power_phase_1_kvar'),
    ('Reactive power L2', 'reactive_power_phase_2_kvar'),
    ('Reactive power L3', 'reactive_power_phase_3_kvar'),
    ('Reactive power total', 'reactive_power_total_kvar'),
    ('Voltage line VL1', 'voltage_line_1_v'),
    ('Voltage line VL2', 'voltage_line_2_v'),
    ('Voltage line VL3', 'voltage_line_3_v'),
    ('Voltage neutral Vn1', 'voltage_neutral_1_v'),
    ('Voltage neutral Vn2', 'voltage_neutral_2_v'),
    ('Voltage neutral Vn3', 'voltage_neutral_3_v'),
], key=lambda t: t[0])


def ep_nonzero(qs):
    """Per-signal availability, in ONE table pass.

    Reports `present` (NOT NULL) separately from `nonzero`, because they answer
    different questions and conflating them is misleading: every meter column
    except the kVA family is 100% NOT NULL, yet reactive_energy_cumulative_kvarh
    is exactly 0 on well over half its rows. "100% available" therefore means
    "always transmitted", not "always meaningful" -- so both are shown.
    """
    wr, pr = flt_raw(qs)
    sel = ['count(*) AS total']
    for k, (label, col) in enumerate(NZ_SIGNALS):
        sel += [
            f'count(r.{col}) AS p{k}',
            f'count(*) FILTER (WHERE r.{col} <> 0) AS n{k}',
            f'count(*) FILTER (WHERE r.{col} = 0) AS z{k}',
            f'count(*) FILTER (WHERE r.{col} < 0) AS g{k}',
        ]
    row = q('SELECT ' + ', '.join(sel) + f' {J_RAW} WHERE {wr}', pr)[0]
    total = row['total'] or 0
    out = []
    for k, (label, col) in enumerate(NZ_SIGNALS):
        present = row[f'p{k}'] or 0
        out.append({
            'signal': label, 'col': col, 'total': total,
            'present': present, 'nonzero': row[f'n{k}'] or 0,
            'zero': row[f'z{k}'] or 0, 'negative': row[f'g{k}'] or 0,
            'present_pct': round(present / total * 100, 2) if total else 0,
            'nonzero_pct': round((row[f'n{k}'] or 0) / total * 100, 2) if total else 0,
        })
    return out


def ep_quality(qs):
    return {
        'summary': clean(q('SELECT * FROM gold.quality_summary LIMIT 500')),
        'gaps': clean(q("""
            SELECT * FROM gold.energy_reading_gaps
            ORDER BY 1 LIMIT 1000
        """)),
    }


def ep_bill(qs):
    """Bill vs system reconciliation, straight from gold.energy_bill."""
    return clean(q("""
        SELECT b.invoice_number, COALESCE(z.zone_name,'?') AS zone,
               b.start_period::date::text AS start_period,
               b.end_period::date::text   AS end_period,
               b.calculated_billing_days,
               b.billed_consumption_kwh, b.billed_cost,
               b.system_consumption_kwh, b.system_estimated_cost,
               b.consumption_variance_kwh,
               round(b.consumption_variance_percent::numeric,2) AS consumption_variance_percent,
               b.cost_variance
        FROM gold.energy_bill b
        LEFT JOIN gold.zone z ON z.zone_key = b.zone_key
        ORDER BY b.consumption_variance_percent NULLS LAST
    """))


def ep_pfdist(qs):
    """Power-factor distribution per phase, in ONE table pass.

    Bands follow the project's own silver.classify_power_factor_v2:
    Critical <0.6, Problematic 0.6-0.78, Review 0.78-0.80, Acceptable 0.80-1.00,
    Critical >1. The range starts at -1 so the negative tail is visible rather
    than clipped -- negative PF is real in this data and hiding it was one of
    the things that made the earlier build misleading.

    A LATERAL VALUES unpivot turns four columns into four rows per reading, so
    the heap is read once instead of once per phase (7.0 s -> ~2 s).
    """
    wr, pr = flt_raw(qs)
    rows = q(f"""
        SELECT t.col, width_bucket(t.v, -1, 1.2, 44) AS b,
               round(min(t.v)::numeric,3) AS lo,
               round(max(t.v)::numeric,3) AS hi,
               count(*) AS n
        {J_RAW}
        CROSS JOIN LATERAL (VALUES
            ('pf1', r.power_factor_phase_1),
            ('pf2', r.power_factor_phase_2),
            ('pf3', r.power_factor_phase_3),
            ('pfa', r.power_factor_average)
        ) AS t(col, v)
        WHERE {wr} AND t.v IS NOT NULL
        GROUP BY 1, 2 ORDER BY 1, 2
    """, pr)
    out = {'pf1': [], 'pf2': [], 'pf3': [], 'pfa': []}
    for r in clean(rows):
        out.setdefault(r['col'], []).append(
            {'b': r['b'], 'lo': r['lo'], 'hi': r['hi'], 'n': r['n']})
    return out


def ep_sql(qs):
    """Every SQL statement the dashboard uses, so any number can be re-run by
    hand in psql. Transparency beats trust."""
    return {'note': 'These are the exact queries behind each endpoint.',
            'joins': {'validated': J_VAL.strip(), 'raw': J_RAW.strip()}}


ROUTES = {
    '/api/meta': ep_meta, '/api/kpi': ep_kpi, '/api/daily': ep_daily,
    '/api/monthly': ep_monthly, '/api/zones': ep_zones, '/api/meters': ep_meters,
    '/api/readings': ep_readings, '/api/series': ep_series, '/api/status': ep_status,
    '/api/nonzero': ep_nonzero, '/api/quality': ep_quality, '/api/bill': ep_bill,
    '/api/pfdist': ep_pfdist, '/api/sql': ep_sql,
}


# A whole-history query touches 4.5M rows and takes tens of seconds. The
# warehouse is a static snapshot, so caching by exact query string is safe and
# makes revisiting a view instant.
_cache = {}
_cache_lock = threading.Lock()
CACHE_MAX = 400


def cached(path, query, fn, qs):
    key = path + '?' + query
    with _cache_lock:
        if key in _cache:
            return _cache[key]
    val = fn(qs)
    with _cache_lock:
        if len(_cache) >= CACHE_MAX:
            _cache.clear()
        _cache[key] = val
    return val


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=HERE, **kw)

    def log_message(self, fmt, *args):
        # send_error() reaches here via log_error() with an HTTPStatus as
        # args[0], not a str -- `in` on that raised TypeError and killed the
        # connection, which the browser reported as ERR_EMPTY_RESPONSE for any
        # missing static file such as favicon.ico. Coerce before testing.
        first = str(args[0]) if args else ''
        if '/api/' in first:
            sys.stderr.write('  %s\n' % (fmt % args))

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path in ROUTES:
            qs = urllib.parse.parse_qs(u.query, keep_blank_values=False)
            try:
                data = cached(u.path, u.query, ROUTES[u.path], qs)
                body = json.dumps(data, default=json_default).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
            except Exception:
                traceback.print_exc()
                body = json.dumps({'error': traceback.format_exc(limit=3)}).encode('utf-8')
                self.send_response(500)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(body)
            return
        if u.path == '/':
            # Prefer the hand-designed UI when it is present, so that opening
            # http://localhost:8770 lands on the current dashboard rather than
            # the earlier one. The older file stays reachable at
            # /dashboard.html for comparison.
            for candidate in ('dashboard_updated.html', 'dashboard.html'):
                if os.path.exists(os.path.join(HERE, candidate)):
                    self.path = '/' + candidate
                    break
        return super().do_GET()


class Server(ThreadingHTTPServer):
    """Threaded on purpose.

    Each page fires four or five requests at once. On a plain HTTPServer those
    serialize, so one slow aggregate stalls the entire page and every panel
    sits at em-dash -- which looks exactly like a broken dashboard rather than
    a queued one. Each thread gets its own read-only connection.
    """
    daemon_threads = True
    allow_reuse_address = True

    def handle_error(self, request, client_address):
        """A superseded request is not a server fault.

        The dashboard aborts in-flight queries on every filter change, so
        the browser routinely closes a socket while we are still writing
        the response. socketserver's default prints a full traceback for
        each one, which buried real errors in noise. Swallow just the
        disconnect cases and let everything else through.
        """
        exc = sys.exc_info()[1]
        if isinstance(exc, (ConnectionAbortedError, ConnectionResetError,
                            BrokenPipeError)):
            return
        super().handle_error(request, client_address)


def warm_cache():
    """Pre-compute the views the dashboard opens on, in the background.

    The response cache lives in memory, so a restart empties it. That is
    the whole reason the dashboard 'used to feel fast': in a long session
    almost every click was a cache hit. Cold, a wide window costs seconds
    per endpoint. Warming the landing view and the full range here gives
    that back without anyone waiting for it.

    Sequential on purpose. Four concurrent scans of the same heap contend
    rather than overlap -- measured 16.0 s wall clock for a page's four
    aggregates fired together, against 6.0 s for the slowest one alone.
    """
    try:
        b = q('SELECT min(reading_date_saudi)::text lo, '
              '       max(reading_date_saudi)::text hi '
              'FROM gold.energy_consumption_validated')[0]
        hi = date.fromisoformat(b['hi'])
        windows = [
            (str(hi - timedelta(days=6)), b['hi']),   # the default landing view
            (b['lo'], b['hi']),                       # what the 'All' preset asks for
        ]
        for d1, d2 in windows:
            query = 'from=%s&to=%s' % (d1, d2)       # must match qsBuild() exactly
            qs = {'from': [d1], 'to': [d2]}
            for path in ('/api/kpi', '/api/daily', '/api/zones', '/api/monthly'):
                cached(path, query, ROUTES[path], qs)
            # The Energy / Current / Voltage / PF pages all pull the same
            # series. Over the full range it is the single most expensive
            # call in the app, so it is worth paying for once up front.
            sq = query + '&limit=6000'
            cached('/api/series', sq, ep_series,
                   {'from': [d1], 'to': [d2], 'limit': ['6000']})
    except Exception as e:                            # never block serving
        print('  cache warm-up skipped: %s' % e, flush=True)
        return
    print('  cache warmed: landing view + full range', flush=True)


if __name__ == '__main__':
    try:
        print('resolving dimensions and row counts once...', flush=True)
        load_dims()
        load_counts()
        load_status_domain()
        load_cadence()
        n = COUNTS['validated']
        t = q('SELECT round(sum(validated_kwh_consumption)::numeric,1) AS t '
              'FROM gold.energy_consumption_validated')[0]['t']
    except Exception as e:
        sys.exit('cannot reach the database: %s' % e)
    print('SADINhub live dashboard')
    print('  meters / zones                    : %d / %d'
          % (len(DIM['meters']), len(DIM['zones'])))
    print('  gold.energy_consumption_validated : %s rows' % f'{n:,}')
    print('  SUM(validated_kwh_consumption)    : %s kWh   <- must equal your Power BI' % f'{float(t):,.1f}')
    print('  connection                        : read-only, verified')
    print()
    print('  open  http://localhost:%d' % PORT)
    print('  stop  Ctrl-C')
    print()
    if os.environ.get('SADIN_NO_WARM') != '1':
        threading.Thread(target=warm_cache, daemon=True).start()
    Server(('127.0.0.1', PORT), Handler).serve_forever()
