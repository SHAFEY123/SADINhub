-- View gold.quality_summary
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.quality_summary AS
 SELECT energy_meter_key,
    meter_label,
    total_readings,
    overall_acceptable_count,
    overall_review_required_count,
    overall_anomaly_count,
    overall_problematic_count,
    overall_critical_count,
    overall_invalid_count,
    computed_at
   FROM silver.data_quality_summary;
