-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        z.zone_name,
        m.energy_meter_key,
        m.source_energy_meter_id,
        m.device_name,
        m.device_label,
        m.device_serial_number,
        m.meter_label,
        m.meter_serial_number,
        m.gateway_id,
        m.is_device_active,
        m.is_device_online,
        m.is_meter_active,
        m.mapping_status,
        b.first_reading_utc,
        b.last_reading_utc,
        b.total_tkw_reading_count,
        b.expected_gap_seconds,
        b.expected_daily_reading_count,
        b.cadence_status,
        b.cadence_baseline_is_reliable
    
    FROM silver.dim_energy_meter_staging AS m
    
    JOIN silver.dim_zone_staging AS z
        ON z.zone_key = m.zone_key
    
    LEFT JOIN silver.dq_device_cadence_staging AS b
        ON b.energy_meter_key = m.energy_meter_key
    
    WHERE z.zone_name = 'Zone 17';
