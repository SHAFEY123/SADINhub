-- View silver.units_types_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.units_types_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    description COLLATE "C" AS description,
    global_type,
    default_level,
    default_type_for_its_level,
    icon_id,
    created_on,
    created_by,
    facility_id
   FROM bronze.units_types;
