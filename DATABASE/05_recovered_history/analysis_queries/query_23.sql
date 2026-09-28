-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH random_meter_day AS (
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
    bounds AS (
        SELECT
            r.*,
            (
                EXTRACT(
                    EPOCH FROM (
                        r.reading_date::timestamp AT TIME ZONE 'UTC'
                    )
                ) * 1000
            )::bigint AS start_ms,
            (
                EXTRACT(
                    EPOCH FROM (
                        (r.reading_date + 1)::timestamp AT TIME ZONE 'UTC'
                    )
                ) * 1000
            )::bigint AS end_ms
        FROM random_meter_day AS r
    ),
    random_packet AS (
        SELECT DISTINCT s.timestamp
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
        TO_TIMESTAMP(p.timestamp / 1000.0)
            AT TIME ZONE 'UTC' AS packet_timestamp_utc,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'V1') AS v1,
        MAX(s.dbl) FILTER (WHERE td.key = 'V2') AS v2,
        MAX(s.dbl) FILTER (WHERE td.key = 'V3') AS v3,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'Vn1') AS vn1,
        MAX(s.dbl) FILTER (WHERE td.key = 'Vn2') AS vn2,
        MAX(s.dbl) FILTER (WHERE td.key = 'Vn3') AS vn3,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
        MAX(s.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
        MAX(s.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'Hz') AS hz,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'PF1') AS pf1,
        MAX(s.dbl) FILTER (WHERE td.key = 'PF2') AS pf2,
        MAX(s.dbl) FILTER (WHERE td.key = 'PF3') AS pf3,
        MAX(s.dbl) FILTER (WHERE td.key = 'PFa') AS pfa,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'kW1') AS kw1,
        MAX(s.dbl) FILTER (WHERE td.key = 'kW2') AS kw2,
        MAX(s.dbl) FILTER (WHERE td.key = 'kW3') AS kw3,
        MAX(s.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'kVAr1') AS kvar1,
        MAX(s.dbl) FILTER (WHERE td.key = 'kVAr2') AS kvar2,
        MAX(s.dbl) FILTER (WHERE td.key = 'kVAr3') AS kvar3,
        MAX(s.dbl) FILTER (WHERE td.key = 'TkVAr') AS total_kvar,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'kVA1') AS kva1,
        MAX(s.dbl) FILTER (WHERE td.key = 'kVA2') AS kva2,
        MAX(s.dbl) FILTER (WHERE td.key = 'kVA3') AS kva3,
        MAX(s.dbl) FILTER (WHERE td.key = 'TkVA') AS total_kva,
    
        MAX(s.dbl) FILTER (WHERE td.key = 'kWh') AS kwh,
        MAX(s.dbl) FILTER (WHERE td.key = 'kVAh') AS kvah,
        MAX(s.dbl) FILTER (WHERE td.key = 'kVArh') AS kvarh
    
    FROM bounds AS b
    CROSS JOIN random_packet AS p
    JOIN silver.telemetries_landing AS s
      ON s.device_id = b.energy_meter_key
     AND s.timestamp = p.timestamp
    JOIN bronze.telemetries_dictionaries AS td
      ON td.id = s.key_id
    GROUP BY
        b.reading_date,
        b.zone_name,
        b.device_name,
        b.meter_label,
        p.timestamp;
