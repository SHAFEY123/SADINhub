-- View silver.grid_billing_accounts_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.grid_billing_accounts_landing AS
 SELECT id,
    label::text COLLATE "C" AS label,
    number,
    meter_serial_number::text COLLATE "C" AS meter_serial_number,
    type_id,
    service_class_id,
    breaker_capacity,
    start_period,
    end_period,
    days,
    facility_id,
    unit_id,
    created_by,
    created_on,
    multiplication_factor
   FROM bronze.grid_billing_accounts;
