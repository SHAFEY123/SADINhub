-- Recovered from PostgreSQL server log postgresql-2026-07-29_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            (
                EXTRACT(
                    EPOCH FROM (
                        TIMESTAMP '2025-04-16 00:00:00'
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS start_ms,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        TIMESTAMP '2025-04-16 01:00:00'
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS end_ms
    ),
    
    silver_count AS (
        SELECT COUNT(*) AS reading_count
        FROM silver.fact_energy_readings_staging AS f
        CROSS JOIN params AS p
        WHERE f.source_timestamp_ms >= p.start_ms
          AND f.source_timestamp_ms < p.end_ms
    ),
    
    gold_count AS (
        SELECT COUNT(*) AS reading_count
        FROM gold.energy_reading AS g
        CROSS JOIN params AS p
        WHERE g.source_timestamp_ms >= p.start_ms
          AND g.source_timestamp_ms < p.end_ms
    )
    
    SELECT
        s.reading_count AS silver_readings,
        g.reading_count AS gold_readings,
        s.reading_count - g.reading_count AS empty_rows_excluded
    FROM silver_count AS s
    CROSS JOIN gold_count AS g;
