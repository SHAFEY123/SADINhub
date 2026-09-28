-- View silver.contact_methods_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.contact_methods_landing AS
 SELECT id,
    title::text COLLATE "C" AS title,
    description::text COLLATE "C" AS description,
    created_on
   FROM bronze.contact_methods;
