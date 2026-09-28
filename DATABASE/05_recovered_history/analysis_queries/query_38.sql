-- Recovered from PostgreSQL server log postgresql-2026-07-28_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        em.device_id,
    
        d.name AS device_name,
        d.label AS device_label,
        d.active AS device_active,
        d.online AS device_online,
    
        em.meter_label AS source_meter_label,
    
        m.meter_label AS canonical_meter_label,
        z.zone_name AS canonical_zone_name,
    
        m.zone_key,
        m.facility_key,
        m.grid_billing_account_key,
    
        CASE
            WHEN m.energy_meter_key IS NULL
                THEN 'EXCLUDED_FROM_CANONICAL_ANALYSIS'
    
            WHEN em.meter_label IS DISTINCT FROM m.meter_label
                THEN 'SOURCE_AND_CANONICAL_LABEL_DIFFER'
    
            ELSE 'INCLUDED_MAPPING_MATCH'
        END AS analysis_status
    
    FROM silver.energy_meters_landing AS em
    
    LEFT JOIN silver.devices_landing AS d
        ON d.id = em.device_id
    
    LEFT JOIN silver.dim_energy_meter_staging AS m
        ON m.energy_meter_key = em.device_id
    
    LEFT JOIN silver.dim_zone_staging AS z
        ON z.zone_key = m.zone_key
    
    ORDER BY
        analysis_status,
        z.zone_name,
        em.meter_label,
        em.device_id;
