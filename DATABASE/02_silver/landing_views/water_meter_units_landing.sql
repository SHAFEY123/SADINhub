-- View silver.water_meter_units_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_meter_units_landing AS
 SELECT water_meter_id,
    unit_id,
    created_on,
    created_by,
    unit_main_meter
   FROM bronze.water_meter_units;
