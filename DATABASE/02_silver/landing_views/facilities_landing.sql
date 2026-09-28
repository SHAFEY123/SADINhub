-- View silver.facilities_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.facilities_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    unit_id,
    facility_type_id,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    address_id,
    created_on,
    created_by
   FROM bronze.facilities;
