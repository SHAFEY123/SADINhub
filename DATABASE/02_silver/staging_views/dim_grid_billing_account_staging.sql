-- View silver.dim_grid_billing_account_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.dim_grid_billing_account_staging AS
 SELECT gba.id AS grid_billing_account_key,
    gba.facility_id AS facility_key,
    gba.unit_id AS zone_key,
    gba.label AS account_label,
    gba.number::text COLLATE "C" AS account_number,
    gba.meter_serial_number,
    gba.type_id AS account_type_key,
    gbat.name AS account_type_name,
    gba.service_class_id AS service_class_key,
    gbasc.name AS service_class_name,
    gba.breaker_capacity,
    gbasc.minimal_breaker_capacity,
    gbasc.maximum_breaker_capacity,
    gbasc.fee AS service_class_fee,
    gba.multiplication_factor,
    gba.start_period,
    gba.end_period,
    gba.days AS configured_billing_days,
    gba.created_on AS source_created_at
   FROM silver.grid_billing_accounts_landing gba
     LEFT JOIN silver.grid_billing_accounts_types_landing gbat ON gbat.id = gba.type_id
     LEFT JOIN silver.grid_billing_accounts_service_classes_landing gbasc ON gbasc.id = gba.service_class_id;
