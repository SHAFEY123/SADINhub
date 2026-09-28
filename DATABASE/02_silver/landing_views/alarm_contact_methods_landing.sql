-- View silver.alarm_contact_methods_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_contact_methods_landing AS
 SELECT contact_after,
    notification_interval,
    contact_method_id,
    alarm_configuration_id
   FROM bronze.alarm_contact_methods;
