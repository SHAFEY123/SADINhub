"""Recover the SADINhub database structure from PostgreSQL into a git repo.

    python export_database.py

Everything is read with a read-only connection; nothing is written to the
database. Run it again any time to refresh the exported SQL.

What this can and cannot recover
--------------------------------
PostgreSQL keeps the *source text* of views, materialised views, functions,
procedures and triggers in its own catalog, so those come back exactly as the
server has them (reformatted by the server, not character-for-character as
originally typed). Table, index and constraint definitions are reconstructed by
pg_dump, which is authoritative and restorable.

One-off INSERT INTO ... SELECT or CREATE TABLE AS source queries are not retained
in the table catalog. Some may survive in pgAdmin history, server logs or saved
files. Their presence in a log is not proof of successful execution or that they
match the current pipeline. Missing load/refresh logic is documented in README.md;
this exporter does not invent it or claim a complete data rebuild.
"""
from collections import defaultdict
from datetime import datetime, timezone
import getpass
import os
import re
import subprocess
import sys
from pathlib import Path

from sqlalchemy import URL, create_engine, text

ROOT = Path(__file__).resolve().parent
DATABASE = 'sadinhub'
SCHEMAS = ['bronze', 'silver', 'gold']
HOST, PORT, USER = 'localhost', 5432, 'postgres'

HEADER = """-- {title}
-- Recovered from PostgreSQL {version} catalog on {stamp}
-- Database {database}, schema {schema}
-- Source of truth: {source}
{extra}
"""


def slug(text_value):
    return re.sub(r'[^A-Za-z0-9_.-]+', '_', text_value)[:110]


def write(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body.rstrip() + '\n', encoding='utf-8')


def find_pg_dump():
    for base in sorted(Path('C:/Program Files/PostgreSQL').glob('*/bin'), reverse=True):
        candidate = base / 'pg_dump.exe'
        if candidate.exists():
            return candidate
    for name in ('pg_dump', 'pg_dump.exe'):
        found = subprocess.run(['where' if os.name == 'nt' else 'which', name],
                               capture_output=True, text=True)
        if found.returncode == 0:
            return Path(found.stdout.splitlines()[0].strip())
    return None


def run_pg_dump(pg_dump, password, args, destination, progress):
    environment = dict(os.environ, PGPASSWORD=password)
    command = [str(pg_dump), '-h', HOST, '-p', str(PORT), '-U', USER,
               '-d', DATABASE, '--schema-only', '--no-owner', '--no-privileges',
               *args]
    result = subprocess.run(command, capture_output=True, text=True,
                            env=environment, encoding='utf-8', errors='replace')
    if result.returncode != 0:
        raise RuntimeError(f'pg_dump failed for {destination.name}; export is incomplete')
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(result.stdout, encoding='utf-8')
    return True


def topological(edges, nodes):
    """Order objects so that each one comes after everything it depends on."""
    incoming = defaultdict(set)
    outgoing = defaultdict(set)
    for child, parent in edges:
        if child in nodes and parent in nodes and child != parent:
            incoming[child].add(parent)
            outgoing[parent].add(child)
    ordered, ready = [], sorted(n for n in nodes if not incoming[n])
    seen = set()
    while ready:
        node = ready.pop(0)
        if node in seen:
            continue
        seen.add(node)
        ordered.append(node)
        for child in sorted(outgoing[node]):
            incoming[child].discard(node)
            if not incoming[child] and child not in seen:
                ready.append(child)
    if len(seen) != len(nodes):
        raise RuntimeError('Unresolved view dependency cycle; no valid apply order can be claimed')
    return ordered


