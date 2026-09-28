"""Canonical meter identity, shared by every task.

The ML documents refer to meters by short labels ("ZN.16-PB", "ZN.20-PB.1") while the
canonical `meter_label` is "ZN.16-PB_child__1_ch3pm". The mapping lives here once so that
Tasks 0A, 0B, 1, 3 and 4 cannot drift apart on meter identity.
"""
from __future__ import annotations

import pandas as pd

ZONE13_PREFIX = "ZN.13-"
LABEL_SUFFIX = "_child__1_ch3pm"

METER_DIM_SQL = """
    SELECT m.energy_meter_key,
           m.meter_label,
           m.phase_count,
           r.cb_max_rating_a
    FROM gold.meter m
    LEFT JOIN silver.dim_meter_cb_rating r USING (energy_meter_key)
    ORDER BY m.meter_label
"""

# Readings for one meter, in primary-key order so the server returns an index-ordered
# scan on pk_energy_readings_snapshot(energy_meter_key, reading_timestamp_utc) with no sort.
METER_READINGS_SQL = """
    SELECT reading_timestamp_utc,
           active_energy_cumulative_kwh
    FROM gold.energy_raw
    WHERE energy_meter_key = %s
    ORDER BY reading_timestamp_utc
"""


def short_label(meter_label: str) -> str:
    """'ZN.16-PB_child__1_ch3pm' -> 'ZN.16-PB'."""
    if meter_label.endswith(LABEL_SUFFIX):
        return meter_label[: -len(LABEL_SUFFIX)]
    return meter_label.split("_child__")[0]


def is_zone13(meter_label: str) -> bool:
    return meter_label.startswith(ZONE13_PREFIX)


def load_meter_dim(conn) -> pd.DataFrame:
    """All 31 canonical meters with breaker rating and a short label."""
    with conn.cursor() as cur:
        cur.execute(METER_DIM_SQL)
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    df = pd.DataFrame(rows, columns=cols)
    df["short_label"] = df["meter_label"].map(short_label)
    df["is_zone13"] = df["meter_label"].map(is_zone13)
    return df


def replay_scope(meter_dim: pd.DataFrame) -> pd.DataFrame:
    """The 29 meters in validated-consumption scope (rule 1 excludes Zone 13)."""
    return meter_dim.loc[~meter_dim["is_zone13"]].reset_index(drop=True)


METER_STATIC_SQL = """
    SELECT m.energy_meter_key,
           m.meter_label,
           z.zone_name,
           r.cb_max_rating_a
    FROM gold.meter m
    LEFT JOIN gold.zone z USING (zone_key)
    LEFT JOIN silver.dim_meter_cb_rating r USING (energy_meter_key)
    ORDER BY m.meter_label
"""


def load_meter_static(conn) -> pd.DataFrame:
    """Static per-meter covariates for the pooled forecaster: zone name and breaker rating.

    Note the boundary exception: cb_max_rating_a lives only in silver.dim_meter_cb_rating and
    is exposed by no Gold view, so Model 2 reads Silver directly. Read-only, as ever.
    gold.meter carries zone_key (a uuid); the readable zone_name comes from gold.zone.
    """
    with conn.cursor() as cur:
        cur.execute(METER_STATIC_SQL)
        rows = cur.fetchall()
        cols = [d.name for d in cur.description]
    df = pd.DataFrame(rows, columns=cols)
    # psycopg returns uuid.UUID; the Task 0A/0B artifacts carry the key as a string, so
    # normalise here or the pooled join silently finds no match.
    df["energy_meter_key"] = df["energy_meter_key"].astype(str)
    df["cb_max_rating_a"] = df["cb_max_rating_a"].astype("float64")
    df["short_label"] = df["meter_label"].map(short_label)
    return df.loc[~df["meter_label"].map(is_zone13)].reset_index(drop=True)


def fetch_meter_readings(conn, energy_meter_key) -> pd.DataFrame:
    """Source columns only: timestamp + cumulative register. No derived column is read."""
    with conn.cursor() as cur:
        cur.execute(METER_READINGS_SQL, (energy_meter_key,))
        rows = cur.fetchall()
    return pd.DataFrame(
        rows, columns=["reading_timestamp_utc", "active_energy_cumulative_kwh"]
    )
