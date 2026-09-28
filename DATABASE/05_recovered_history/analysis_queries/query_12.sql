-- Recovered from PostgreSQL server log postgresql-2026-07-23_103051.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH five_minute_data AS (
        SELECT
            to_timestamp(t.timestamp / 1000.0)
                AT TIME ZONE 'UTC' AS reading_time_utc,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'V1'
            ) AS v1,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'V2'
            ) AS v2,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'V3'
            ) AS v3,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'PFa'
            ) AS power_factor,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'TkW'
            ) AS total_kw,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'kWh'
            ) AS cumulative_kwh
    
        FROM bronze.telemetries t
    
        JOIN bronze.telemetries_dictionaries td
            ON td.id = t.key_id
    
        JOIN bronze.device d
            ON d.id = t.device_id
    
        WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm','ZN.20-PB.2_child__1_ch3pm',
    
          AND td.key IN (
              'V1', 'V2', 'V3',
              'PFa', 'TkW', 'kWh'
          )
    
          AND t.timestamp >= (
              EXTRACT(
                  EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00'
              ) * 1000
          )::bigint
    
          AND t.timestamp < (
              EXTRACT(
                  EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00'
              ) * 1000
          )::bigint
    
        GROUP BY t.timestamp
    )
    
    SELECT
        DATE_TRUNC('hour', reading_time_utc) AS hour_utc,
    
        ROUND(AVG(total_kw)::numeric, 3)
            AS average_kw,
    
        ROUND(MAX(total_kw)::numeric, 3)
            AS peak_kw,
    
        ROUND(AVG(power_factor)::numeric, 3)
            AS average_power_factor,
    
        ROUND(MIN(v1)::numeric, 2)
            AS minimum_v1,
    
        ROUND(MAX(v1)::numeric, 2)
            AS maximum_v1,
    
        ROUND(
            (
                MAX(cumulative_kwh)
                - MIN(cumulative_kwh)
            )::numeric,
            3
        ) AS estimated_energy_used_kwh
    
    FROM five_minute_data
    
    GROUP BY DATE_TRUNC('hour', reading_time_utc)
    
    ORDER BY hour_utc;
