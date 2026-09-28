"""Check that the load script recovered from the server log rebuilds the stored table.

    python verify_recovered_sql.py

The script for silver.fact_energy_consumption_validated was recovered from a
PostgreSQL log entry, and it is in that log because that execution was cancelled
part-way. That makes it plausible, not proven. This runs the recovered SQL as a
plain SELECT over a sample of meters and compares every column against the rows
the table actually holds, so the repo can say "verified" rather than "found".

Read-only throughout: the CREATE TABLE ... AS wrapper is stripped and the query
runs as a SELECT.
"""
import getpass
import os
import re
import sys
from pathlib import Path

import pandas as pd
from sqlalchemy import URL, create_engine, text

ROOT = Path(__file__).resolve().parent
DDL = ROOT / '05_recovered_history' / 'original_ddl'
SAMPLE_METERS = 2

# Each recovered load script, the table it should rebuild, and the columns whose
# values prove the logic rather than just the shape.
CASES = {
    'consumption': {
        'script': 'table__silver__fact_energy_consumption_validated.sql',
        'target': 'silver.fact_energy_consumption_validated',
        'key': ['energy_meter_key', 'reading_timestamp_utc'],
        'compare': ['consumption_cleaning_status', 'interval_quality',
                    'previous_valid_kwh', 'validated_kwh_consumption', 'gap_minutes',
                    'status_kwh', 'raw_previous_kwh', 'raw_next_kwh'],
    },
    'snapshot': {
        'script': 'table__silver__fact_energy_readings_snapshot__2.sql',
        'target': 'silver.fact_energy_readings_snapshot',
        'key': ['energy_meter_key', 'reading_timestamp_utc'],
        'compare': ['overall_status', 'status_kwh', 'status_v1', 'status_pfa',
                    'status_amp1', 'status_hz', 'active_energy_cumulative_kwh',
                    'active_power_total_kw', 'voltage_line_1_v', 'power_factor_average'],
    },
}


SOURCE_VIEWS = ['silver.fact_energy_readings_staging',
                'silver.fact_energy_readings_flagged']


def first_statement(sql):
    """Return the text up to the first top-level semicolon."""
    depth = 0
    quote = None
    index = 0
    length = len(sql)
    while index < length:
        char = sql[index]
        pair = sql[index:index + 2]
        if quote is None and pair == '--':
            end = sql.find('\n', index)
            index = length if end == -1 else end
            continue
        if quote is None and pair == '/*':
            end = sql.find('*/', index + 2)
            index = length if end == -1 else end + 2
            continue
        if quote is not None:
            if char == quote:
                quote = None
            index += 1
            continue
        if char in ("'", '"'):
            quote = char
        elif char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
        elif char == ';' and depth == 0:
            return sql[:index]
        index += 1
    if depth != 0:
        raise RuntimeError('Unbalanced parentheses while splitting the recovered script')
    return sql


def recovered_select(script, restrict_to_meters=True):
    """Strip the comment header and the CREATE TABLE ... AS wrapper.

    Both source views sit on top of the raw bronze telemetry, so filtering after
    the query has run would still make PostgreSQL rebuild the whole staging layer
    first. The filter is therefore pushed into the source references instead.

    That substitution is exact rather than approximate: every window clause in
    the recovered query, and in fact_energy_readings_flagged, partitions by
    energy_meter_key, so restricting to whole meters cannot change the result for
    those meters. verify_windows() re-checks that before the comparison runs.
    """
    text_body = (DDL / script).read_text(encoding='utf-8')
    body = '\n'.join(line for line in text_body.splitlines()
                     if not line.lstrip().startswith('-- '))
    # Drop the comment banner and any DROP TABLE, then the CREATE ... AS wrapper,
    # leaving the SELECT that produced the rows.
    body = '\n'.join(line for line in body.splitlines()
                     if not line.lstrip().upper().startswith('DROP TABLE'))
    body = re.sub(r'.*?CREATE\s+TABLE\s+\S+\s+AS\s*', '', body,
                  count=1, flags=re.IGNORECASE | re.DOTALL)
    # A recovered block often holds several statements: the CREATE TABLE AS, then
    # an ALTER TABLE for the primary key, then a spot-check SELECT. Keep only the
    # first statement, cutting at the first semicolon that is not inside quotes,
    # parentheses or a comment.
    body = first_statement(body).strip()
    if re.search(r'CREATE\s+TABLE', body, re.IGNORECASE):
        raise RuntimeError(f'{script}: could not reduce the recovered script to a '
                           'plain SELECT; refusing to send it to the database')
    if restrict_to_meters:
        for view in SOURCE_VIEWS:
            body = body.replace(
                view, f'(SELECT * FROM {view} '
                      f'WHERE energy_meter_key = ANY(:meters))')
    return body


