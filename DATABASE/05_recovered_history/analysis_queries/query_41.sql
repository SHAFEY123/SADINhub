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
    
    packets AS (
        SELECT
            t.device_id,
            t.timestamp,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'PF1'
            ) AS pf1,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'PF2'
            ) AS pf2,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'PF3'
            ) AS pf3,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'PFa'
            ) AS pfa,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'TkW'
            ) AS total_kw,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'Amp1'
            ) AS amp1,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'Amp2'
            ) AS amp2,
    
            MAX(t.dbl) FILTER (
                WHERE td.key = 'Amp3'
            ) AS amp3
    
        FROM bronze.telemetries AS t
    
        CROSS JOIN params AS p
    
        JOIN bronze.telemetries_dictionaries AS td
          ON td.id = t.key_id
    
        JOIN silver.dim_energy_meter_staging AS m
          ON m.energy_meter_key = t.device_id
    
        JOIN silver.dim_zone_staging AS z
          ON z.zone_key = m.zone_key
    
        WHERE t.timestamp >= p.start_ms
          AND t.timestamp < p.end_ms
    
          AND td.key IN (
              'PF1',
              'PF2',
              'PF3',
              'PFa',
              'TkW',
              'Amp1',
              'Amp2',
              'Amp3'
          )
    
          AND z.zone_name ~ '^Zone (0[1-9]|1[0-9]|2[0-1])$'
    
        GROUP BY
            t.device_id,
            t.timestamp
    ),
    
    calculated AS (
        SELECT
            p.*,
    
            (
                COALESCE(p.pf1, 0)
                + COALESCE(p.pf2, 0)
                + COALESCE(p.pf3, 0)
            ) / NULLIF(
                (p.pf1 IS NOT NULL)::integer
                + (p.pf2 IS NOT NULL)::integer
                + (p.pf3 IS NOT NULL)::integer,
                0
            ) AS arithmetic_phase_pf_average,
    
            (
                COALESCE(p.amp1, 0)
                + COALESCE(p.amp2, 0)
                + COALESCE(p.amp3, 0)
            ) / NULLIF(
                (p.amp1 IS NOT NULL)::integer
                + (p.amp2 IS NOT NULL)::integer
                + (p.amp3 IS NOT NULL)::integer,
                0
            ) AS average_current_a
    
        FROM packets AS p
    )
    
    SELECT
        z.zone_name,
        m.device_name,
        m.meter_label,
    
        TO_TIMESTAMP(c.timestamp / 1000.0)
            AT TIME ZONE 'Asia/Riyadh'
            AS reading_timestamp_saudi,
    
        /* Power-factor readings */
        c.pf1,
        c.pf2,
        c.pf3,
        c.pfa,
    
        /* Current readings */
        c.amp1,
        c.amp2,
        c.amp3,
        c.average_current_a,
    
        /* PF comparison */
        c.arithmetic_phase_pf_average,
    
        c.pfa - c.arithmetic_phase_pf_average
            AS pfa_minus_arithmetic_average,
    
        c.total_kw,
    
        CASE
            WHEN ABS(COALESCE(c.total_kw, 0)) < 0.5
              OR COALESCE(c.average_current_a, 0) < 1.0
            THEN 'LOW_LOAD_PF_REVIEW'
    
            WHEN ABS(
                c.pfa - c.arithmetic_phase_pf_average
            ) > 0.10
            THEN 'PFA_DEFINITION_REVIEW'
    
            ELSE 'WITHIN_EXPLORATORY_TOLERANCE'
        END AS review_status
    
    FROM calculated AS c
    
    JOIN silver.dim_energy_meter_staging AS m
      ON m.energy_meter_key = c.device_id
    
    JOIN silver.dim_zone_staging AS z
      ON z.zone_key = m.zone_key
    
    WHERE c.pfa IS NOT NULL
    
      AND z.zone_name ~ '^Zone (0[1-9]|1[0-9]|2[0-1])$'
    
      AND (
          ABS(COALESCE(c.total_kw, 0)) < 0.5
          OR COALESCE(c.average_current_a, 0) < 1.0
          OR ABS(
              c.pfa - c.arithmetic_phase_pf_average
          ) > 0.10
      )
    
    ORDER BY
        REGEXP_REPLACE(
            z.zone_name,
            '[^0-9]',
            '',
            'g'
        )::integer,
    
        m.meter_label,
    
        ABS(
            c.pfa - c.arithmetic_phase_pf_average
        ) c.pfa,
    
        c.timestamp
    
    LIMIT 1000;
