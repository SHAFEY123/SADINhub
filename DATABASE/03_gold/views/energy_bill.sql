-- View gold.energy_bill
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.energy_bill AS
 SELECT energy_bill_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    start_date_key,
    end_date_key,
    start_period,
    end_period,
    calculated_billing_days,
    invoice_number,
    beginning_reading,
    ending_reading,
    billed_consumption_kwh,
    billed_cost,
    system_beginning_reading,
    system_ending_reading,
    system_consumption_kwh,
    system_estimated_cost,
    consumption_variance_kwh,
    cost_variance,
    consumption_variance_percent,
    comparing_with_last_bill,
    comparing_with_grid_bill,
    system_reading_timestamp_utc,
    source_created_at
   FROM silver.fact_energy_bill_staging;
