-- View silver.water_grid_account_service_type_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_grid_account_service_type_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    c_base,
    s1,
    s2,
    s3,
    s4,
    s5,
    water_grid_provider_id,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_type;
