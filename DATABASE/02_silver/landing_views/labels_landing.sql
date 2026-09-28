-- View silver.labels_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.labels_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    icon::text COLLATE "C" AS icon,
    description COLLATE "C" AS description,
    hex_color::text COLLATE "C" AS hex_color,
    active,
    label_type_id,
    created_on,
    created_by
   FROM bronze.labels;
