-- View silver.consumption_categories_grid_billing_accounts_types_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.consumption_categories_grid_billing_accounts_types_landing AS
 SELECT consumption_category_id,
    grid_billing_account_type_id,
    fee_per_kwh,
    created_by,
    created_on
   FROM bronze.consumption_categories_grid_billing_accounts_types;
