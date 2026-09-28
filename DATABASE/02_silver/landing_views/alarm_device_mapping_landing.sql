-- View silver.alarm_device_mapping_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_device_mapping_landing AS
 SELECT alarm_configuration_id,
    device_type_id,
    device_category_id,
    alarm_level_id,
    unit_id
   FROM bronze.alarm_device_mapping;
