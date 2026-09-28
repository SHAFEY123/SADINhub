-- View silver.energy_meter_phase_map_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.energy_meter_phase_map_landing AS
 SELECT parent_device,
    phase_parent,
    child_device,
    phase_child
   FROM bronze.energy_meter_phase_map;
