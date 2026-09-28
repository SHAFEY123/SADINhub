-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH random_meter_day AS MATERIALIZED (
        SELECT
            energy_meter_key,
            zone_name,
            device_name,
            meter_label,
            reading_date
        FROM silver.dq_meter_daily_completeness_staging
        WHERE actual_reading_count > 0
        ORDER BY RANDOM()
        LIMIT 1
    ),
    bounds AS MATERIALIZED (
        SELECT
            r.*,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        r.reading_date::timestamp
                        AT TIME ZONE 'UTC'
                    )
                ) * 1000
            )::bigint AS start_ms,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        (r.reading_date + 1)::timestamp
                        AT TIME ZONE 'UTC'
                    )
                ) * 1000
            )::bigint AS end_ms
    
        FROM random_meter_day AS r
    ),
    random_packet AS MATERIALIZED (
        SELECT DISTINCT
            s.timestamp
    
        FROM silver.telemetries_landing AS s
    
        CROSS JOIN bounds AS b
    
        WHERE s.device_id = b.energy_meter_key
          AND s.timestamp >= b.start_ms
          AND s.timestamp < b.end_ms
          AND s.dbl IS NOT NULL
    
        ORDER BY RANDOM()
    
        LIMIT 1
    )
    SELECT
        b.reading_date AS selected_random_date,
        b.zone_name,
        b.device_name,
        b.meter_label,
    
        TO_TIMESTAMP(br.timestamp / 1000.0)
            AT TIME ZONE 'UTC'
            AS reading_timestamp_utc,
    
        td.key AS measurement_key,
    
        br.dbl AS bronze_exact_value,
        sl.dbl AS silver_cleaned_value,
    
        br.dbl - sl.dbl AS difference
    
    FROM bounds AS b
    
    CROSS JOIN random_packet AS rp
    
    JOIN bronze.telemetries AS br
      ON br.device_id = b.energy_meter_key
     AND br.timestamp = rp.timestamp
    
    JOIN silver.telemetries_landing AS sl
      ON sl.device_id = br.device_id
     AND sl.key_id = br.key_id
     AND sl.timestamp = br.timestamp
    
    JOIN bronze.telemetries_dictionaries AS td
      ON td.id = br.key_id
    
    WHERE br.dbl IS NOT NULL
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
    
    ORDER BY td.key;
