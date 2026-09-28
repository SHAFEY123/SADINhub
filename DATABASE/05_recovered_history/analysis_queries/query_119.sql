-- Recovered from PostgreSQL server log postgresql-2026-09-02_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH readings AS (
        SELECT
            meter_label,
            reading_timestamp_utc,
            reading_timestamp_utc + INTERVAL '3 hours'
                AS reading_timestamp_saudi,
            active_energy_cumulative_kwh,
    
            LAG(active_energy_cumulative_kwh) OVER (
                PARTITION BY meter_label
                ORDER BY reading_timestamp_utc
            ) AS previous_kwh,
    
            LAG(reading_timestamp_utc) OVER (
                PARTITION BY meter_label
                ORDER BY reading_timestamp_utc
            ) AS previous_timestamp_utc
    
        FROM silver.fact_energy_readings_snapshot
    
        WHERE meter_label IN (
            'ZN.13-PB.1_child__1_ch3pm',
            'ZN.13-PB.2_child__1_ch3pm'
        )
    
          AND active_energy_cumulative_kwh IS NOT NULL
    )
    
    SELECT
        meter_label,
    
        previous_timestamp_utc,
        reading_timestamp_utc,
    
        reading_timestamp_saudi,
    
        ROUND(previous_kwh::numeric, 2) AS previous_kwh,
        ROUND(active_energy_cumulative_kwh::numeric, 2) AS current_kwh,
    
        ROUND(
            (active_energy_cumulative_kwh - previous_kwh)::numeric,
            2
        ) AS change_kwh
    
    FROM readings
    
    WHERE active_energy_cumulative_kwh < previous_kwh
    
    ORDER BY
        meter_label,
        reading_timestamp_utc;
