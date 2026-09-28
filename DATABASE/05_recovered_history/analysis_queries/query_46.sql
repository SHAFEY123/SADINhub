-- Recovered from PostgreSQL server log postgresql-2026-07-29_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH checked_readings AS (
        SELECT
            device_id,
            reading_timestamp_saudi,
    
            num_nonnulls(
                NULLIF(v1, 0),
                NULLIF(v2, 0),
                NULLIF(v3, 0),
                NULLIF(vn1, 0),
                NULLIF(vn2, 0),
                NULLIF(vn3, 0),
                NULLIF(amp1, 0),
                NULLIF(amp2, 0),
                NULLIF(amp3, 0),
                NULLIF(tkw, 0),
                NULLIF(kw1, 0),
                NULLIF(kw2, 0),
                NULLIF(kw3, 0),
                NULLIF(tkvar, 0),
                NULLIF(pfa, 0),
                NULLIF(pf1, 0),
                NULLIF(pf2, 0),
                NULLIF(pf3, 0),
                NULLIF(hz, 0),
                NULLIF(kwh, 0),
                NULLIF(kvarh, 0)
            ) AS useful_value_count
    
        FROM silver.fact_energy_readings_staging
        WHERE reading_date_saudi = DATE '2025-03-01'
    )
    
    SELECT
        COUNT(*) AS total_silver_rows,
    
        COUNT(*) FILTER (
            WHERE useful_value_count > 0
        ) AS rows_to_keep_in_gold,
    
        COUNT(*) FILTER (
            WHERE useful_value_count = 0
        ) AS rows_to_exclude_from_gold,
    
        ROUND(
            100.0
            * COUNT(*) FILTER (WHERE useful_value_count > 0)
            / NULLIF(COUNT(*), 0),
            2
        ) AS kept_percentage
    
    FROM checked_readings;
