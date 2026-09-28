-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            '2025-03-01'::timestamptz AS window_start,               -- inclusive
            '2025-03-08'::timestamptz AS window_end,                 -- exclusive
            0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
            5.0                        AS spike_zscore_threshold            -- std devs
    ),
     
    -- ---------------------------------------------------------------------------
    -- 1. Base reading set for the window, with meter/zone context
    -- ---------------------------------------------------------------------------
    base_readings AS (
        SELECT
            f.energy_meter_key,
            m.meter_name,
            z.zone_name,
            f.reading_timestamp_utc,
            f.v1, f.v2, f.v3, f.va,
            f.amp1, f.amp2, f.amp3, f.ampa,
            f.hz,
            f.pf1, f.pf2, f.pf3, f.pfa,
            f.tkw, f.tkva, f.tkvar,
            f.kwh, f.kvah, f.kvarh
        FROM silver.fact_energy_readings_staging f
        INNER JOIN silver.dim_energy_meter_staging m
            ON m.energy_meter_key = f.energy_meter_key
        INNER JOIN silver.dim_zone_staging z
            ON z.zone_key = m.zone_key
        CROSS JOIN params p
        WHERE f.reading_timestamp_utc >= p.window_start
          AND f.reading_timestamp_utc <  p.window_end
