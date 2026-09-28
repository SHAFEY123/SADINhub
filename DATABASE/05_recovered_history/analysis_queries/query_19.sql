-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        zone_name,
        device_name,
        meter_label,
        reading_date,
        expected_gap_seconds,
        expected_daily_reading_count,
        actual_reading_count,
        actual_reading_count - expected_daily_reading_count
            AS extra_reading_count,
        (
            actual_reading_count::numeric
            / NULLIF(expected_daily_reading_count, 0)
        ) * 100 AS raw_completeness_percent,
        large_gap_count,
        maximum_within_day_gap_seconds,
        daily_quality_status,
        severity
    FROM silver.dq_meter_daily_completeness_staging
    WHERE reading_date = selected_random_date
      AND actual_reading_count >
          expected_daily_reading_count + 2
    ORDER BY
        (
            actual_reading_count::numeric
            / NULLIF(expected_daily_reading_count, 0)
        ) DESC,
        zone_name,
        device_name;
