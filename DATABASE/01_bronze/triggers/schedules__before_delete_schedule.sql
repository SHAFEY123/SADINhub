-- Trigger before_delete_schedule on bronze.schedules
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_triggerdef()


CREATE TRIGGER before_delete_schedule BEFORE DELETE ON bronze.schedules FOR EACH ROW EXECUTE FUNCTION bronze.archive_deleted_schedule();
