-- Recovered from PostgreSQL server log postgresql-2026-07-29_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH base AS (
        SELECT
            f.*,
    
            CASE
                WHEN
                    COALESCE(ABS(f.voltage_line_1_v), 0) = 0
                    AND COALESCE(ABS(f.voltage_line_2_v), 0) = 0
                    AND COALESCE(ABS(f.voltage_line_3_v), 0) = 0
    
                    AND COALESCE(ABS(f.current_phase_1_a), 0) = 0
                    AND COALESCE(ABS(f.current_phase_2_a), 0) = 0
                    AND COALESCE(ABS(f.current_phase_3_a), 0) = 0
    
                    AND COALESCE(ABS(f.frequency_hz), 0) = 0
    
                    AND COALESCE(ABS(f.power_factor_phase_1), 0) = 0
                    AND COALESCE(ABS(f.power_factor_phase_2), 0) = 0
                    AND COALESCE(ABS(f.power_factor_phase_3), 0) = 0
    
                    AND COALESCE(ABS(f.active_power_phase_1_kw), 0) = 0
                    AND COALESCE(ABS(f.active_power_phase_2_kw), 0) = 0
                    AND COALESCE(ABS(f.active_power_phase_3_kw), 0) = 0
                    AND COALESCE(ABS(f.active_power_total_kw), 0) = 0
    
                    AND COALESCE(
                        ABS(f.active_energy_cumulative_kwh),
                        0
                    ) = 0
    
                THEN 'EMPTY_OR_ALL_ZERO'
                ELSE 'USABLE'
            END AS gold_row_status
    
        FROM silver.fact_energy_readings_staging AS f
    
        WHERE f.reading_date_saudi = DATE '2025-04-16'
    )
    
    SELECT
        gold_row_status,
        COUNT(*) AS reading_count
    FROM base
    GROUP BY gold_row_status
    ORDER BY gold_row_status;
