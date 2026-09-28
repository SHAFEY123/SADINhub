-- View silver.icons_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.icons_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    css_class::text COLLATE "C" AS css_class,
    active,
    created_on
   FROM bronze.icons;
