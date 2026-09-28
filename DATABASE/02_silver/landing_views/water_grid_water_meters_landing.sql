-- View silver.water_grid_water_meters_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_grid_water_meters_landing AS
 SELECT water_grid_account_id,
    water_meter_id,
    created_on,
    created_by,
    grid_account_main_meter
   FROM bronze.water_grid_water_meters;
