-- Recovered from PostgreSQL server log postgresql-2026-08-20_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH meter_map AS (
        -- Restrict Bronze to the meters that actually exist
        -- in our analytical dataset
        SELECT DISTINCT
            em.meter_label,
            em.device_id
        FROM bronze.energy_meters em
        JOIN silver.dim_energy_meter_staging m
            ON m.meter_label = em.meter_label
    ),
    
    pf_raw AS (
        SELECT
            mm.meter_label,
            t.timestamp,
    
            MAX(t.dbl) FILTER (
                WHERE d.key = 'PF1'
            ) AS pf1,
    
            MAX(t.dbl) FILTER (
                WHERE d.key = 'PF2'
            ) AS pf2,
    
            MAX(t.dbl) FILTER (
                WHERE d.key = 'PF3'
            ) AS pf3
    
        FROM meter_map mm
    
        JOIN bronze.telemetries t
            ON t.device_id = mm.device_id
    
        JOIN bronze.telemetries_dictionaries d
            ON d.id = t.key_id
    
        WHERE d.key IN ('PF1', 'PF2', 'PF3')
    
        GROUP BY
            mm.meter_label,
            t.timestamp
    ),
    
    pf_rates AS (
        SELECT
            meter_label,
    
            COUNT(*) AS bronze_reading_rows,
    
            COUNT(*) FILTER (
                WHERE silver.classify_power_factor_v2(pf1) = 'Critical'
            )::numeric
            / NULLIF(COUNT(*), 0) AS pf1_critical_pct,
    
            COUNT(*) FILTER (
                WHERE silver.classify_power_factor_v2(pf2) = 'Critical'
            )::numeric
            / NULLIF(COUNT(*), 0) AS pf2_critical_pct,
    
            COUNT(*) FILTER (
                WHERE silver.classify_power_factor_v2(pf3) = 'Critical'
            )::numeric
            / NULLIF(COUNT(*), 0) AS pf3_critical_pct
    
        FROM pf_raw
    
        GROUP BY meter_label
    ),
    
    final AS (
        SELECT
            meter_label,
            bronze_reading_rows,
            pf1_critical_pct,
            pf2_critical_pct,
            pf3_critical_pct,
    
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
            ) AS critical_spread
    
        FROM pf_rates
    )
    
    SELECT
        meter_label,
        bronze_reading_rows,
    
        ROUND(pf1_critical_pct * 100, 2) AS pf1_critical_pct,
        ROUND(pf2_critical_pct * 100, 2) AS pf2_critical_pct,
        ROUND(pf3_critical_pct * 100, 2) AS pf3_critical_pct,
    
        ROUND(critical_spread * 100, 2) AS spread_percentage_points
    
    FROM final
    
    WHERE critical_spread > 0.65
    
    ORDER BY critical_spread DESC;
