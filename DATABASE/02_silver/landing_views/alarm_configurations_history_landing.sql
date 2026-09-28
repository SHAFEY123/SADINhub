-- View silver.alarm_configurations_history_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_configurations_history_landing AS
 SELECT id,
    payload::jsonb AS payload,
    alarm_configuration_id,
    created_by,
    updated_by,
    updated_at
   FROM bronze.alarm_configurations_history;
