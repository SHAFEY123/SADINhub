-- View silver.grid_billing_accounts_service_classes_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.grid_billing_accounts_service_classes_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    minimal_breaker_capacity,
    maximum_breaker_capacity,
    fee,
    facility_id,
    active,
    created_by,
    created_on
   FROM bronze.grid_billing_accounts_service_classes;
