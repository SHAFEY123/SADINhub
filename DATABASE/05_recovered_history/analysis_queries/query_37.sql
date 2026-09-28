-- Recovered from PostgreSQL server log postgresql-2026-07-28_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        z.zone_name,
    
        m.energy_meter_key AS device_id,
        d.name AS device_name,
        d.label AS device_label,
        d.active AS device_active,
        d.online AS device_online,
    
        em.meter_label AS source_meter_label,
        m.meter_label AS canonical_meter_label,
    
        m.source_energy_meter_id,
        m.facility_key,
        m.zone_key,
        m.grid_billing_account_key,
    
        CASE
            WHEN em.device_id IS NULL
                THEN 'SOURCE_METER_RECORD_NOT_FOUND'
    
            WHEN em.meter_label IS DISTINCT FROM m.meter_label
                THEN 'SOURCE_AND_CANONICAL_LABEL_DIFFER'
    
            ELSE 'MAPPING_MATCH'
        END AS mapping_status
    
    FROM silver.dim_energy_meter_staging AS m
    
    LEFT JOIN silver.dim_zone_staging AS z
        ON z.zone_key = m.zone_key
    
    LEFT JOIN silver.devices_landing AS d
        ON d.id = m.energy_meter_key
    
    LEFT JOIN silver.energy_meters_landing AS em
        ON em.device_id = m.energy_meter_key
    
    ORDER BY
        z.zone_name,
        m.meter_label,
        m.energy_meter_key;
