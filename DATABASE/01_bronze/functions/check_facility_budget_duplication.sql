-- bronze.check_facility_budget_duplication()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.check_facility_budget_duplication()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF EXISTS (
        SELECT 1 FROM budgets
        WHERE budgets.type_id = NEW.type_id
    ) THEN
        RAISE EXCEPTION 'Budget of the same type already exist';
    END IF;
    RETURN NEW;
END;
$function$
