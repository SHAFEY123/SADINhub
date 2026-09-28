-- View silver.roles_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.roles_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    description COLLATE "C" AS description,
    global_role,
    icon::text COLLATE "C" AS icon,
    icon_color::text COLLATE "C" AS icon_color,
    active,
    created_on,
    created_by,
    facility_id
   FROM bronze.roles;
