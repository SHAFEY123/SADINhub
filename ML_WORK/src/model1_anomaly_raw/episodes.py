"""Collapse flagged readings into episodes.

An event is a contiguous flagged episode, never a single reading. Two runs of flagged
readings merge into one episode when the time between them is at most
`episodes.merge_gap_minutes`, so a brief recovery inside a chronic fault does not shatter it
into thousands of events.

Splitting on the TIME gap rather than the index gap handles both cases at once: adjacent
flagged readings are one sampling interval apart and always merge, while two flagged
readings that happen to be adjacent in index across a 201-day telemetry gap do not.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def collapse(timestamps: pd.Series | np.ndarray, flags: np.ndarray,
             merge_gap_minutes: float, min_readings: int = 1) -> list[dict]:
    """Return one record per episode: index span, timestamp span and flagged count."""
    flags = np.asarray(flags, dtype=bool)
    ts = pd.to_datetime(pd.Series(timestamps).to_numpy())
    if flags.size != ts.size:
        raise ValueError("flags and timestamps must be the same length")

    idx = np.flatnonzero(flags)
    if idx.size == 0:
        return []

    flagged_ts = ts[idx]
    gap = np.diff(flagged_ts) / np.timedelta64(1, "m")
    split_after = np.flatnonzero(gap > float(merge_gap_minutes))
    starts = np.concatenate(([0], split_after + 1))
    ends = np.concatenate((split_after, [idx.size - 1]))

    episodes = []
    for s, e in zip(starts, ends):
        first, last = int(idx[s]), int(idx[e])
        n_flagged = int(e - s + 1)
        if n_flagged < min_readings:
            continue
        span = ts[last] - ts[first]
        episodes.append({
            "first_index": first,
            "last_index": last,
            "event_start": pd.Timestamp(ts[first]),
            "event_end": pd.Timestamp(ts[last]),
            "duration_hours": float(span / np.timedelta64(1, "h")),
            "n_flagged": n_flagged,
            "evidence_window_rows": int(last - first + 1),
        })
    return episodes


def collapse_days(days: pd.Series | np.ndarray, flags: np.ndarray,
                  merge_gap_days: float = 1.0, min_days: int = 1) -> list[dict]:
    """Day-grain counterpart, for the register and change families.

    `merge_gap_days` of 1.0 means consecutive calendar days merge and a skipped day splits.
    """
    flags = np.asarray(flags, dtype=bool)
    d = pd.to_datetime(pd.Series(days).to_numpy())
    idx = np.flatnonzero(flags)
    if idx.size == 0:
        return []

    flagged = d[idx]
    gap = np.diff(flagged) / np.timedelta64(1, "D")
    split_after = np.flatnonzero(gap > float(merge_gap_days))
    starts = np.concatenate(([0], split_after + 1))
    ends = np.concatenate((split_after, [idx.size - 1]))

    episodes = []
    for s, e in zip(starts, ends):
        first, last = int(idx[s]), int(idx[e])
        n_days = int(e - s + 1)
        if n_days < min_days:
            continue
        episodes.append({
            "first_index": first,
            "last_index": last,
            "event_start": pd.Timestamp(d[first]),
            "event_end": pd.Timestamp(d[last]),
            "duration_hours": float(
                ((d[last] - d[first]) / np.timedelta64(1, "h")) + 24.0),
            "n_flagged": n_days,
            "evidence_window_rows": int(last - first + 1),
        })
    return episodes
