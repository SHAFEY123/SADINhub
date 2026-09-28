-- Recovered from PostgreSQL server log postgresql-2026-08-20_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH mismatch AS (
        SELECT
            energy_meter_key,
            meter_label,
    
            COUNT(*) FILTER (
                WHERE status_amp1 IN ('Major Issue', 'Major Problem')
            ) AS phase_1_mismatch,
    
            COUNT(*) FILTER (
                WHERE status_amp2 IN ('Major Issue', 'Major Problem')
            ) AS phase_2_mismatch,
    
            COUNT(*) FILTER (
                WHERE status_amp3 IN ('Major Issue', 'Major Problem')
            ) AS phase_3_mismatch
    
        FROM gold.energy_raw
    
        GROUP BY
            energy_meter_key,
            meter_label
    )
    
    SELECT
        meter_label,
        phase_1_mismatch,
        phase_2_mismatch,
        phase_3_mismatch,
    
        phase_1_mismatch
        + phase_2_mismatch
        + phase_3_mismatch AS total_mismatch_events
    
    FROM mismatch
    
    WHERE GREATEST(
        phase_1_mismatch,
        phase_2_mismatch,
        phase_3_mismatch
    ) > 100
    
    ORDER BY total_mismatch_events DESC;
