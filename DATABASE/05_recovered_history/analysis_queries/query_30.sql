-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH random_day AS (
        SELECT reading_date
        FROM silver.dq_meter_daily_completeness_staging
        WHERE actual_reading_count > 0
        ORDER BY RANDOM()
        LIMIT 1
    ),
    bounds AS (
        SELECT
            reading_date,
            (EXTRACT(EPOCH FROM (reading_date::timestamp AT TIME ZONE 'UTC')) * 1000)::bigint AS start_ms,
            (EXTRACT(EPOCH FROM ((reading_date + 1)::timestamp AT TIME ZONE 'UTC')) * 1000)::bigint AS end_ms
        FROM random_day
    ),
    target_keys AS (
        SELECT id, key
        FROM bronze.telemetries_dictionaries
        WHERE key IN (
            'V1', 'V2', 'V3', 'Vn1', 'Vn2', 'Vn3',
            'Amp1', 'Amp2', 'Amp3', 'Hz',
            'PF1', 'PF2', 'PF3', 'PFa',
            'kW1', 'kW2', 'kW3', 'TkW',
            'kVAr1', 'kVAr2', 'kVAr3', 'TkVAr',
            'kWh', 'kVArh', 'kVAh',
            'kVA1', 'kVA2', 'kVA3', 'TkVA'
        )
    ),
    mismatched_telemetries AS (
        -- Pre-filter bronze rows first using timestamp index and target keys
        SELECT 
            br.device_id,
            br.key_id,
            br.timestamp,
            br.dbl AS bronze_exact_value,
            sl.dbl AS silver_cleaned_value,
            x.reading_date
        FROM bounds x
        JOIN bronze.telemetries br 
          ON br.timestamp >= x.start_ms 
         AND br.timestamp < x.end_ms
        JOIN target_keys tk 
          ON tk.id = br.key_id
        JOIN silver.telemetries_landing sl
          ON sl.device_id = br.device_id
         AND sl.key_id = br.key_id
         AND sl.timestamp = br.timestamp
        WHERE br.dbl IS NOT NULL
          AND br.dbl IS DISTINCT FROM sl.dbl
        -- Limit BEFORE joining dimension tables/sorting if you just need any sample
        LIMIT 1000 
    )
    SELECT
        m.reading_date AS selected_random_date,
        z.zone_name,
        d.device_name,
        d.meter_label,
        tk.key AS measurement_key,
        TO_TIMESTAMP(m.timestamp / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
        m.bronze_exact_value,
        m.silver_cleaned_value,
        (m.bronze_exact_value - m.silver_cleaned_value) AS difference
    FROM mismatched_telemetries m
    JOIN target_keys tk ON tk.id = m.key_id
    JOIN silver.dim_energy_meter_staging d ON d.energy_meter_key = m.device_id
    LEFT JOIN silver.dim_zone_staging z ON z.zone_key = d.zone_key
    ORDER BY RANDOM()
    LIMIT 100;
