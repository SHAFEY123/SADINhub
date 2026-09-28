-- Recovered from PostgreSQL server log postgresql-2026-07-28_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            'a0396787-f0f9-4037-a5cd-232c3b6e0000'::uuid AS selected_meter,
            (EXTRACT(EPOCH FROM (TIMESTAMP '2025-03-01 00:00:00' AT TIME ZONE 'Asia/Riyadh')) * 1000)::bigint AS start_ms,
            (EXTRACT(EPOCH FROM (TIMESTAMP '2025-03-01 01:00:00' AT TIME ZONE 'Asia/Riyadh')) * 1000)::bigint AS end_ms
    )
    
    -- 1. Aggregate telemetries_landing
    SELECT
        'telemetries_landing'::text AS object_name,
        COUNT(*) AS checked_rows,
        COUNT(*) FILTER (WHERE reading_timestamp_utc IS NULL OR reading_timestamp_saudi IS NULL) AS null_timestamps,
        COUNT(*) FILTER (WHERE reading_timestamp_saudi - reading_timestamp_utc <> INTERVAL '3 hours') AS incorrect_saudi_offset,
        COUNT(*) FILTER (WHERE reading_timestamp_utc IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'UTC')) AS incorrect_utc_timestamp,
        COUNT(*) FILTER (WHERE reading_timestamp_saudi IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh')) AS incorrect_saudi_timestamp,
        COUNT(*) FILTER (WHERE reading_date_saudi IS DISTINCT FROM reading_timestamp_saudi::date) AS incorrect_saudi_date,
        COUNT(*) FILTER (WHERE reading_time_saudi IS DISTINCT FROM reading_timestamp_saudi::time) AS incorrect_saudi_time,
        COUNT(*) FILTER (WHERE saudi_date_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'YYYYMMDD')::integer) AS incorrect_saudi_date_key,
        COUNT(*) FILTER (WHERE saudi_time_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'HH24MISS')::integer) AS incorrect_saudi_time_key
    FROM silver.telemetries_landing AS t
    INNER JOIN params AS p ON t.device_id = p.selected_meter
    WHERE t.timestamp >= p.start_ms AND t.timestamp < p.end_ms
    
    UNION ALL
    
    -- 2. Aggregate telemetries_latest_landing
    SELECT
        'telemetries_latest_landing'::text,
        COUNT(*),
        COUNT(*) FILTER (WHERE reading_timestamp_utc IS NULL OR reading_timestamp_saudi IS NULL),
        COUNT(*) FILTER (WHERE reading_timestamp_saudi - reading_timestamp_utc <> INTERVAL '3 hours'),
        COUNT(*) FILTER (WHERE reading_timestamp_utc IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'UTC')),
        COUNT(*) FILTER (WHERE reading_timestamp_saudi IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh')),
        COUNT(*) FILTER (WHERE reading_date_saudi IS DISTINCT FROM reading_timestamp_saudi::date),
        COUNT(*) FILTER (WHERE reading_time_saudi IS DISTINCT FROM reading_timestamp_saudi::time),
        COUNT(*) FILTER (WHERE saudi_date_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'YYYYMMDD')::integer),
        COUNT(*) FILTER (WHERE saudi_time_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'HH24MISS')::integer)
    FROM silver.telemetries_latest_landing AS t
    INNER JOIN params AS p ON t.device_id = p.selected_meter
    -- (Note: Left without timestamp filters to match your original query)
    
    UNION ALL
    
    -- 3. Aggregate fact_energy_readings_staging
    SELECT
        'fact_energy_readings_staging'::text,
        COUNT(*),
        COUNT(*) FILTER (WHERE reading_timestamp_utc IS NULL OR reading_timestamp_saudi IS NULL),
        COUNT(*) FILTER (WHERE reading_timestamp_saudi - reading_timestamp_utc <> INTERVAL '3 hours'),
        COUNT(*) FILTER (WHERE reading_timestamp_utc IS DISTINCT FROM (TO_TIMESTAMP(f.source_timestamp_ms / 1000.0) AT TIME ZONE 'UTC')),
        COUNT(*) FILTER (WHERE reading_timestamp_saudi IS DISTINCT FROM (TO_TIMESTAMP(f.source_timestamp_ms / 1000.0) AT TIME ZONE 'Asia/Riyadh')),
        COUNT(*) FILTER (WHERE reading_date_saudi IS DISTINCT FROM reading_timestamp_saudi::date),
        COUNT(*) FILTER (WHERE reading_time_saudi IS DISTINCT FROM reading_timestamp_saudi::time),
        COUNT(*) FILTER (WHERE saudi_date_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'YYYYMMDD')::integer),
        COUNT(*) FILTER (WHERE saudi_time_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'HH24MISS')::integer)
    FROM silver.fact_energy_readings_staging AS f
    INNER JOIN params AS p ON f.energy_meter_key = p.selected_meter
    WHERE f.source_timestamp_ms >= p.start_ms AND f.source_timestamp_ms < p.end_ms;
