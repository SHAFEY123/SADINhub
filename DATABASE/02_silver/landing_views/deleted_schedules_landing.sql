-- View silver.deleted_schedules_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.deleted_schedules_landing AS
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
    deleted_by,
    deleted_at,
    deleted_schedule_units,
    deleted_schedule_controllers
   FROM bronze.deleted_schedules;
