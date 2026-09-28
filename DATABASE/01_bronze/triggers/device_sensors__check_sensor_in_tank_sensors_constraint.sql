-- Trigger check_sensor_in_tank_sensors_constraint on bronze.device_sensors
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_triggerdef()


CREATE TRIGGER check_sensor_in_tank_sensors_constraint BEFORE INSERT ON bronze.device_sensors FOR EACH ROW EXECUTE FUNCTION bronze.check_sensor_in_tank_sensors();