def main():
    password = os.environ.get('SADINHUB_PASSWORD') or getpass.getpass(
        f'PostgreSQL password for {USER}@{HOST}/{DATABASE}: ')
    progress = print
    url = URL.create('postgresql+psycopg', username=USER, password=password,
                     host=HOST, port=PORT, database=DATABASE)
    engine = create_engine(url, connect_args={
        'connect_timeout': 10,
        'options': '-c default_transaction_read_only=on -c statement_timeout=600000'})
    stamp = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    counts = defaultdict(int)

    with engine.connect() as connection:
        if connection.execute(text('SHOW transaction_read_only')).scalar_one() != 'on':
            raise RuntimeError('Refusing to continue: connection is not read-only')
        version = connection.execute(text('SHOW server_version')).scalar_one()

        def header(title, schema, source, extra=''):
            return HEADER.format(title=title, version=version, stamp=stamp,
                                 database=DATABASE, schema=schema, source=source,
                                 extra=extra)

        # ------------------------------------------------------------- views
        progress('Views and materialised views...')
        view_rows = connection.execute(text("""
            SELECT n.nspname, c.relname, c.relkind,
                   pg_get_viewdef(c.oid, true) AS definition
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('v', 'm') AND n.nspname = ANY(:schemas)
            ORDER BY n.nspname, c.relname
        """), {'schemas': SCHEMAS}).all()

        edges = connection.execute(text("""
            SELECT DISTINCT dn.nspname || '.' || dv.relname AS child,
                            sn.nspname || '.' || st.relname AS parent
            FROM pg_depend d
            JOIN pg_rewrite r ON d.objid = r.oid
            JOIN pg_class dv ON r.ev_class = dv.oid
            JOIN pg_class st ON d.refobjid = st.oid
            JOIN pg_namespace dn ON dn.oid = dv.relnamespace
            JOIN pg_namespace sn ON sn.oid = st.relnamespace
            WHERE d.classid = 'pg_rewrite'::regclass
              AND d.refclassid = 'pg_class'::regclass
              AND st.oid <> dv.oid
              AND dn.nspname = ANY(:schemas) AND sn.nspname = ANY(:schemas)
        """), {'schemas': SCHEMAS}).all()

        folder_for = {}
        for schema, name, kind, definition in view_rows:
            if kind == 'm':
                bucket = 'materialized_views'
            elif name.endswith('_landing'):
                bucket = 'landing_views'
            elif name.endswith('_staging'):
                bucket = 'staging_views'
            else:
                bucket = 'views'
            folder_for[f'{schema}.{name}'] = bucket
            keyword = ('CREATE MATERIALIZED VIEW' if kind == 'm' else
                       'CREATE OR REPLACE VIEW')
            note = ('-- A materialised view stores its rows; REFRESH MATERIALIZED VIEW\n'
                    '-- rebuilds them from the query below.\n' if kind == 'm' else '')
            body = header(f'{"Materialised view" if kind == "m" else "View"} '
                          f'{schema}.{name}', schema,
                          'pg_get_viewdef() - this is the definition the server holds',
                          note)
            tail = ' WITH NO DATA;' if kind == 'm' else ';'
            body += f'\n{keyword} {schema}.{name} AS\n{definition.rstrip().rstrip(";")}{tail}\n'
            write(ROOT / layer(schema) / bucket / f'{slug(name)}.sql', body)
            counts[f'{schema} {bucket}'] += 1

        # --------------------------------------------------- functions
        progress('Functions and procedures...')
        routines = connection.execute(text("""
            SELECT n.nspname, p.proname,
                   pg_get_function_identity_arguments(p.oid) AS args,
                   pg_get_functiondef(p.oid) AS definition
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = ANY(:schemas) AND p.prokind IN ('f', 'p')
            ORDER BY n.nspname, p.proname
        """), {'schemas': SCHEMAS}).all()
        by_name = defaultdict(list)
        for row in routines:
            by_name[(row[0], row[1])].append(row)
        for (schema, name), group in sorted(by_name.items()):
            for index, (_, _, args, definition) in enumerate(group):
                # Overloaded routines share a name, so add a suffix to keep files apart.
                suffix = '' if len(group) == 1 else f'__{index + 1}'
                bucket = ('classify_functions'
                          if schema == 'silver' and name.startswith(
                              ('classify_', 'status_', 'worst_'))
                          else 'functions')
                body = header(f'{schema}.{name}({args})', schema,
                              'pg_get_functiondef() - full source held by the server')
                body += f'\n{definition}\n'
                write(ROOT / layer(schema) / bucket / f'{slug(name)}{suffix}.sql', body)
                counts[f'{schema} {bucket}'] += 1

        # ----------------------------------------------------- triggers
        progress('Triggers...')
        triggers = connection.execute(text("""
            SELECT n.nspname, c.relname, t.tgname, pg_get_triggerdef(t.oid, true)
            FROM pg_trigger t
            JOIN pg_class c ON c.oid = t.tgrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE NOT t.tgisinternal AND n.nspname = ANY(:schemas)
            ORDER BY n.nspname, c.relname, t.tgname
        """), {'schemas': SCHEMAS}).all()
        for schema, table, name, definition in triggers:
            body = header(f'Trigger {name} on {schema}.{table}', schema,
                          'pg_get_triggerdef()')
            body += f'\n{definition};\n'
            write(ROOT / layer(schema) / 'triggers' / f'{slug(table)}__{slug(name)}.sql', body)
            counts[f'{schema} triggers'] += 1

        # ------------------------------------------------ table inventory
        progress('Table inventory...')
        tables = connection.execute(text("""
            SELECT n.nspname, c.relname, c.reltuples::bigint,
                   pg_size_pretty(pg_total_relation_size(c.oid)),
                   obj_description(c.oid, 'pg_class')
            FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind = 'r' AND n.nspname = ANY(:schemas)
            ORDER BY n.nspname, c.relname
        """), {'schemas': SCHEMAS}).all()

        # ------------------------------------------- ordered view script
        progress('Working out the order objects must be created in...')
        nodes = set(folder_for)
        order = topological([(c, p) for c, p in edges], nodes)
        lines = [header('Views in dependency order', 'bronze, silver, gold',
                        'pg_depend - each view listed after everything it reads',
                        '-- VIEWS ONLY. Requires schemas, tables, sequences and routines first.\n'
                        '-- This is NOT a complete database restore script.\n'
                        '-- Prefer pg_dump/schema_full.sql for a new empty database.\n')]
        for position, key in enumerate(order, start=1):
            schema, name = key.split('.', 1)
            lines.append(f'-- {position:>3}. {key}   ({folder_for[key]})\n'
                         f'\\ir {layer(schema)}/{folder_for[key]}/{slug(name)}.sql')
        write(ROOT / 'APPLY_ORDER.sql', '\n'.join(lines))

    engine.dispose()

    # ------------------------------------------------------- pg_dump files
    progress('pg_dump schema files...')
    pg_dump = find_pg_dump()
    if pg_dump is None:
        raise RuntimeError('pg_dump not found; table/index/constraint export is incomplete')
    else:
        progress(f'  using {pg_dump}')
        run_pg_dump(pg_dump, password, [], ROOT / 'pg_dump' / 'schema_full.sql', progress)
        for schema in SCHEMAS:
            run_pg_dump(pg_dump, password, ['-n', schema],
                        ROOT / 'pg_dump' / f'schema_{schema}.sql', progress)
        progress('Reference-table rows...')
        export_table_data(pg_dump, password, progress)

    progress('Query text recoverable outside the catalog...')
    export_recovered_history(progress)

    write_inventory(ROOT, stamp, version, tables, view_rows, routines, triggers, counts)
    progress('')
    progress(f'Exported to {ROOT}')
    for key in sorted(counts):
        progress(f'  {key:<28} {counts[key]}')
    return 0


