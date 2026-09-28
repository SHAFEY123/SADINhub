-- View silver.devices_types_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.devices_types_landing AS
 SELECT id,
    category_id,
    name::text COLLATE "C" AS name,
    config_preset::jsonb AS config_preset,
    created_on,
    created_by,
    code,
    description COLLATE "C" AS description,
    icon::text COLLATE "C" AS icon,
    properties
   FROM bronze.devices_types;
