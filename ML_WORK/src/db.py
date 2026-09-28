"""Read-only PostgreSQL access for the SADINhub ML branch.

The safety boundary for every ML task: the connection is read-only and REPEATABLE READ
*from its first transaction*, and that is verified before any query runs.

Why libpq connect options rather than SET SESSION CHARACTERISTICS: psycopg3 opens a
transaction on the first execute(), and `transaction_read_only` is fixed at transaction
start. `SET SESSION CHARACTERISTICS` only changes the default for *future* transactions, so
issuing it after connecting cannot affect the transaction already running and a later
verification reads `off`. Passing `-c default_transaction_read_only=on` at connect time
applies it from the very first transaction. This mirrors the pattern already working in
DATABASE/export_database.py.

No password is ever stored here. It comes from SADINHUB_PASSWORD or an interactive prompt,
and is never written into a DSN string, a log line or run metadata.
"""
from __future__ import annotations

import getpass
import os
from contextlib import contextmanager
from pathlib import Path

import psycopg
import yaml

CONFIG_PATH = Path(__file__).resolve().parent.parent / "config" / "db_config.yaml"


class ReadOnlyViolation(RuntimeError):
    """The connection could not be proven read-only. Never downgrade this to a warning."""


def load_config(path: Path | None = None) -> dict:
    with open(path or CONFIG_PATH, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    for key in ("host", "port", "dbname", "user"):
        if key not in cfg:
            raise KeyError(f"db_config.yaml is missing required key: {key}")
    if "password" in cfg:
        raise ReadOnlyViolation(
            "db_config.yaml contains a 'password' key. Remove it — the password comes "
            "from the SADINHUB_PASSWORD environment variable or an interactive prompt."
        )
    return cfg


def _password(cfg: dict) -> str:
    pw = os.environ.get("SADINHUB_PASSWORD")
    if pw:
        return pw
    return getpass.getpass(
        f"PostgreSQL password for {cfg['user']}@{cfg['host']}/{cfg['dbname']}: "
    )


@contextmanager
def readonly_connection(cfg: dict | None = None, statement_timeout_ms: int = 600_000):
    """Yield a psycopg connection that is verified read-only and REPEATABLE READ.

    Raises ReadOnlyViolation if either property cannot be confirmed. Deliberately not an
    `assert` — python -O strips assert statements, which would silently remove the only
    safety gate the ML branch has.
    """
    cfg = cfg or load_config()
    options = (
        "-c default_transaction_read_only=on "
        "-c default_transaction_isolation=repeatable\\ read "
        f"-c statement_timeout={int(statement_timeout_ms)}"
    )
    conn = psycopg.connect(
        host=cfg["host"],
        port=cfg["port"],
        dbname=cfg["dbname"],
        user=cfg["user"],
        password=_password(cfg),
        connect_timeout=cfg.get("connect_timeout", 10),
        options=options,
    )
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT current_setting('transaction_read_only'), "
                "       current_setting('transaction_isolation'), "
                "       current_setting('statement_timeout')"
            )
            read_only, isolation, timeout = cur.fetchone()

        if read_only != "on":
            raise ReadOnlyViolation(
                f"Refusing to proceed: transaction_read_only is {read_only!r}, not 'on'."
            )
        if isolation.replace(" ", "").lower() != "repeatableread":
            raise ReadOnlyViolation(
                f"Refusing to proceed: transaction_isolation is {isolation!r}, "
                "not 'repeatable read'."
            )
        yield conn
    finally:
        conn.close()


def connection_facts(conn) -> dict:
    """Facts recorded into run_metadata.json as evidence of the safety boundary."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT version(), current_database(), current_user, "
            "       current_setting('transaction_read_only'), "
            "       current_setting('transaction_isolation'), "
            "       current_setting('statement_timeout')"
        )
        version, database, user, read_only, isolation, timeout = cur.fetchone()
    return {
        "server_version": version,
        "database": database,
        "user": user,
        "transaction_read_only": read_only,
        "transaction_isolation": isolation,
        "statement_timeout": timeout,
    }
