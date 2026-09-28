-- View gold.facility
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.facility AS
 SELECT facility_key,
    facility_name,
    facility_type_key,
    facility_type_name,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    address_key,
    address_title,
    short_address,
    building_number,
    street_name,
    district_name,
    city_name,
    zip_code,
    additional_number,
    unit_number,
    source_created_at
   FROM silver.dim_facility_staging;
