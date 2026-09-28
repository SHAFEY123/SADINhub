-- View gold.energy_consumption_validated
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.energy_consumption_validated AS
 SELECT energy_meter_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    meter_label,
    reading_timestamp_utc,
    reading_timestamp_saudi,
    reading_date_saudi,
    active_energy_cumulative_kwh,
    previous_valid_timestamp,
    previous_valid_kwh,
    validated_kwh_consumption,
    consumption_cleaning_status,
    interval_quality,
    gap_minutes
   FROM silver.fact_energy_consumption_validated;
