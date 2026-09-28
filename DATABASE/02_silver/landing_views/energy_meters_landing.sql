-- View silver.energy_meters_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.energy_meters_landing AS
 SELECT id,
    facility_id,
    grid_billing_account_id,
    device_id,
    phase,
    parent_id,
    maximum_kwh,
    type_id,
    unit_id,
    active,
    created_by,
    created_on,
    meter_sn::text COLLATE "C" AS meter_sn,
    meter_label::text COLLATE "C" AS meter_label
   FROM bronze.energy_meters;
