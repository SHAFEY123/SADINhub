-- View silver.addresses_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.addresses_landing AS
 SELECT id,
    short_address::text COLLATE "C" AS short_address,
    building_number,
    street_name::text COLLATE "C" AS street_name,
    district_name::text COLLATE "C" AS district_name,
    city_name::text COLLATE "C" AS city_name,
    zip_code,
    additional_number,
    unit_number,
    created_on,
    created_by,
    title::text COLLATE "C" AS title
   FROM bronze.addresses;
