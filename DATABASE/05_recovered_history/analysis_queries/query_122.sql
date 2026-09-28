-- Recovered from PostgreSQL server log postgresql-2026-09-07_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH recovered AS (
                WITH base AS (
            SELECT
                s.energy_meter_key,
                s.source_energy_meter_id,
                s.facility_key,
                s.zone_key,
                s.grid_billing_account_key,
                s.source_timestamp_ms,
                s.reading_timestamp_utc,
                s.reading_timestamp_saudi,
                s.reading_date_saudi,
        
                s.active_energy_cumulative_kwh,
        
                f.status_kwh,
                m.meter_label
        
            FROM silver.fact_energy_readings_staging s
        
            LEFT JOIN silver.fact_energy_readings_flagged f
                ON f.energy_meter_key = s.energy_meter_key
               AND f.source_timestamp_ms = s.source_timestamp_ms
        
            LEFT JOIN silver.dim_energy_meter_staging m
                ON m.energy_meter_key = s.energy_meter_key
        ),
        
        /* Get surrounding cumulative kWh readings */
        ordered AS (
            SELECT
                *,
        
                LAG(active_energy_cumulative_kwh, 1) OVER (
                    PARTITION BY energy_meter_key
                    ORDER BY reading_timestamp_utc
                ) AS raw_previous_kwh,
        
                LAG(active_energy_cumulative_kwh, 2) OVER (
                    PARTITION BY energy_meter_key
                    ORDER BY reading_timestamp_utc
                ) AS raw_previous_2_kwh,
        
                LEAD(active_energy_cumulative_kwh, 1) OVER (
                    PARTITION BY energy_meter_key
                    ORDER BY reading_timestamp_utc
                ) AS raw_next_kwh
        
            FROM base
        ),
        
        /* Apply the consumption cleaning rules */
        classified AS (
            SELECT
                *,
        
                CASE
        
                    /* -----------------------------------------
                       Zone 13:
                       completely excluded from consumption
                       ----------------------------------------- */
                    WHEN meter_label LIKE 'ZN.13-%'
                    THEN 'EXCLUDED_ZONE13'
        
        
                    WHEN active_energy_cumulative_kwh IS NULL
                    THEN 'MISSING_KWH'
        
        
                    /* -----------------------------------------
                       ZN.1-PB.1 installation/startup readings
        
                       Valid sequence begins at 46.5
                       ----------------------------------------- */
                    WHEN meter_label = 'ZN.1-PB.1_child__1_ch3pm'
                         AND reading_timestamp_utc <
                             TIMESTAMP '2024-12-10 17:16:15.655'
                    THEN 'STARTUP_EXCLUDED'
        
        
                    WHEN meter_label = 'ZN.1-PB.1_child__1_ch3pm'
                         AND reading_timestamp_utc =
                             TIMESTAMP '2024-12-10 17:16:15.655'
                    THEN 'STARTUP_BASELINE'
        
        
                    /* -----------------------------------------
                       ZN.4-PB.1 installation/startup readings
        
                       Valid sequence begins at 150.4
                       ----------------------------------------- */
                    WHEN meter_label = 'ZN.4-PB.1_child__1_ch3pm'
                         AND reading_timestamp_utc <
                             TIMESTAMP '2024-12-10 21:46:39.010'
                    THEN 'STARTUP_EXCLUDED'
        
        
                    WHEN meter_label = 'ZN.4-PB.1_child__1_ch3pm'
                         AND reading_timestamp_utc =
                             TIMESTAMP '2024-12-10 21:46:39.010'
                    THEN 'STARTUP_BASELINE'
        
        
                    /* -----------------------------------------
                       Single isolated LOW reading
        
                       1218.4 -> 30.5 -> 1218.8
        
                       30.5 is ignored
                       ----------------------------------------- */
                    WHEN raw_previous_kwh IS NOT NULL
                         AND raw_next_kwh IS NOT NULL
                         AND active_energy_cumulative_kwh < raw_previous_kwh
                         AND raw_next_kwh >= raw_previous_kwh
        
                    THEN 'ISOLATED_LOW_BAD'
        
        
                    /* -----------------------------------------
                       Single isolated HIGH spike
        
                       35272.4 -> 94894 -> 35272.8
        
                       94894 is ignored
                       ----------------------------------------- */
                    WHEN raw_previous_kwh IS NOT NULL
                         AND raw_next_kwh IS NOT NULL
                         AND active_energy_cumulative_kwh > raw_previous_kwh
                         AND active_energy_cumulative_kwh > raw_next_kwh
                         AND raw_next_kwh >= raw_previous_kwh
        
                    THEN 'ISOLATED_HIGH_BAD'
        
        
                    /* -----------------------------------------
                       Recovery after isolated high spike
        
                       35272.4 -> 94894 -> 35272.8
        
                       35272.8 is a valid recovery reading
                       ----------------------------------------- */
                    WHEN raw_previous_2_kwh IS NOT NULL
                         AND raw_previous_kwh IS NOT NULL
                         AND raw_previous_kwh > raw_previous_2_kwh
                         AND raw_previous_kwh > active_energy_cumulative_kwh
                         AND active_energy_cumulative_kwh >= raw_previous_2_kwh
        
                    THEN 'HIGH_SPIKE_RECOVERY'
        
        
                    /* Any decrement we haven't explained */
                    WHEN raw_previous_kwh IS NOT NULL
                         AND active_energy_cumulative_kwh < raw_previous_kwh
        
                    THEN 'UNRESOLVED_DECREMENT'
        
        
                    /* Normal increase or flat reading */
                    ELSE 'KEEP'
        
                END AS consumption_cleaning_status
        
            FROM ordered
        ),
        
        /* Determine whether each meter can be used */
        meter_status AS (
            SELECT
                *,
        
                CASE
        
                    WHEN meter_label LIKE 'ZN.13-%'
                    THEN 'EXCLUDED'
        
                    WHEN MAX(
                        CASE
                            WHEN consumption_cleaning_status =
                                 'UNRESOLVED_DECREMENT'
                            THEN 1
                            ELSE 0
                        END
                    ) OVER (
                        PARTITION BY energy_meter_key
                    ) = 1
                    THEN 'REVIEW_REQUIRED'
        
                    ELSE 'ELIGIBLE'
        
                END AS meter_consumption_status
        
            FROM classified
        ),
        
        /* Keep only trustworthy readings for the consumption sequence */
        valid_sequence AS (
            SELECT
                energy_meter_key,
                reading_timestamp_utc,
                active_energy_cumulative_kwh
        
            FROM meter_status
        
            WHERE meter_consumption_status = 'ELIGIBLE'
        
              AND consumption_cleaning_status IN (
                  'KEEP',
                  'STARTUP_BASELINE',
                  'HIGH_SPIKE_RECOVERY'
              )
        ),
        
        /* Find previous VALID reading instead of previous raw reading */
        previous_valid AS (
            SELECT
                energy_meter_key,
                reading_timestamp_utc,
                active_energy_cumulative_kwh,
        
                LAG(reading_timestamp_utc) OVER (
                    PARTITION BY energy_meter_key
                    ORDER BY reading_timestamp_utc
                ) AS previous_valid_timestamp,
        
                LAG(active_energy_cumulative_kwh) OVER (
                    PARTITION BY energy_meter_key
                    ORDER BY reading_timestamp_utc
                ) AS previous_valid_kwh
        
            FROM valid_sequence
        ),
        
        /* Calculate actual validated consumption */
        calculated AS (
            SELECT
                *,
        
                CASE
                    WHEN previous_valid_kwh IS NULL
                    THEN NULL
        
                    WHEN active_energy_cumulative_kwh >= previous_valid_kwh
                    THEN active_energy_cumulative_kwh - previous_valid_kwh
        
                    ELSE NULL
                END AS validated_kwh_consumption,
        
                EXTRACT(
                    EPOCH FROM (
                        reading_timestamp_utc - previous_valid_timestamp
                    )
                ) / 60.0 AS gap_minutes
        
            FROM previous_valid
        )
        
        SELECT
            c.energy_meter_key,
            c.source_energy_meter_id,
            c.facility_key,
            c.zone_key,
            c.grid_billing_account_key,
        
            c.meter_label,
        
            c.source_timestamp_ms,
            c.reading_timestamp_utc,
            c.reading_timestamp_saudi,
            c.reading_date_saudi,
        
            /* Original cumulative meter value */
            c.active_energy_cumulative_kwh,
        
            c.status_kwh,
        
            /* Raw surrounding readings for validation */
            c.raw_previous_kwh,
            c.raw_next_kwh,
        
            /* Why a reading was kept/ignored */
            c.consumption_cleaning_status,
        
            /* Whether this meter contributes to consumption */
            c.meter_consumption_status,
        
            /* Previous trustworthy meter reading */
            v.previous_valid_timestamp,
            v.previous_valid_kwh,
        
            /* VALUE WE WILL USE FOR CONSUMPTION */
            v.validated_kwh_consumption,
        
            ROUND(v.gap_minutes::numeric, 2) AS gap_minutes,
        
            CASE
                WHEN c.meter_consumption_status = 'EXCLUDED'
                THEN 'EXCLUDED_METER'
        
                WHEN c.meter_consumption_status = 'REVIEW_REQUIRED'
                THEN 'REVIEW_REQUIRED'
        
                WHEN c.consumption_cleaning_status IN (
                    'ISOLATED_LOW_BAD',
                    'ISOLATED_HIGH_BAD',
                    'STARTUP_EXCLUDED',
                    'MISSING_KWH'
                )
                THEN 'IGNORED_READING'
        
                WHEN v.previous_valid_timestamp IS NULL
                THEN 'FIRST_VALID_READING'
        
                /* Gap is allowed when cumulative counter increases */
                WHEN v.gap_minutes >= 15
                THEN 'LONG_GAP'
        
                ELSE 'NORMAL_INTERVAL'
        
            END AS interval_quality
        
        FROM meter_status c
        
        LEFT JOIN calculated v
            ON v.energy_meter_key = c.energy_meter_key
           AND v.reading_timestamp_utc = c.reading_timestamp_utc
                )
                SELECT * FROM recovered
                WHERE energy_meter_key = ANY($1)
