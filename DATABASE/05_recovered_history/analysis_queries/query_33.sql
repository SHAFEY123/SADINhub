-- Recovered from PostgreSQL server log postgresql-2026-07-28_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            (
                EXTRACT(
                    EPOCH FROM (
                        DATE '2025-03-01'::timestamp
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS start_ms,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        (DATE '2025-03-01' + 1)::timestamp
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS end_ms
    ),
    
    timestamp_rows AS (
        SELECT
            'telemetries_landing'::text AS object_name,
            t.timestamp AS source_timestamp_ms,
            t.reading_timestamp_utc,
            t.reading_timestamp_saudi,
            t.reading_date_saudi,
            t.reading_time_saudi,
            t.saudi_date_key,
            t.saudi_time_key
    
        FROM silver.telemetries_landing AS t
        CROSS JOIN params AS p
    
        WHERE t.timestamp >= p.start_ms
          AND t.timestamp < p.end_ms
    
        UNION ALL
    
        SELECT
            'telemetries_latest_landing'::text,
            t.timestamp,
            t.reading_timestamp_utc,
            t.reading_timestamp_saudi,
            t.reading_date_saudi,
            t.reading_time_saudi,
            t.saudi_date_key,
            t.saudi_time_key
    
        FROM silver.telemetries_latest_landing AS t
    
        UNION ALL
    
        SELECT
            'fact_energy_readings_staging'::text,
            f.source_timestamp_ms,
            f.reading_timestamp_utc,
            f.reading_timestamp_saudi,
            f.reading_date_saudi,
            f.reading_time_saudi,
            f.saudi_date_key,
            f.saudi_time_key
    
        FROM silver.fact_energy_readings_staging AS f
        CROSS JOIN params AS p
    
        WHERE f.source_timestamp_ms >= p.start_ms
          AND f.source_timestamp_ms < p.end_ms
    )
    
    SELECT
        object_name,
        COUNT(*) AS checked_rows,
    
        COUNT(*) FILTER (
            WHERE reading_timestamp_saudi
                  - reading_timestamp_utc
                  <> INTERVAL '3 hours'
        ) AS incorrect_utc_offset,
    
        COUNT(*) FILTER (
            WHERE reading_timestamp_utc IS DISTINCT FROM
                (
                    TO_TIMESTAMP(source_timestamp_ms / 1000.0)
                    AT TIME ZONE 'UTC'
                )::timestamp without time zone
        ) AS incorrect_utc_timestamp,
    
        COUNT(*) FILTER (
            WHERE reading_timestamp_saudi IS DISTINCT FROM
                (
                    TO_TIMESTAMP(source_timestamp_ms / 1000.0)
                    AT TIME ZONE 'Asia/Riyadh'
                )::timestamp without time zone
        ) AS incorrect_saudi_timestamp,
    
        COUNT(*) FILTER (
            WHERE reading_date_saudi IS DISTINCT FROM
                  reading_timestamp_saudi::date
        ) AS incorrect_saudi_date,
    
        COUNT(*) FILTER (
            WHERE reading_time_saudi IS DISTINCT FROM
                  reading_timestamp_saudi::time
        ) AS incorrect_saudi_time,
    
        COUNT(*) FILTER (
            WHERE saudi_date_key IS DISTINCT FROM
                TO_CHAR(
                    reading_timestamp_saudi,
                    'YYYYMMDD'
                )::integer
        ) AS incorrect_saudi_date_key,
    
        COUNT(*) FILTER (
            WHERE saudi_time_key IS DISTINCT FROM
                TO_CHAR(
                    reading_timestamp_saudi,
                    'HH24MISS'
                )::integer
        ) AS incorrect_saudi_time_key
    
    FROM timestamp_rows
    
    GROUP BY object_name
    
    ORDER BY object_name;
