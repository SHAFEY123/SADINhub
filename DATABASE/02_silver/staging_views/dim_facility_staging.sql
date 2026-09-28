-- View silver.dim_facility_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.dim_facility_staging AS
 SELECT f.id AS facility_key,
    f.name AS facility_name,
    f.facility_type_id AS facility_type_key,
    ft.name AS facility_type_name,
    f.latitude,
    f.longitude,
    f.x_coordinate,
    f.y_coordinate,
    f.address_id AS address_key,
    a.title AS address_title,
    a.short_address,
    a.building_number,
    a.street_name,
    a.district_name,
    a.city_name,
    a.zip_code,
    a.additional_number,
    a.unit_number,
    f.created_on AS source_created_at
   FROM silver.facilities_landing f
     LEFT JOIN silver.facilities_types_landing ft ON ft.id = f.facility_type_id
     LEFT JOIN silver.addresses_landing a ON a.id = f.address_id;
