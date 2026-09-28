-- Trigger check_facility_budget_duplication_constraint on bronze.budgets
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_triggerdef()


CREATE TRIGGER check_facility_budget_duplication_constraint BEFORE INSERT ON bronze.budgets FOR EACH ROW EXECUTE FUNCTION bronze.check_facility_budget_duplication();
