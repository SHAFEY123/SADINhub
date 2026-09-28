-- View silver.schedules_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.schedules_landing AS
 SELECT id,
    name::text COLLATE "C" AS name,
    description COLLATE "C" AS description,
    start_datetime,
    end_datetime,
    schedule_duration,
    triggers,
    active,
    created_on,
    created_by,
    schedule_type::text COLLATE "C" AS schedule_type
   FROM bronze.schedules;
