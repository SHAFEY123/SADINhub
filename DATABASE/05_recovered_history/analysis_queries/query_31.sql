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
    packets AS (
        SELECT
            t.device_id,
            t.timestamp,
            MAX(t.dbl) FILTER (WHERE td.key = 'kW1') AS kw1,
            MAX(t.dbl) FILTER (WHERE td.key = 'kW2') AS kw2,
            MAX(t.dbl) FILTER (WHERE td.key = 'kW3') AS kw3,
            MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw
        FROM silver.telemetries AS t
        JOIN params AS p
          ON t.timestamp >= p.start_ms
         AND t.timestamp < p.end_ms
        JOIN silver.telemetries_dictionaries AS td
          ON td.id = t.key_id
        JOIN silver.dim_energy_meter_staging AS m
          ON m.energy_meter_key = t.device_id
        WHERE td.key IN ('kW1','kW2','kW3','TkW')
        GROUP BY t.device_id, t.timestamp
    ),
    calculated AS (
        SELECT
            p.*,
            COALESCE(p.kw1, 0)
            + COALESCE(p.kw2, 0)
            + COALESCE(p.kw3, 0) AS phase_kw_sum
        FROM packets AS p
    )
    SELECT
        z.zone_name,
        m.device_name,
        m.meter_label,
        TO_TIMESTAMP(c.timestamp / 1000.0) AT TIME ZONE 'UTC'
            AS reading_timestamp_utc,
        TO_TIMESTAMP(c.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh'
            AS reading_timestamp_saudi,
        c.kw1,
        c.kw2,
        c.kw3,
        c.phase_kw_sum,
        c.total_kw,
        c.total_kw - c.phase_kw_sum AS signed_difference_kw,
        ABS(c.total_kw - c.phase_kw_sum) AS absolute_difference_kw,
        ROUND(
            (
                ABS(c.total_kw - c.phase_kw_sum)::numeric
                / NULLIF(ABS(c.total_kw)::numeric, 0)
            ) * 100,
            3
        ) AS difference_percent_of_total
    FROM calculated AS c
    JOIN silver.dim_energy_meter_staging AS m
      ON m.energy_meter_key = c.device_id
    LEFT JOIN silver.dim_zone_staging AS z
      ON z.zone_key = m.zone_key
    WHERE c.total_kw IS NOT NULL
    ORDER BY ABS(c.total_kw - c.phase_kw_sum) DESC
    LIMIT 500;
