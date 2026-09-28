-- View silver.contact_method_mapping_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.contact_method_mapping_landing AS
 SELECT contact_id,
    contact_method_id
   FROM bronze.contact_method_mapping;
