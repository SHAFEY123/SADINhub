-- Trigger add_alarm_to_device_constraint on bronze.device
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_triggerdef()


CREATE TRIGGER add_alarm_to_device_constraint AFTER INSERT ON bronze.device FOR EACH ROW EXECUTE FUNCTION bronze.add_alarm_to_device();
