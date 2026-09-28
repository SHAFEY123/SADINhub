-- View silver.alarms_severities_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.alarms_severities_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    active,
    icon::text COLLATE "C" AS icon,
    hex_color::text COLLATE "C" AS hex_color,
    default_configs::jsonb AS default_configs,
    created_on,
    created_by
   FROM bronze.alarms_severities;
