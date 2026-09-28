-- View silver.mqtt_service_accounts_allowed_topics_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.mqtt_service_accounts_allowed_topics_landing AS
 SELECT id,
    mqtt_topic_id,
    access,
    active,
    mqtt_service_account_id,
    created_on,
    created_by
   FROM bronze.mqtt_service_accounts_allowed_topics;
