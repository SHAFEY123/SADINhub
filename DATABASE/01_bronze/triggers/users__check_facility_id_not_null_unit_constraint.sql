-- Trigger check_facility_id_not_null_unit_constraint on bronze.users
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_triggerdef()


CREATE TRIGGER check_facility_id_not_null_unit_constraint BEFORE INSERT ON bronze.users FOR EACH ROW EXECUTE FUNCTION bronze.check_facility_id_not_null();
