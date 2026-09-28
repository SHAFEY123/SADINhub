-- View gold.mapping_audit
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.mapping_audit AS
 SELECT source_energy_meter_id,
    device_id,
    facility_id,
    zone_key,
    zone_name,
    source_device_name,
    source_meter_label,
    canonical_device_name,
    canonical_meter_label,
    source_meter_records_for_device,
    source_records_for_meter_label,
    business_rule_code,
    canonical_mapping_rank,
    mapping_decision,
    mapping_status,
    is_meter_active,
    meter_source_created_at
   FROM silver.energy_meter_mapping_audit_staging;
