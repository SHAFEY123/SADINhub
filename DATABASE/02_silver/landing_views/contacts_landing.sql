-- View silver.contacts_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.contacts_landing AS
 SELECT id,
    full_name::text COLLATE "C" AS full_name,
    description::text COLLATE "C" AS description,
    preferences::jsonb AS preferences,
    user_id,
    email::text COLLATE "C" AS email,
    phone_number::text COLLATE "C" AS phone_number,
    created_on,
    created_by
   FROM bronze.contacts;
