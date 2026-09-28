-- Recovered from PostgreSQL server log postgresql-2026-07-28_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH params AS (
        SELECT
            'a0396787-f0f9-4037-a5cd-232c3b6e0000'::uuid
                AS selected_meter,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        TIMESTAMP '2025-03-01 00:00:00'
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS start_ms,
    
            (
                EXTRACT(
                    EPOCH FROM (
                        TIMESTAMP '2025-03-01 01:00:00'
                        AT TIME ZONE 'Asia/Riyadh'
                    )
                ) * 1000
            )::bigint AS end_ms
    ),
    
    base AS (
        SELECT
            f.energy_meter_key,
            f.reading_timestamp_saudi,
    
            f.current_phase_1_a,
            f.current_phase_2_a,
            f.current_phase_3_a,
    
            (
                f.current_phase_1_a
                + f.current_phase_2_a
                + f.current_phase_3_a
            ) / 3.0 AS calculated_current_average_a
    
        FROM silver.fact_energy_readings_staging AS f
        CROSS JOIN params AS p
    
        WHERE f.energy_meter_key = p.selected_meter
          AND f.source_timestamp_ms >= p.start_ms
          AND f.source_timestamp_ms < p.end_ms
    
          AND f.current_phase_1_a IS NOT NULL
          AND f.current_phase_2_a IS NOT NULL
          AND f.current_phase_3_a IS NOT NULL
    )
    
    SELECT
        energy_meter_key,
        reading_timestamp_saudi,
    
        current_phase_1_a,
        current_phase_2_a,
        current_phase_3_a,
    
        ROUND(
            calculated_current_average_a::numeric,
            2
        ) AS calculated_current_average_a,
    
        ROUND(
            (
                GREATEST(
                    current_phase_1_a,
                    current_phase_2_a,
                    current_phase_3_a
                )
                -
                LEAST(
                    current_phase_1_a,
                    current_phase_2_a,
                    current_phase_3_a
                )
            )::numeric,
            2
        ) AS current_phase_spread_a,
    
        CASE
            WHEN ABS(calculated_current_average_a) > 0.1
            THEN ROUND(
                (
                    100.0
                    *
                    GREATEST(
                        ABS(
                            current_phase_1_a
                            - calculated_current_average_a
                        ),
                        ABS(
                            current_phase_2_a
                            - calculated_current_average_a
                        ),
                        ABS(
                            current_phase_3_a
                            - calculated_current_average_a
                        )
                    )
                    /
                    ABS(calculated_current_average_a)
                )::numeric,
                2
            )
        END AS current_imbalance_"%"
    
    FROM base
    
    ORDER BY reading_timestamp_saudi;
