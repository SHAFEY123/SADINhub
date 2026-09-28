-- View silver.overlay_controllers_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.overlay_controllers_landing AS
 SELECT overlay_id,
    controller_id
   FROM bronze.overlay_controllers;
