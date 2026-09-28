-- View silver.schedule_controllers_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.schedule_controllers_landing AS
 SELECT id,
    schedule_id,
    controller_id,
    execution_sequence,
    controller_action::text COLLATE "C" AS controller_action,
    created_on,
    created_by
   FROM bronze.schedule_controllers;
