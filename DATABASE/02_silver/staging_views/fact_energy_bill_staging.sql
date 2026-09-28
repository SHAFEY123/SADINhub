-- View silver.fact_energy_bill_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.fact_energy_bill_staging AS
 SELECT bill.id AS energy_bill_key,
    bill.facility_id AS facility_key,
    account.zone_key,
    bill.grid_billing_account_id AS grid_billing_account_key,
    to_char((bill.start_period AT TIME ZONE 'UTC'::text), 'YYYYMMDD'::text)::integer AS start_date_key,
    to_char((bill.end_period AT TIME ZONE 'UTC'::text), 'YYYYMMDD'::text)::integer AS end_date_key,
    bill.start_period,
    bill.end_period,
    bill.end_period::date - bill.start_period::date AS calculated_billing_days,
    bill.invoice_number::text COLLATE "C" AS invoice_number,
    bill.beginning_reading,
    bill.ending_reading,
    bill.consumption_reading AS billed_consumption_kwh,
    bill.cost AS billed_cost,
    bill.system_beginning_reading,
    bill.system_endng_reading AS system_ending_reading,
    bill.system_consumption_reading AS system_consumption_kwh,
    bill.system_estimated_cost,
    bill.system_consumption_reading - bill.consumption_reading AS consumption_variance_kwh,
    bill.system_estimated_cost - bill.cost AS cost_variance,
    (bill.system_consumption_reading - bill.consumption_reading) / NULLIF(bill.consumption_reading, 0::numeric) * 100::numeric AS consumption_variance_percent,
    bill.comparing_with_last_bill,
    bill.comparing_with_grid_bill,
        CASE
            WHEN bill.system_reading_time IS NULL THEN NULL::timestamp without time zone
            ELSE (to_timestamp((bill.system_reading_time::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)
        END AS system_reading_timestamp_utc,
    bill.created_on AS source_created_at
   FROM silver.energy_bills_tracking_landing bill
     LEFT JOIN silver.dim_grid_billing_account_staging account ON account.grid_billing_account_key = bill.grid_billing_account_id;
