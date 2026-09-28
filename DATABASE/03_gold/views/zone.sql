-- View gold.zone
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.zone AS
 SELECT zone_key,
    facility_key,
    parent_zone_key,
    parent_zone_name,
    zone_name,
    zone_type_key,
    zone_type_name,
    hierarchy_level,
    is_building,
    is_active,
    has_children,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    html_hex_color,
    description,
    source_created_at
   FROM silver.dim_zone_staging;
