-- View silver.alarm_logs_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_logs_landing AS
 SELECT details::jsonb AS details,
    alarm_configuration_id,
    log_type_id,
    device_id,
    "timestamp"
   FROM bronze.alarm_logs;
