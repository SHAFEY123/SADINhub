-- View silver.multi_factor_authentication_factors_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.multi_factor_authentication_factors_landing AS
 SELECT id,
    token::text COLLATE "C" AS token,
    additional_config::jsonb AS additional_config,
    type_id,
    active
   FROM bronze.multi_factor_authentication_factors;
