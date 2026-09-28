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
                        TIMESTAMP '2025-03-01 00:00:00'
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS start_ms,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        TIMESTAMP '2025-03-02 00:00:00'
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS end_ms
    ),
    
    telemetries_check AS (
        SELECT
            'telemetries_landing'::text AS object_name,
            COUNT(*) AS checked_rows,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_saudi
                        - reading_timestamp_utc
                      <> INTERVAL '3 hours'
            ) AS incorrect_utc_offset,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_utc IS DISTINCT FROM
                    (
                        TO_TIMESTAMP(timestamp / 1000.0)
                        AT TIME ZONE 'UTC'
                    )
            ) AS incorrect_utc_timestamp,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_saudi IS DISTINCT FROM
                    (
                        TO_TIMESTAMP(timestamp / 1000.0)
                        AT TIME ZONE 'Asia/Riyadh'
                    )
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
                      (
                          EXTRACT(YEAR FROM reading_timestamp_saudi)::integer
                          * 10000
                        + EXTRACT(MONTH FROM reading_timestamp_saudi)::integer
                          * 100
                        + EXTRACT(DAY FROM reading_timestamp_saudi)::integer
                      )
            ) AS incorrect_saudi_date_key,
    
            COUNT(*) FILTER (
                WHERE saudi_time_key IS DISTINCT FROM
                      (
                          EXTRACT(HOUR FROM reading_timestamp_saudi)::integer
                          * 10000
                        + EXTRACT(MINUTE FROM reading_timestamp_saudi)::integer
                          * 100
                        + FLOOR(
                              EXTRACT(SECOND FROM reading_timestamp_saudi)
                          )::integer
                      )
            ) AS incorrect_saudi_time_key
    
        FROM silver.telemetries_landing AS t
        CROSS JOIN params AS p
    
        WHERE t.timestamp >= p.start_ms
          AND t.timestamp < p.end_ms
    ),
    
    latest_check AS (
        SELECT
            'telemetries_latest_landing'::text AS object_name,
            COUNT(*) AS checked_rows,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_saudi
                        - reading_timestamp_utc
                      <> INTERVAL '3 hours'
            ) AS incorrect_utc_offset,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_utc IS DISTINCT FROM
                    (
                        TO_TIMESTAMP(timestamp / 1000.0)
                        AT TIME ZONE 'UTC'
                    )
            ) AS incorrect_utc_timestamp,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_saudi IS DISTINCT FROM
                    (
                        TO_TIMESTAMP(timestamp / 1000.0)
                        AT TIME ZONE 'Asia/Riyadh'
                    )
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
                      (
                          EXTRACT(YEAR FROM reading_timestamp_saudi)::integer
                          * 10000
                        + EXTRACT(MONTH FROM reading_timestamp_saudi)::integer
                          * 100
                        + EXTRACT(DAY FROM reading_timestamp_saudi)::integer
                      )
            ) AS incorrect_saudi_date_key,
    
            COUNT(*) FILTER (
                WHERE saudi_time_key IS DISTINCT FROM
                      (
                          EXTRACT(HOUR FROM reading_timestamp_saudi)::integer
                          * 10000
                        + EXTRACT(MINUTE FROM reading_timestamp_saudi)::integer
                          * 100
                        + FLOOR(
                              EXTRACT(SECOND FROM reading_timestamp_saudi)
                          )::integer
                      )
            ) AS incorrect_saudi_time_key
    
        FROM silver.telemetries_latest_landing AS t
        CROSS JOIN params AS p
    
        WHERE t.timestamp >= p.start_ms
          AND t.timestamp < p.end_ms
    ),
    
    fact_check AS (
        SELECT
            'fact_energy_readings_staging'::text AS object_name,
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
                    )
            ) AS incorrect_utc_timestamp,
    
            COUNT(*) FILTER (
                WHERE reading_timestamp_saudi IS DISTINCT FROM
                    (
                        TO_TIMESTAMP(source_timestamp_ms / 1000.0)
                        AT TIME ZONE 'Asia/Riyadh'
                    )
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
                      (
                          EXTRACT(YEAR FROM reading_timestamp_saudi)::integer
                          * 10000
                        + EXTRACT(MONTH FROM reading_timestamp_saudi)::integer
                          * 100
                        + EXTRACT(DAY FROM reading_timestamp_saudi)::integer
                      )
            ) AS incorrect_saudi_date_key,
    
            COUNT(*) FILTER (
                WHERE saudi_time_key IS DISTINCT FROM
                      (
                          EXTRACT(HOUR FROM reading_timestamp_saudi)::integer
                          * 10000
                        + EXTRACT(MINUTE FROM reading_timestamp_saudi)::integer
                          * 100
                        + FLOOR(
                              EXTRACT(SECOND FROM reading_timestamp_saudi)
                          )::integer
                      )
            ) AS incorrect_saudi_time_key
    
        FROM silver.fact_energy_readings_staging AS f
        CROSS JOIN params AS p
    
        WHERE f.source_timestamp_ms >= p.start_ms
          AND f.source_timestamp_ms < p.end_ms
    )
    
    SELECT * FROM telemetries_check
    UNION ALL
    SELECT * FROM latest_check
    UNION ALL
    SELECT * FROM fact_check
    ORDER BY object_name;
