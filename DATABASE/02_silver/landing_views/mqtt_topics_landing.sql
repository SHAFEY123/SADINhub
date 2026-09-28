-- View silver.mqtt_topics_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.mqtt_topics_landing AS
 SELECT id,
    topic::text COLLATE "C" AS topic,
    regex::text COLLATE "C" AS regex,
    active,
    created_on,
    facility_id
   FROM bronze.mqtt_topics;
