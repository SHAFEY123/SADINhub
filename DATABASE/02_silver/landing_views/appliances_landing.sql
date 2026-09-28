-- View silver.appliances_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.appliances_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    category_id,
    unit_id,
    meter_id,
    facility_id,
    created_on,
    created_by
   FROM bronze.appliances;
