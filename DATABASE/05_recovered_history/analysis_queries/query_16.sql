-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            (
                EXTRACT(
                    EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00'
                ) * 1000
            )::bigint AS start_ms,
    
            (
                EXTRACT(
                    EPOCH FROM TIMESTAMPTZ '2025-03-08 00:00:00+00'
                ) * 1000
            )::bigint AS end_ms
    ),
    
    readings AS (
        SELECT
            t.device_id,
            t.timestamp,
    
            (
                TO_TIMESTAMP(t.timestamp / 1000.0)
                AT TIME ZONE 'UTC'
            )::date AS reading_date,
    
            LAG(t.timestamp) OVER (
                PARTITION BY t.device_id
                ORDER BY t.timestamp
            ) AS previous_timestamp
    
        FROM bronze.telemetries AS t
    
        JOIN params AS p
            ON t.timestamp >= p.start_ms
           AND t.timestamp < p.end_ms
    
        JOIN bronze.telemetries_dictionaries AS td
            ON td.id = t.key_id
           AND td.key = 'TkW'
    ),
    
    gaps AS (
        SELECT
            device_id,
            reading_date,
            timestamp,
            previous_timestamp,
    
            (
                timestamp - previous_timestamp
            ) / 1000.0 AS gap_seconds
    
        FROM readings
    
        WHERE previous_timestamp IS NOT NULL
    ),
    
    device_baseline AS (
        SELECT
            device_id,
    
            PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY gap_seconds
            ) AS expected_gap_seconds
    
        FROM gaps
    
        GROUP BY device_id
    ),
    
    daily_counts AS (
        SELECT
            device_id,
            reading_date,
            COUNT(DISTINCT timestamp) AS actual_reading_count,
            MIN(timestamp) AS first_timestamp_ms,
            MAX(timestamp) AS last_timestamp_ms
    
        FROM readings
    
        GROUP BY
            device_id,
            reading_date
    ),
    
    daily_gap_quality AS (
        SELECT
            g.device_id,
            g.reading_date,
    
            COUNT(*) FILTER (
                WHERE g.gap_seconds >
                      b.expected_gap_seconds * 1.5
            ) AS large_gap_count,
    
            COALESCE(
                SUM(
                    GREATEST(
                        ROUND(
                            g.gap_seconds
                            / b.expected_gap_seconds
                        )::integer - 1,
                        0
                    )
                ) FILTER (
                    WHERE g.gap_seconds >
                          b.expected_gap_seconds * 1.5
                ),
                0
            ) AS estimated_missing_readings,
    
            MAX(g.gap_seconds) AS maximum_gap_seconds
    
        FROM gaps AS g
    
        JOIN device_baseline AS b
            ON b.device_id = g.device_id
    
        GROUP BY
            g.device_id,
            g.reading_date
    )
    
    SELECT
        z.zone_name,
        m.device_name,
        m.meter_label,
    
        dc.reading_date,
    
        ROUND(
            b.expected_gap_seconds::numeric,
            3
        ) AS expected_gap_seconds,
    
        ROUND(
            (
                b.expected_gap_seconds / 60
            )::numeric,
            3
        ) AS expected_gap_minutes,
    
        ROUND(
            86400.0 / b.expected_gap_seconds
        )::integer AS expected_reading_count,
    
        dc.actual_reading_count,
    
        ROUND(
            (
                dc.actual_reading_count::numeric
                /
                ROUND(
                    86400.0 / b.expected_gap_seconds
                )
            ) * 100,
            2
        ) AS cadence_adjusted_completeness_percent,
    
        COALESCE(dg.large_gap_count, 0)
            AS large_gap_count,
    
        COALESCE(dg.estimated_missing_readings, 0)
            AS estimated_missing_readings,
    
        ROUND(
            dg.maximum_gap_seconds::numeric,
            3
        ) AS maximum_gap_seconds,
    
        TO_TIMESTAMP(dc.first_timestamp_ms / 1000.0)
            AT TIME ZONE 'UTC'
            AS first_reading_utc,
    
        TO_TIMESTAMP(dc.last_timestamp_ms / 1000.0)
            AT TIME ZONE 'UTC'
            AS last_reading_utc,
    
        CASE
            WHEN COALESCE(dg.large_gap_count, 0) > 0
                THEN 'MISSING_INTERVALS_DETECTED'
    
            WHEN dc.actual_reading_count >=
                 ROUND(
                     86400.0 / b.expected_gap_seconds
                 )
                THEN 'COMPLETE'
    
            WHEN dc.actual_reading_count >=
                 ROUND(
                     86400.0 / b.expected_gap_seconds
                 ) - 1
                THEN 'COMPLETE_WITH_DAY_BOUNDARY_VARIATION'
    
            ELSE 'LOW_COMPLETENESS_REVIEW'
        END AS daily_quality_status,
    
        CASE
            WHEN ABS(
                b.expected_gap_seconds - 300
            ) <= 15
                THEN 'STANDARD_APPROXIMATELY_5_MINUTES'
    
            ELSE 'NON_STANDARD_STABLE_CADENCE'
        END AS cadence_status
    
    FROM daily_counts AS dc
    
    JOIN device_baseline AS b
        ON b.device_id = dc.device_id
    
    LEFT JOIN daily_gap_quality AS dg
        ON dg.device_id = dc.device_id
       AND dg.reading_date = dc.reading_date
    
    LEFT JOIN silver.dim_energy_meter_staging AS m
        ON m.energy_meter_key = dc.device_id
    
    LEFT JOIN silver.dim_zone_staging AS z
        ON z.zone_key = m.zone_key
    
    ORDER BY
        dc.reading_date,
        z.zone_name,
        m.device_name;
