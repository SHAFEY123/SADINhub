-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH one_meter_one_week AS (
        SELECT
            energy_meter_id,
            reading_timestamp_utc,
            kwh
        FROM silver.fact_energy_readings_staging
        WHERE energy_meter_id = 1
          AND reading_timestamp_utc >= '2026-07-01'
          AND reading_timestamp_utc <  '2026-07-08'
    ),
    deltas AS (
        SELECT
            kwh - LAG(kwh) OVER (ORDER BY reading_timestamp_utc) AS kwh_delta
        FROM one_meter_one_week
    )
    SELECT
        COUNT(*) FILTER (WHERE kwh_delta < 0)  AS negative_deltas,
        COUNT(*) FILTER (WHERE kwh_delta = 0)  AS zero_deltas,
        COUNT(*) FILTER (WHERE kwh_delta > 0)  AS positive_deltas,
        COUNT(*) FILTER (WHERE kwh_delta IS NULL) AS null_deltas
    FROM deltas;
