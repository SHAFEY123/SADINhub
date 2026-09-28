-- bronze.check_sensor_in_device_sensors()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.check_sensor_in_device_sensors()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1 FROM device_sensors
        WHERE device_sensors.sensor_id = NEW.water_sensor_id
    ) THEN
        RAISE EXCEPTION 'Sensor % already has a relation in DeviceSenor',NEW.water_sensor_id;
    END IF;
    RETURN NEW;
END;
$function$
