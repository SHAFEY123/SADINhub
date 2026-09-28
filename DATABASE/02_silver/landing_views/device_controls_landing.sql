-- View silver.device_controls_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_controls_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    device_id,
    unit_id,
    icon::text COLLATE "C" AS icon,
    icon_color::text COLLATE "C" AS icon_color,
    config,
    created_by,
    telemetry_key::text COLLATE "C" AS telemetry_key,
    description COLLATE "C" AS description
   FROM bronze.device_controls;
