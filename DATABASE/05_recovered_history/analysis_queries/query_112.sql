-- Recovered from PostgreSQL server log postgresql-2026-08-09_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH bronze_packet_counts AS (
        SELECT device_id, COUNT(DISTINCT timestamp) AS bronze_packet_count
        FROM bronze.telemetries
        WHERE device_id IN (SELECT DISTINCT source_energy_meter_id FROM silver.fact_energy_readings_snapshot)
        GROUP BY device_id
    ),
    silver_packet_counts AS (
        SELECT source_energy_meter_id, COUNT(*) AS silver_packet_count
        FROM silver.fact_energy_readings_snapshot
        GROUP BY source_energy_meter_id
    )
    SELECT
        b.device_id,
        b.bronze_packet_count,
        s.silver_packet_count,
        (b.bronze_packet_count - s.silver_packet_count) AS diff
    FROM bronze_packet_counts b
    JOIN silver_packet_counts s ON s.source_energy_meter_id = b.device_id
    ORDER BY ABS(b.bronze_packet_count - s.silver_packet_count) DESC;
