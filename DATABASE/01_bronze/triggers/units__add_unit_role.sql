-- Trigger add_unit_role on bronze.units
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_triggerdef()


CREATE TRIGGER add_unit_role AFTER INSERT ON bronze.units FOR EACH ROW EXECUTE FUNCTION bronze.link_unit_with_parent_roles();
