-- View silver.energy_bills_tracking_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.energy_bills_tracking_landing AS
 SELECT id,
    facility_id,
    grid_billing_account_id,
    start_period,
    end_period,
    beginning_reading,
    ending_reading,
    consumption_reading,
    cost,
    comparing_with_last_bill::text COLLATE "C" AS comparing_with_last_bill,
    system_beginning_reading,
    system_endng_reading,
    system_consumption_reading,
    system_estimated_cost,
    system_reading_time,
    comparing_with_grid_bill::text COLLATE "C" AS comparing_with_grid_bill,
    created_by,
    created_on,
    invoice_number
   FROM bronze.energy_bills_tracking;