def layer(schema):
    return {'bronze': '01_bronze', 'silver': '02_silver', 'gold': '03_gold'}[schema]


# Small tables that hold configuration or derived reference rows rather than bulk
# telemetry. Their contents are part of the pipeline: dim_meter_cb_rating in
# particular is hand-maintained and every silver.classify_current_v2 call depends
# on it, so the rows are exported as INSERT statements, not just the DDL.
DATA_TABLES = [
    ('silver', 'dim_meter_cb_rating'),
    ('silver', 'data_quality_summary'),
    ('gold', 'energy_reading_gaps'),
]


def export_table_data(pg_dump, password, progress):
    for schema, table in DATA_TABLES:
        destination = ROOT / '04_reference_data' / f'{schema}.{table}.sql'
        environment = dict(os.environ, PGPASSWORD=password)
        command = [str(pg_dump), '-h', HOST, '-p', str(PORT), '-U', USER, '-d', DATABASE,
                   '--data-only', '--column-inserts', '--no-owner', '--no-privileges',
                   '-t', f'{schema}.{table}']
        result = subprocess.run(command, capture_output=True, text=True,
                                env=environment, encoding='utf-8', errors='replace')
        if result.returncode != 0:
            progress(f'    could not export {schema}.{table}')
            continue
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(
            f'-- Rows of {schema}.{table}\n'
            f'-- Exported because this table holds configuration or reference rows\n'
            f'-- that the pipeline depends on and that no view can rebuild.\n\n'
            + result.stdout, encoding='utf-8')
        progress(f'    {schema}.{table}')


