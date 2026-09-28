-- View silver.water_grid_account_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_grid_account_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    account_number,
    meter_serial_number::text COLLATE "C" AS meter_serial_number,
    water_grid_provider_id,
    service_type_id,
    service_class_id,
    start_period,
    end_period,
    account_cycle_days,
    is_new_tariff,
    grid_account_units_count,
    created_by,
    created_on
   FROM bronze.water_grid_account;
