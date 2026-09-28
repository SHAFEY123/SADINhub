-- View silver.consumption_categories_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.consumption_categories_landing AS
 SELECT id,
    facility_id,
    name::text COLLATE "C" AS name,
    maximum_kwh,
    minimum_kwh,
    active,
    created_by,
    created_on
   FROM bronze.consumption_categories;
