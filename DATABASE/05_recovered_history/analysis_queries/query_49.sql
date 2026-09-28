-- Recovered from PostgreSQL server log postgresql-2026-07-29_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            1744741200000::bigint AS start_ms,
            1744744800000::bigint AS end_ms
    )
    
    SELECT
        silver_readings,
        gold_readings,
        silver_readings - gold_readings AS empty_rows_excluded
    
    FROM params AS p
    
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS silver_readings
        FROM silver.fact_energy_readings_staging AS f
        WHERE f.source_timestamp_ms >= p.start_ms
          AND f.source_timestamp_ms < p.end_ms
    ) AS s
    
    CROSS JOIN LATERAL (
        SELECT COUNT(*) AS gold_readings
        FROM gold.energy_reading AS g
        WHERE g.source_timestamp_ms >= p.start_ms
          AND g.source_timestamp_ms < p.end_ms
    ) AS gold;
