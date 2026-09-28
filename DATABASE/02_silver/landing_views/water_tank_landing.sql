-- View silver.water_tank_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_tank_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    capacity,
    width,
    body_height,
    inside_water_height,
    length,
    diameter,
    thickness,
    max_temperature,
    min_temperature,
    max_pressure,
    min_pressure,
    water_source_id,
    type_id,
    location_id,
    active,
    created_by,
    created_on,
    label_id
   FROM bronze.water_tank;
