-- View silver.overlays_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.overlays_landing AS
 SELECT id,
    unit_id,
    floor_plan_id,
    name::text COLLATE "C" AS name,
    shape_config,
    created_by,
    created_on
   FROM bronze.overlays;
