-- Recovered from PostgreSQL server log postgresql-2026-07-23_103051.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        f.name AS facility_name,
        u.name AS zone_name,
    
        em.id AS energy_meter_id,
        em.meter_label,
        em.meter_sn,
        em.phase,
    
        d.id AS device_id,
        d.name AS device_name,
        d.serial_number AS device_serial_number,
    
        COUNT(*) OVER (
            PARTITION BY em.device_id
        ) AS meter_records_using_same_device,
    
        COUNT(*) OVER (
            PARTITION BY em.meter_label
        ) AS records_using_same_meter_label
    
    FROM bronze.energy_meters em
    
    JOIN bronze.device d
        ON d.id = em.device_id
    
    LEFT JOIN bronze.units u
        ON u.id = em.unit_id
    
    LEFT JOIN brone.facilities f
        ON f.id = em.facility_id
    
    ORDER BY
        u.name,
        em.meter_label,
        d.name;
