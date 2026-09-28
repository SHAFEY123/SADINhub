-- View silver.device_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.device_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    active,
    gateway_id,
    label::text COLLATE "C" AS label,
    user_conf::jsonb AS user_conf,
    description::text COLLATE "C" AS description,
    type_id,
    unit_id,
    created_on,
    created_by,
    facility_id,
    online,
    client_id,
    assembly_date,
    serial_number,
    label_id,
    properties
   FROM bronze.device;
