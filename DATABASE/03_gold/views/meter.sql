-- View gold.meter
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.meter AS
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    parent_energy_meter_source_id,
    meter_label,
    meter_serial_number,
    phase_count,
    maximum_kwh,
    energy_meter_type_key,
    energy_meter_type_name,
    is_meter_active,
    device_name,
    device_label,
    device_serial_number,
    device_type_key,
    device_type_name,
    device_category_key,
    device_category_name,
    gateway_id,
    is_device_active,
    is_device_online,
    assembly_date,
    device_properties,
    source_meter_records_for_device,
    source_records_for_meter_label,
    meter_label_matches_device_name,
    mapping_status,
    meter_source_created_at
   FROM silver.dim_energy_meter_staging;
