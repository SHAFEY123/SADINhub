-- Recovered from PostgreSQL server log postgresql-2026-07-27_180903.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            (
                EXTRACT(EPOCH FROM (
                    DATE '2025-03-01'::timestamp AT TIME ZONE 'Asia/Riyadh'
                )) * 1000
            )::bigint AS start_ms,
            (
                EXTRACT(EPOCH FROM (
                    (DATE '2025-03-01' + 1)::timestamp
                    AT TIME ZONE 'Asia/Riyadh'
                )) * 1000
            )::bigint AS end_ms
    ),
    packet_quality AS (
        SELECT
            t.device_id,
            t.timestamp,
            COUNT(*) AS electrical_row_count,
            COUNT(DISTINCT td.key) AS distinct_electrical_key_count,
            COUNT(*) - COUNT(DISTINCT td.key) AS duplicate_key_rows,
            COUNT(*) FILTER (
                WHERE t.dbl IS NULL
                  AND t.long IS NULL
                  AND t.bool IS NULL
                  AND t.str IS NULL
                  AND t.json IS NULL
            ) AS completely_null_rows,
            COUNT(*) FILTER (
                WHERE t.dbl IS NULL
                  AND (
                      t.long IS NOT NULL
                      OR t.bool IS NOT NULL
                      OR t.str IS NOT NULL
                      OR t.json IS NOT NULL
                  )
            ) AS values_stored_outside_dbl
        FROM bronze.telemetries AS t
        JOIN params AS p
          ON t.timestamp >= p.start_ms
         AND t.timestamp < p.end_ms
        JOIN bronze.telemetries_dictionaries AS td
          ON td.id = t.key_id
        JOIN silver.dim_energy_meter_staging AS m
          ON m.energy_meter_key = t.device_id
        WHERE td.key IN (
            'V1','V2','V3','Va','Vn1','Vn2','Vn3','Vna',
            'Amp1','Amp2','Amp3','Ampa','Hz',
            'PF1','PF2','PF3','PFa',
            'kW1','kW2','kW3','TkW',
            'kVA1','kVA2','kVA3','TkVA',
            'kVAr1','kVAr2','kVAr3','TkVAr',
            'kWh','kVAh','kVArh'
        )
        GROUP BY t.device_id, t.timestamp
    )
    SELECT
        z.zone_name,
        m.device_name,
        m.meter_label,
        TO_TIMESTAMP(q.timestamp / 1000.0) AT TIME ZONE 'UTC'
            AS packet_timestamp_utc,
        TO_TIMESTAMP(q.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh'
            AS packet_timestamp_saudi,
        q.electrical_row_count,
        q.distinct_electrical_key_count,
        q.duplicate_key_rows,
        q.completely_null_rows,
        q.values_stored_outside_dbl
    FROM packet_quality AS q
    JOIN silver.dim_energy_meter_staging AS 
      ON m.energy_meter_key = q.device_id
    LEFT JOIN silver.dim_zone_staging AS z
      ON z.zone_key = m.zone_key
    WHERE q.duplicate_key_rows > 0
       OR q.completely_null_rows > 0
       OR q.values_stored_outside_dbl > 0
    ORDER BY z.zone_name, m.device_name, q.timestamp;
