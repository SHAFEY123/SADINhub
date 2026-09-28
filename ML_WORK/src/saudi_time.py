"""Saudi-local time helpers.

Asia/Riyadh is UTC+3 with no daylight saving, so the conversion is a fixed offset and every
Saudi day is exactly 86,400 seconds. That is relied on by Task 0B's coverage denominator, so
it is asserted here rather than assumed.

The `*_utc` columns in PostgreSQL are `timestamp without time zone` holding UTC, so the
offset is applied explicitly and never inferred from a session timezone.
"""
from __future__ import annotations

import numpy as np
import pandas as pd

SAUDI_OFFSET = pd.Timedelta(hours=3)
SECONDS_PER_SAUDI_DAY = 86_400


def utc_to_saudi(ts_utc):
    """Naive-UTC timestamps -> naive Saudi-local timestamps."""
    return ts_utc + SAUDI_OFFSET


def saudi_date(ts_utc):
    """Naive-UTC timestamps -> Saudi-local calendar date."""
    saudi = utc_to_saudi(ts_utc)
    if isinstance(saudi, pd.Series):
        return saudi.dt.normalize()
    if isinstance(saudi, (pd.DatetimeIndex, np.ndarray)):
        return pd.DatetimeIndex(saudi).normalize()
    return pd.Timestamp(saudi).normalize()


def saudi_day_close_utc(day):
    """UTC instant at which Saudi day `day` closes.

    The Saudi day [D 00:00, D+1 00:00) maps to UTC [D-1 21:00, D 21:00), so the close of
    Saudi day D is D 21:00:00 UTC. This is the `as_of` cut for a forecast issued at the end
    of day D.
    """
    day = pd.to_datetime(day)
    if isinstance(day, pd.Series):
        return day.dt.normalize() + pd.Timedelta(hours=21)
    if isinstance(day, pd.DatetimeIndex):
        return day.normalize() + pd.Timedelta(hours=21)
    return pd.Timestamp(day).normalize() + pd.Timedelta(hours=21)


def saudi_day_bounds_utc(day):
    """Half-open UTC window [start, end) covering Saudi day `day`."""
    end = saudi_day_close_utc(day)
    return end - pd.Timedelta(days=1), end


def _self_check() -> None:
    d = pd.Timestamp("2026-06-27")
    start, end = saudi_day_bounds_utc(d)
    assert (end - start).total_seconds() == SECONDS_PER_SAUDI_DAY
    assert saudi_date(pd.Timestamp("2026-06-27 21:30:00")) == pd.Timestamp("2026-06-28")
    assert saudi_date(pd.Timestamp("2026-06-27 20:59:59")) == pd.Timestamp("2026-06-27")


_self_check()
