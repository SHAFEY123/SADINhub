"""Model 1 scope, row-count assertions and the per-meter reading pull.

Two scopes, because Zone 13's exclusion from validated consumption is a cumulative-kWh
integrity concern and not an electrical-measurement one:

    ELECTRICAL  31 meters, 4,535,918 readings  -> families T1, T2, T3, T4
    REGISTER    29 meters, 4,260,849 readings  -> family T5

Every run asserts its own scope's count and fails loudly on a mismatch.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from meters import short_label  # noqa: E402

METER_DIM_SQL = """
    SELECT m.energy_meter_key,
           m.meter_label,
           z.zone_name,
           r.cb_max_rating_a,
           m.phase_count
    FROM gold.meter m
    LEFT JOIN gold.zone z USING (zone_key)
    LEFT JOIN silver.dim_meter_cb_rating r USING (energy_meter_key)
    ORDER BY m.meter_label
"""

# gold.energy_raw carries no meter_label, so every scoped count needs the gold.meter join.
SCOPE_COUNT_SQL = """
    SELECT count(*) AS electrical_readings,
           count(*) FILTER (WHERE m.meter_label NOT LIKE %s) AS register_readings,
           count(DISTINCT m.energy_meter_key) AS electrical_meters,
           count(DISTINCT m.energy_meter_key)
               FILTER (WHERE m.meter_label NOT LIKE %s) AS register_meters
    FROM gold.energy_raw e
    JOIN gold.meter m USING (energy_meter_key)
"""

READINGS_SQL = """
    SELECT reading_timestamp_utc,
           active_power_phase_1_kw, active_power_phase_2_kw, active_power_phase_3_kw,
           active_power_total_kw,
           current_phase_1_a, current_phase_2_a, current_phase_3_a,
           power_factor_phase_1, power_factor_phase_2, power_factor_phase_3,
           active_energy_cumulative_kwh,
           status_amp1, status_amp2, status_amp3,
           status_pf1, status_pf2, status_pf3
    FROM gold.energy_raw
    WHERE energy_meter_key = %s
    ORDER BY reading_timestamp_utc
"""

PHASE_COLUMNS = {
    1: ("active_power_phase_1_kw", "current_phase_1_a", "power_factor_phase_1",
        "status_amp1", "status_pf1"),
    2: ("active_power_phase_2_kw", "current_phase_2_a", "power_factor_phase_2",
        "status_amp2", "status_pf2"),
    3: ("active_power_phase_3_kw", "current_phase_3_a", "power_factor_phase_3",
        "status_amp3", "status_pf3"),
}


class ScopeMismatch(RuntimeError):
    """The live data no longer matches the scope this model was specified against."""


def load_meter_dim(conn) -> pd.DataFrame:
    with conn.cursor() as cur:
        cur.execute(METER_DIM_SQL)
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    df = pd.DataFrame(rows, columns=cols)
    df["energy_meter_key"] = df["energy_meter_key"].astype(str)
    df["short_label"] = df["meter_label"].map(short_label)
    df["is_zone13"] = df["meter_label"].str.startswith("ZN.13-")
    return df


def verify_scope(conn, cfg: dict) -> dict:
    """Assert both scopes against the live database. Fails loudly, never silently."""
    like = cfg["scope"]["zone13_prefix"] + "%"
    with conn.cursor() as cur:
        cur.execute(SCOPE_COUNT_SQL, (like, like))
        row = cur.fetchone()
        cols = [d.name for d in cur.description]
    actual = dict(zip(cols, (int(v) for v in row)))

    expected = {
        "electrical_readings": cfg["scope"]["electrical"]["readings"],
        "electrical_meters": cfg["scope"]["electrical"]["meters"],
        "register_readings": cfg["scope"]["register"]["readings"],
        "register_meters": cfg["scope"]["register"]["meters"],
    }
    mismatches = {k: {"expected": v, "actual": actual[k]}
                  for k, v in expected.items() if actual[k] != v}
    if mismatches:
        raise ScopeMismatch(
            "live row counts do not match the configured Model 1 scope; the model was "
            f"specified against different data: {mismatches}")
    return {"expected": expected, "actual": actual, "verified": True}


def fetch_readings(conn, energy_meter_key: str) -> pd.DataFrame:
    """All readings for one meter, ordered. One meter at a time keeps 4.5M rows off the heap."""
    with conn.cursor() as cur:
        cur.execute(READINGS_SQL, (energy_meter_key,))
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    df = pd.DataFrame(rows, columns=cols)
    if df.empty:
        return df
    df["reading_timestamp_utc"] = pd.to_datetime(df["reading_timestamp_utc"])
    numeric = [c for c in df.columns
               if c.startswith(("active_", "current_", "power_factor"))]
    for c in numeric:
        df[c] = pd.to_numeric(df[c], errors="coerce").astype("float64")
    return df
