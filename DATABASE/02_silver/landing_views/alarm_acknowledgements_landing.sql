-- View silver.alarm_acknowledgements_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_acknowledgements_landing AS
 SELECT id,
    alarm_configuration_id,
    device_id,
    acknowledged_until,
    "timestamp",
    acknowledged_by
   FROM bronze.alarm_acknowledgements;
