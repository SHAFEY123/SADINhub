"""Shared fixtures for the SADINhub ML tests.

Database-backed tests skip cleanly when SADINHUB_PASSWORD is unset, so the pure-logic tests
still run in an environment without database access.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pandas as pd
import pytest

ML_WORK = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ML_WORK / "src"))

from db import readonly_connection  # noqa: E402
from meters import load_meter_dim, replay_scope  # noqa: E402

DB_AVAILABLE = bool(os.environ.get("SADINHUB_PASSWORD"))
requires_db = pytest.mark.skipif(not DB_AVAILABLE, reason="SADINHUB_PASSWORD not set")


@pytest.fixture(scope="session")
def conn():
    if not DB_AVAILABLE:
        pytest.skip("SADINHUB_PASSWORD not set")
    with readonly_connection() as connection:
        yield connection


@pytest.fixture(scope="session")
def meter_dim(conn) -> pd.DataFrame:
    return load_meter_dim(conn)


@pytest.fixture(scope="session")
def scope_meters(meter_dim) -> pd.DataFrame:
    return replay_scope(meter_dim)


@pytest.fixture(scope="session")
def forward_looking_rows(conn) -> pd.DataFrame:
    """The 23 readings produced by the two forward-looking rules, straight from Gold.

    This is comparison evidence, not replay input.
    """
    sql = """
        SELECT v.energy_meter_key, v.meter_label, v.reading_timestamp_utc,
               v.reading_date_saudi, v.consumption_cleaning_status, v.interval_quality
        FROM gold.energy_consumption_validated v
        WHERE v.consumption_cleaning_status IN ('ISOLATED_LOW_BAD', 'ISOLATED_HIGH_BAD')
        ORDER BY v.meter_label, v.reading_timestamp_utc
    """
    with conn.cursor() as cur:
        cur.execute(sql)
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    return pd.DataFrame(rows, columns=cols)


def make_readings(timestamps, kwh) -> pd.DataFrame:
    """Build a synthetic readings frame in the shape replay functions expect."""
    return pd.DataFrame({
        "reading_timestamp_utc": pd.to_datetime(list(timestamps)),
        "active_energy_cumulative_kwh": [float(v) for v in kwh],
    })
