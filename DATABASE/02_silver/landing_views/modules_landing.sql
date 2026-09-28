-- View silver.modules_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.modules_landing AS
 SELECT id,
    title::text COLLATE "C" AS title,
    html_class::text COLLATE "C" AS html_class,
    color::text COLLATE "C" AS color,
    has_children,
    level,
    parent_id,
    priority,
    route_to::text COLLATE "C" AS route_to,
    created_on
   FROM bronze.modules;