def export_recovered_history(progress):
    """Query text still findable outside the catalog: pgAdmin history, server logs."""
    import binascii
    import json
    import sqlite3

    out = ROOT / '05_recovered_history'
    source = Path(os.environ.get('APPDATA', '')) / 'pgAdmin' / 'pgadmin4.db'
    if source.exists():
        connection = sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)
        entries = []
        for _srno, _uid, _sid, dbname, info, _flag in connection.execute(
                'SELECT * FROM query_history WHERE dbname = ?', (DATABASE,)):
            try:
                raw = binascii.unhexlify(info) if isinstance(info, str) else bytes(info)
                parsed = json.loads(raw.decode('utf-8', errors='replace'))
            except (ValueError, binascii.Error):
                continue
            entries.append((parsed.get('start_time') or '', dbname, parsed.get('status'),
                            parsed.get('row_affected'), parsed.get('query', '')))
        connection.close()
        entries.sort()
        lines = ['-- pgAdmin 4 query history, decoded from pgadmin4.db',
                 '-- Only currently retained queries for sadinhub are exported.',
                 '-- This is partial history, not a complete record or a rebuild script.',
                 '-- Kept because these queries document how the data was investigated.',
                 f'-- {len(entries)} entries recovered.', '']
        for start, dbname, status, rows, query in entries:
            lines += ['-- ' + '=' * 74,
                      f'-- {start}  database={dbname}  succeeded={status}  rows={rows}',
                      '-- ' + '=' * 74, query.strip(), '']
        write(out / 'pgadmin_query_history.sql', '\n'.join(lines))
        progress(f'    pgAdmin history: {len(entries)} queries')

    log_directory = Path('C:/Program Files/PostgreSQL/18/data/log')
    if log_directory.is_dir():
        pattern = re.compile(
            r'STATEMENT:\s*(.*?)(?=\n\d{4}-\d\d-\d\d |\Z)', re.DOTALL)
        interesting = re.compile(
            r'^\s*(CREATE|ALTER|DROP|TRUNCATE|INSERT|UPDATE|DELETE|WITH|SELECT)\b',
            re.IGNORECASE)

        def strip_comments(body):
            """A logged script often opens with a banner of -- comment lines."""
            return '\n'.join(line for line in body.splitlines()
                             if line.strip() and not line.lstrip().startswith('--')).strip()

        found, seen = [], set()
        for path in sorted(log_directory.glob('*.log')):
            try:
                content = path.read_text(encoding='utf-8', errors='replace')
            except OSError:
                continue
            for statement in pattern.findall(content):
                statement = statement.strip()
                if interesting.match(strip_comments(statement)) and statement not in seen:
                    seen.add(statement)
                    found.append((path.name, statement))
        lines = ['-- Statements recovered from the PostgreSQL server logs.',
                 '-- STATEMENT records commonly accompany errors or cancellations.',
                 '-- Their presence does not prove a successful execution, database',
                 '-- attribution, or agreement with the current pipeline. Review only.',
                 f'-- {len(found)} distinct statements recovered.', '']
        for name, statement in found:
            lines += ['-- ' + '=' * 74, f'-- from {name}', '-- ' + '=' * 74, statement, '']
        write(out / 'server_log_statements.sql', '\n'.join(lines))
        progress(f'    server logs: {len(found)} statements')

        # The log text keeps the original comments, named constants and layout
        # that the catalog reformats away, so DDL found here is worth its own
        # file next to the catalog version.
        # A recovered block often opens with a comment banner and may hold a
        # DROP followed by a CREATE, so leading comments are stripped and the
        # CREATE target is looked for anywhere in the block, not just at the top.
        ddl = re.compile(r'\b(CREATE|ALTER|DROP|TRUNCATE|INSERT\s+INTO|UPDATE|DELETE\s+FROM)\b',
                         re.IGNORECASE)
        named = re.compile(
            r'\bCREATE\s+(?:OR\s+REPLACE\s+)?'
            r'(TABLE|VIEW|MATERIALIZED\s+VIEW|FUNCTION|PROCEDURE|INDEX|SCHEMA)'
            r'\s+(?:IF\s+NOT\s+EXISTS\s+)?([A-Za-z0-9_."]+)', re.IGNORECASE)
        ddl_count = query_count = 0
        for source_name, statement in found:
            body = '\n'.join(line.replace('\t', '    ')
                             for line in statement.splitlines()).strip()
            uncommented = '\n'.join(
                line for line in body.splitlines()
                if line.strip() and not line.lstrip().startswith('--')).strip()
            note = (f'-- Recovered from PostgreSQL server log {source_name}.\n'
                    f'-- This is the statement text as originally submitted, including\n'
                    f'-- its comments. It is in the log because that execution raised an\n'
                    f'-- error, usually a user cancellation, so confirm it against the\n'
                    f'-- catalog version before relying on it.\n\n')
            match = named.search(uncommented)
            if ddl.match(uncommented) and match:
                kind = re.sub(r'\s+', '_', match.group(1).lower())
                target = match.group(2).replace('"', '').replace('.', '__')
                path = out / 'original_ddl' / f'{kind}__{slug(target)}.sql'
                index = 2
                while path.exists() and path.read_text(encoding='utf-8').strip() != (note + body).strip():
                    path = out / 'original_ddl' / f'{kind}__{slug(target)}__{index}.sql'
                    index += 1
                write(path, note + body)
                ddl_count += 1
            elif len(body) > 700:
                path = out / 'analysis_queries' / f'query_{query_count + 1:02d}.sql'
                write(path, note + body)
                query_count += 1
        progress(f'    split into {ddl_count} DDL files and '
                 f'{query_count} analysis queries')


