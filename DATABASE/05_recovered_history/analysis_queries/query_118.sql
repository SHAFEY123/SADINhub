-- Recovered from PostgreSQL server log postgresql-2026-09-02_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        interval_quality,
        COUNT(*) AS interval_count,
        ROUND(SUM(validated_kwh_consumption)::numeric, 2) AS consumption_kwh
    FROM silver.fact_energy_consumption_validated
    WHERE meter_label = 'ZN.17-PB_child__1_ch3pm'
      AND validated_kwh_consumption IS NOT NULL
    GROUP BY interval_quality
    ORDER BY consumption_kwh DESCSELECT
        reading_timestamp_utc,
        gap_minutes,
        previous_valid_kwh,
        active_energy_cumulative_kwh,
        validated_kwh_consumption,
        interval_quality
    FROM silver.fact_energy_consumption_validated
    WHERE meter_label = 'ZN.17-PB_child__1_ch3pm'
      AND interval_quality = 'LONG_GAP'
    ORDER BY validated_kwh_consumption DESC;
