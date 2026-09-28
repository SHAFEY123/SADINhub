-- View silver.dim_zone_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.dim_zone_staging AS
 SELECT u.id AS zone_key,
    u.facility_id AS facility_key,
    u.parent_id AS parent_zone_key,
    parent_u.name AS parent_zone_name,
    u.name AS zone_name,
    u.type_id AS zone_type_key,
    ut.name AS zone_type_name,
    u.level AS hierarchy_level,
    u.is_building,
    u.active AS is_active,
    u.has_children,
    u.latitude,
    u.longitude,
    u.x_coordinate,
    u.y_coordinate,
    u.html_hex_color,
    u.description,
    u.created_on AS source_created_at
   FROM silver.units_landing u
     LEFT JOIN silver.units_landing parent_u ON parent_u.id = u.parent_id
     LEFT JOIN silver.units_types_landing ut ON ut.id = u.type_id;