def verify_windows(connection, query):
    """Confirm the exactness claim the meter filter depends on."""
    clauses = re.findall(r'OVER\s*\(([^)]*)\)', query, re.IGNORECASE | re.DOTALL)
    flagged = connection.execute(text("""
        SELECT pg_get_viewdef('silver.fact_energy_readings_flagged'::regclass, true)
    """)).scalar_one()
    clauses += re.findall(r'(?:OVER|WINDOW\s+\w+\s+AS)\s*\(([^)]*)\)', flagged,
                          re.IGNORECASE | re.DOTALL)
    unsafe = [c for c in clauses
              if 'PARTITION BY' not in c.upper() or 'energy_meter_key' not in c]
    if unsafe:
        raise RuntimeError(
            'Cannot verify meter-by-meter: these window clauses are not partitioned '
            'by energy_meter_key, so a per-meter filter would change results:\n  '
            + '\n  '.join(' '.join(c.split()) for c in unsafe))
    print(f'{len(clauses)} window clauses checked, all partitioned by '
          f'energy_meter_key: a per-meter comparison is exact.')


def run_case(connection, name, case):
    print('=' * 72)
    print(f'{name}: {case["script"]}  ->  {case["target"]}')
    print('=' * 72)
    query = recovered_select(case['script'])
    print(f'recovered query: {len(query):,} characters')
    verify_windows(connection, query)
    meters = [r[0] for r in connection.execute(text(f"""
        SELECT energy_meter_key FROM {case['target']}
        GROUP BY energy_meter_key ORDER BY count(*) DESC LIMIT {SAMPLE_METERS}
    """))]
    print(f'comparing {len(meters)} meters')
    rebuilt = pd.read_sql_query(text(query), connection, params={'meters': meters})
    stored = pd.read_sql_query(text(f"""
        SELECT * FROM {case['target']} WHERE energy_meter_key = ANY(:meters)
    """), connection, params={'meters': meters})
    print(f'rebuilt rows {len(rebuilt):,}   stored rows {len(stored):,}')

    key = case['key']
    missing = [c for c in case['compare'] if c not in rebuilt.columns]
    if missing:
        print(f'columns the recovered query does not produce: {missing}')
    shared = [c for c in case['compare']
              if c in rebuilt.columns and c in stored.columns]
    merged = stored.merge(rebuilt, on=key, how='outer',
                          suffixes=('_stored', '_rebuilt'), indicator=True)
    only_stored = int((merged._merge == 'left_only').sum())
    only_rebuilt = int((merged._merge == 'right_only').sum())
    both = merged[merged._merge == 'both']
    print(f'rows only in stored {only_stored:,}   only in rebuilt {only_rebuilt:,}   '
          f'in both {len(both):,}')
    print()
    print(f'{"column":<34} {"equal":>10} {"differing":>10}')
    identical = True
    for column in shared:
        left, right = both[f'{column}_stored'], both[f'{column}_rebuilt']
        if (pd.api.types.is_numeric_dtype(left)
                and pd.api.types.is_numeric_dtype(right)):
            same = ((left - right).abs() < 1e-6) | (left.isna() & right.isna())
        else:
            same = ((left.astype(str) == right.astype(str))
                    | (left.isna() & right.isna()))
        differing = int((~same).sum())
        print(f'{column:<34} {int(same.sum()):>10,} {differing:>10,}')
        if differing:
            identical = False
            print(both.loc[~same, key + [f'{column}_stored',
                                         f'{column}_rebuilt']].head(3).to_string(index=False))
    verdict = identical and not missing and only_stored == 0 and only_rebuilt == 0
    print()
    print('VERIFIED: reproduces the stored table exactly for these meters.'
          if verdict else
          'DIFFERENCES: close but not identical; reconcile the columns above.')
    print()
    return verdict


def main():
    wanted = [a for a in sys.argv[1:] if a in CASES] or list(CASES)
    password = os.environ.get('SADINHUB_PASSWORD') or getpass.getpass(
        'PostgreSQL password for postgres@localhost/sadinhub: ')
    url = URL.create('postgresql+psycopg', username='postgres', password=password,
                     host='localhost', port=5432, database='sadinhub')
    engine = create_engine(url, connect_args={
        'connect_timeout': 10,
        'options': '-c default_transaction_read_only=on -c statement_timeout=1800000'})
    results = {}
    try:
        with engine.connect() as connection:
            if connection.execute(
                    text('SHOW transaction_read_only')).scalar_one() != 'on':
                raise RuntimeError('Refusing to continue: connection is not read-only')
            for name in wanted:
                case = CASES[name]
                if not (DDL / case['script']).exists():
                    print(f'{name}: {case["script"]} not found; run export_database.py')
                    results[name] = False
                    continue
                results[name] = run_case(connection, name, case)
    finally:
        engine.dispose()
    print('=' * 72)
    for name, ok in results.items():
        print(f'  {name:<14} {"VERIFIED" if ok else "NOT IDENTICAL"}')
    return 0 if all(results.values()) else 2


if __name__ == '__main__':
    sys.exit(main())