def write_inventory(root, stamp, version, tables, views, routines, triggers, counts):
    lines = [f'# SADINhub database inventory', '',
             f'PostgreSQL {version}, database `{DATABASE}`, read {stamp}.', '',
             '## Object counts', '',
             '| Schema | Kind | Count |', '|---|---|---|']
    for key in sorted(counts):
        schema, kind = key.split(' ', 1)
        lines.append(f'| {schema} | {kind.replace("_", " ")} | {counts[key]} |')
    table_count = defaultdict(int)
    for schema, *_ in tables:
        table_count[schema] += 1
    for schema in SCHEMAS:
        if table_count[schema]:
            lines.append(f'| {schema} | tables | {table_count[schema]} |')

    lines += ['', '## Tables', '',
              '| Schema | Table | Approx rows | Size |', '|---|---|---:|---:|']
    for schema, name, rows, size, _comment in tables:
        shown = f'{rows:,}' if rows and rows > 0 else '-'
        lines.append(f'| {schema} | `{name}` | {shown} | {size} |')

    lines += ['', '## Views and materialised views', '',
              '| Schema | Name | Kind |', '|---|---|---|']
    for schema, name, kind, _definition in views:
        lines.append(f'| {schema} | `{name}` | '
                     f'{"materialised view" if kind == "m" else "view"} |')

    lines += ['', '## Functions and procedures', '',
              '| Schema | Routine |', '|---|---|']
    for schema, name, args, _definition in routines:
        lines.append(f'| {schema} | `{name}({args})` |')

    if triggers:
        lines += ['', '## Triggers', '', '| Schema | Table | Trigger |', '|---|---|---|']
        for schema, table, name, _definition in triggers:
            lines.append(f'| {schema} | `{table}` | `{name}` |')

    write(root / 'INVENTORY.md', '\n'.join(lines))


if __name__ == '__main__':
    sys.exit(main())
