-- View silver.alarm_device_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_device_landing AS
 SELECT device_id,
    alarm_level_id,
    alarm_configuration_id,
    active
   FROM bronze.alarm_device;
