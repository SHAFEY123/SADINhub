-- View silver.water_grid_account_service_class_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_grid_account_service_class_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    minimal_meter_diameter,
    maximum_meter_diameter,
    fee,
    active,
    water_grid_provider_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_class;
