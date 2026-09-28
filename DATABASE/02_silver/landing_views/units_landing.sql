-- View silver.units_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.units_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    is_building,
    level,
    parent_id,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    type_id,
    active,
    has_children,
    icon_id,
    html_hex_color::text COLLATE "C" AS html_hex_color,
    description COLLATE "C" AS description,
    created_on,
    created_by,
    facility_id
   FROM bronze.units;
