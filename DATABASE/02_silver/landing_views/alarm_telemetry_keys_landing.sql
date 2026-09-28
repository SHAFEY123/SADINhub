-- View silver.alarm_telemetry_keys_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_telemetry_keys_landing AS
 SELECT alarm_configuration_id,
    telemetry_key_id,
    details::jsonb AS details
   FROM bronze.alarm_telemetry_keys;
