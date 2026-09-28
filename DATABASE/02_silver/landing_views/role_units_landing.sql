-- View silver.role_units_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.role_units_landing AS
 SELECT role_id,
    unit_id,
    unit_level,
    created_on,
    created_by
   FROM bronze.role_units;
