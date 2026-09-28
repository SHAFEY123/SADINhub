-- View silver.device_sensors_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_sensors_landing AS
 SELECT device_id,
    sensor_id,
    telemetry_key::text COLLATE "C" AS telemetry_key,
    telemetry_key_id,
    control_id,
    category_name::text COLLATE "C" AS category_name,
    created_on,
    created_by
   FROM bronze.device_sensors;
