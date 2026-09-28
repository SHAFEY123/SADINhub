-- View silver.alarm_levels_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarm_levels_landing AS
 SELECT id,
    title::text COLLATE "C" AS title,
    description::text COLLATE "C" AS description
   FROM bronze.alarm_levels;
