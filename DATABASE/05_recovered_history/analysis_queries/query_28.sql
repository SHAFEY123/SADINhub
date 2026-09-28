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
            (
                EXTRACT(
                    EPOCH FROM (
                        reading_date::timestamp AT TIME ZONE 'UTC'
                    )
                ) * 1000
            )::bigint AS start_ms,
            (
                EXTRACT(
                    EPOCH FROM (
                        (reading_date + 1)::timestamp AT TIME ZONE 'UTC'
                    )
                ) * 1000
            )::bigint AS end_ms
        FROM random_day
    )
    SELECT
        x.reading_date AS selected_random_date,
        z.zone_name,
        m.device_name,
        m.meter_label,
        td.key AS measurement_key,
        TO_TIMESTAMP(br.timestamp / 1000.0)
            AT TIME ZONE 'UTC' AS reading_timestamp_utc,
    
        br.dbl AS bronze_exact_value,
        sl.dbl AS silver_cleaned_value,
        br.dbl - sl.dbl AS difference
    
    FROM bronze.telemetries AS br
    JOIN silver.telemetries_landing AS sl
      ON sl.device_id = br.device_id
     AND sl.key_id = br.key_id
     AND sl.timestamp = br.timestamp
    JOIN bronze.telemetries_dictionaries AS td
      ON td.id = br.key_id
    JOIN silver.dim_energy_meter_staging AS m
      ON m.energy_meter_key = br.device_id
    LEFT JOIN silver.dim_zone_staging AS z
      ON z.zone_key = m.zone_key
    CROSS JOIN bounds AS x
    WHERE br.timestamp >= x.start_ms
      AND br.timestamp < x.end_ms
      AND br.dbl IS NOT NULL
      AND br.dbl IS DISTINCT FROM sl.dbl
      AND td.key IN (
          'V1', 'V2', 'V3',
          'Vn1', 'Vn2', 'Vn3',
          'Amp1', 'Amp2', 'Amp3',
          'Hz',
          'PF1', 'PF2', 'PF3', 'PFa',
          'kW1', 'kW2', 'kW3', 'TkW',
          'kVAr1', 'kVAr2', 'kVAr3', 'TkVAr',
          'kWh', 'kVArh', 'kVAh',
          'kVA1', 'kVA2', 'kVA3', 'TkVA'
      )
    ORDER BY RANDOM()
    LIMIT 100;
