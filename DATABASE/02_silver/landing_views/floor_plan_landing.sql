-- View silver.floor_plan_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.floor_plan_landing AS
 SELECT id,
    unit_id,
    name::text COLLATE "C" AS name,
    image_proprties,
    created_by,
    created_on
   FROM bronze.floor_plan;
