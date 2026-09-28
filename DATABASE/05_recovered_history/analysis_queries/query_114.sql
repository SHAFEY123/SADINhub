-- Recovered from PostgreSQL server log postgresql-2026-08-17_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH first_reading AS (
        SELECT DISTINCT ON (energy_meter_key)
            energy_meter_key,
            meter_label,
            reading_timestamp_utc AS first_timestamp,
            active_energy_cumulative_kwh AS first_kwh
        FROM silver.fact_energy_consumption_validated
        WHERE consumption_cleaning_status = 'KEEP'
        ORDER BY
            energy_meter_key,
            reading_timestamp_utc
    ),
    
    last_reading AS (
        SELECT DISTINCT ON (energy_meter_key)
            energy_meter_key,
            reading_timestamp_utc AS last_timestamp,
            active_energy_cumulative_kwh AS last_kwh
        FROM silver.fact_energy_consumption_validated
        WHERE consumption_cleaning_status = 'KEEP'
        ORDER BY
            energy_meter_key,
            reading_timestamp_utc DESC
    ),
    
    meter_totals AS (
        SELECT
            energy_meter_key,
            meter_label,
    
            SUM(validated_kwh_consumption)
                AS summed_validated_consumption,
    
            COUNT(*) FILTER (
                WHERE interval_quality = 'UNRESOLVED_DECREMENT'
            ) AS unresolved_decrements,
    
            COUNT(*) FILTER (
                WHERE interval_quality = 'LONG_GAP'
            ) AS long_gap_intervals
    
        FROM silver.fact_energy_consumption_validated
        GROUP BY
            energy_meter_key,
            meter_label
    )
    
    SELECT
        t.meter_label,
    
        f.first_timestamp,
        f.first_kwh,
    
        l.last_timestamp,
        l.last_kwh,
    
        ROUND(
            t.summed_validated_consumption::numeric,
            2
        ) AS summed_consumption,
    
        ROUND(
            (l.last_kwh - f.first_kwh)::numeric,
            2
        ) AS first_to_last_change,
    
        ROUND(
            (
                t.summed_validated_consumption
                - (l.last_kwh - f.first_kwh)
            )::numeric,
            2
        ) AS difference,
    
        t.unresolved_decrements,
        t.long_gap_intervals
    
    FROM meter_totals t
    
    JOIN first_reading f
        ON f.energy_meter_key = t.energy_meter_key
    
    JOIN last_reading l
        ON l.energy_meter_key = t.energy_meter_key
    
    ORDER BY
        ABS(
            t.summed_validated_consumption
            - (l.last_kwh - f.first_kwh)
        ) DESC;
