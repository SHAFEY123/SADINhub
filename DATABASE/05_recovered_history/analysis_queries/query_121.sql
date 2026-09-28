-- Recovered from PostgreSQL server log postgresql-2026-09-04_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- Sign mismatch between Power Factor and Active Power, per phase
    --
    -- Electrically, PF and active power should carry the same sign
    -- on a given phase (both flip together if current-transformer
    -- polarity is reversed). A mismatch -- one negative, the other
    -- not, on the same phase, same reading -- is a genuine
    -- inconsistency worth investigating.
    -- ============================================================
    
    WITH mismatches AS (
        SELECT
            e.reading_timestamp_utc,
            m.meter_label,
            1 AS phase,
            e.power_factor_phase_1 AS pf,
            e.active_power_phase_1_kw AS active_power_kw
        FROM gold.energy_raw e
        LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
        WHERE (e.power_factor_phase_1 < 0 AND e.active_power_phase_1_kw >= 0)
           OR (e.power_factor_phase_1 >= 0 AND e.active_power_phase_1_kw < 0)
    
        UNION ALL
    
        SELECT
            e.reading_timestamp_utc,
            m.meter_label,
            2 AS phase,
            e.power_factor_phase_2,
            e.active_power_phase_2_kw
        FROM gold.energy_raw e
        LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
        WHERE (e.power_factor_phase_2 < 0 AND e.active_power_phase_2_kw >= 0)
           OR (e.power_factor_phase_2 >= 0 AND e.active_power_phase_2_kw < 0)
    
        UNION ALL
    
        SELECT
            e.reading_timestamp_utc,
            m.meter_label,
            3 AS phase,
            e.power_factor_phase_3,
            e.active_power_phase_3_kw
        FROM gold.energy_raw e
        LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
        WHERE (e.power_factor_phase_3 < 0 AND e.active_power_phase_3_kw >= 0)
           OR (e.power_factor_phase_3 >= 0 AND e.active_power_phase_3_kw < 0)
    )
    
    -- Summary: how many mismatches per meter, per phase
    SELECT meter_label, phase, COUNT(*) AS mismatch_count
    FROM mismatches
    GROUP BY meter_label, phase
    ORDER BY mismatch_count DESC;
    
    -- Detail (comment the summary above out and use this instead if
    -- you want the actual rows, not just counts):
    -- SELECT * FROM mismatches ORDER BY meter_label, phase, reading_timestamp_utc;
