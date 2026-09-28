-- View gold.billing_account
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.billing_account AS
 SELECT grid_billing_account_key,
    facility_key,
    zone_key,
    account_label,
    account_number,
    meter_serial_number,
    account_type_key,
    account_type_name,
    service_class_key,
    service_class_name,
    breaker_capacity,
    minimal_breaker_capacity,
    maximum_breaker_capacity,
    service_class_fee,
    multiplication_factor,
    start_period,
    end_period,
    configured_billing_days,
    source_created_at
   FROM silver.dim_grid_billing_account_staging;
