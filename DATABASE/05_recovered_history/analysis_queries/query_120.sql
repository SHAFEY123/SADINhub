-- Recovered from PostgreSQL server log postgresql-2026-09-04_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

select * 

    from 

    (

        WITH readings AS (
        SELECT
            energy_meter_key,
            reading_timestamp_utc,
            active_energy_cumulative_kwh,
    
            LAG(active_energy_cumulative_kwh, 1) OVER (
                PARTITION BY energy_meter_key
                ORDER BY reading_timestamp_utc
            ) AS previous_kwh,
    
            LAG(active_energy_cumulative_kwh, 2) OVER (
                PARTITION BY energy_meter_key
                ORDER BY reading_timestamp_utc
            ) AS two_back_kwh,
    
            LAG(reading_timestamp_utc, 1) OVER (
                PARTITION BY energy_meter_key
                ORDER BY reading_timestamp_utc
            ) AS previous_timestamp_utc,
    
            LAG(reading_timestamp_utc, 2) OVER (
                PARTITION BY energy_meter_key
                ORDER BY reading_timestamp_utc
            ) AS two_back_timestamp_utc,
    
            LEAD(active_energy_cumulative_kwh, 1) OVER (
                PARTITION BY energy_meter_key
                ORDER BY reading_timestamp_utc
            ) AS next_kwh,
    
            LEAD(reading_timestamp_utc, 1) OVER (
                PARTITION BY energy_meter_key
                ORDER BY reading_timestamp_utc
            ) AS next_timestamp_utc
    
        FROM silver.fact_energy_readings_snapshot
    
        WHERE energy_meter_key IN (
            'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2',
            '9fc6d98a-5c79-48df-abd5-c0a21e61f40c'
        )
    
        AND active_energy_cumulative_kwh IS NOT NULL
    ),
    
    stats AS (
        SELECT
            energy_meter_key,
    
            PERCENTILE_CONT(0.99)
            WITHIN GROUP (
                ORDER BY active_energy_cumulative_kwh - previous_kwh
            ) FILTER (
                WHERE active_energy_cumulative_kwh > previous_kwh
            ) AS p99_positive_change
    
        FROM readings
        GROUP BY energy_meter_key
    ),
    
    drops AS (
        SELECT
            r.*,
            s.p99_positive_change,
    
            previous_kwh - active_energy_cumulative_kwh
                AS decrement_size_kwh
    
        FROM readings r
    
        JOIN stats s
            ON s.energy_meter_key = r.energy_meter_key
    
        WHERE active_energy_cumulative_kwh < previous_kwh
    ),
    
    classified AS (
        SELECT
            d.*,
    
            recovery.return_timestamp_utc,
            recovery.return_from_kwh,
            recovery.return_to_kwh
    
        FROM drops d
    
        LEFT JOIN LATERAL (
            SELECT
                r2.reading_timestamp_utc AS return_timestamp_utc,
                r2.previous_kwh AS return_from_kwh,
                r2.active_energy_cumulative_kwh AS return_to_kwh
    
            FROM readings r2
    
            WHERE r2.energy_meter_key = d.energy_meter_key
    
              AND r2.reading_timestamp_utc >
                  d.reading_timestamp_utc
    
              AND r2.active_energy_cumulative_kwh >=
                  d.previous_kwh
    
              AND (
                  r2.active_energy_cumulative_kwh -
                  r2.previous_kwh
              ) > (10 * d.p99_positive_change)
    
              AND EXTRACT(
                  EPOCH FROM (
                      r2.reading_timestamp_utc -
                      r2.previous_timestamp_utc
                  )
              ) / 60.0 <= 30
    
            ORDER BY r2.reading_timestamp_utc
            LIMIT 1
    
        ) recovery ON TRUE
    )
    
    SELECT
        CASE
            WHEN c.energy_meter_key =
                'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2'
                THEN 'PB1'
            ELSE 'PB2'
        END AS meter,
    
        c.reading_timestamp_utc + INTERVAL '3 hours'
            AS decrement_timestamp_saudi,
    
        c.previous_kwh,
    
        c.active_energy_cumulative_kwh
            AS current_kwh,
    
        c.decrement_size_kwh,
    
        c.next_kwh,
    
        CASE
            WHEN c.decrement_size_kwh
                <= 10 * c.p99_positive_change
            THEN 'Minor Decrement'
    
            WHEN c.next_kwh >= c.previous_kwh
             AND EXTRACT(
                 EPOCH FROM (
                     c.next_timestamp_utc -
                     c.reading_timestamp_utc
                 )
             ) / 60.0 <= 30
             AND (
                 c.next_kwh -
                 c.active_energy_cumulative_kwh
             ) > 10 * c.p99_positive_change
            THEN 'Isolated Low Sample'
    
            WHEN c.two_back_kwh IS NOT NULL
             AND (
                 c.previous_kwh -
                 c.two_back_kwh
             ) > 10 * c.p99_positive_change
             AND EXTRACT(
                 EPOCH FROM (
                     c.previous_timestamp_utc -
                     c.two_back_timestamp_utc
                 )
             ) / 60.0 <= 30
             AND ABS(
                 c.active_energy_cumulative_kwh -
                 c.two_back_kwh
             ) <= 10 * c.p99_positive_change
            THEN 'Return to Low After Upward Spike'
    
            WHEN c.return_timestamp_utc IS NOT NULL
            THEN 'Temporary Downward Switch'
    
            ELSE 'Unresolved Downward Shift'
    
        END AS problem_type
    
    FROM classified c
    
    ORDER BY
        c.energy_meter_key,
        c.reading_timestamp_utc;

    ) "_"

    limit 0
