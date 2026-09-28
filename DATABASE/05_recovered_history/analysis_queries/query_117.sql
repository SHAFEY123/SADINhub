-- Recovered from PostgreSQL server log postgresql-2026-08-20_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH pf_counts AS (
        SELECT
            m.meter_label,
    
            COUNT(*) FILTER (
                WHERE t.key_id = 19
            ) AS pf1_total,
    
            COUNT(*) FILTER (
                WHERE t.key_id = 19
                  AND (t.dbl < 0.6 OR t.dbl > 1)
            ) AS pf1_critical,
    
            COUNT(*) FILTER (
                WHERE t.key_id = 36
            ) AS pf2_total,
    
            COUNT(*) FILTER (
                WHERE t.key_id = 36
                  AND (t.dbl < 0.6 OR t.dbl > 1)
            ) AS pf2_critical,
    
            COUNT(*) FILTER (
                WHERE t.key_id = 37
            ) AS pf3_total,
    
            COUNT(*) FILTER (
                WHERE t.key_id = 37
                  AND (t.dbl < 0.6 OR t.dbl > 1)
            ) AS pf3_critical
    
        FROM bronze.telemetries t
    
        JOIN silver.dim_energy_meter_staging m
            ON m.energy_meter_key = t.device_id
    
        WHERE t.key_id IN (19, 36, 37)
    
        GROUP BY m.meter_label
    ),
    
    rates AS (
        SELECT
            meter_label,
    
            pf1_total,
            pf2_total,
            pf3_total,
    
            pf1_critical::numeric / NULLIF(pf1_total, 0)
                AS pf1_critical_pct,
    
            pf2_critical::numeric / NULLIF(pf2_total, 0)
                AS pf2_critical_pct,
    
            pf3_critical::numeric / NULLIF(pf3_total, 0)
                AS pf3_critical_pct
    
        FROM pf_counts
    ),
    
    final AS (
        SELECT
            *,
    
            GREATEST(
                pf1_critical_pct,
                pf2_critical_pct,
                pf3_critical_pct
            )
            -
            LEAST(
                pf1_critical_pct,
                pf2_critical_pct,
                pf3_critical_pct
            ) AS pf_critical_spread
    
        FROM rates
    )
    
    SELECT
        meter_label,
    
        pf1_total,
        pf2_total,
        pf3_total,
    
        ROUND(pf1_critical_pct * 100, 2) AS pf1_critical_pct,
        ROUND(pf2_critical_pct * 100, 2) AS pf2_critical_pct,
        ROUND(pf3_critical_pct * 100, 2) AS pf3_critical_pct,
    
        ROUND(pf_critical_spread * 100, 2)
            AS spread_percentage_points
    
    FROM final
    
    WHERE pf_critical_spread > 0.65
    
    ORDER BY pf_critical_spread DESC;
