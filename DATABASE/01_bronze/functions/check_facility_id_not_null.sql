-- bronze.check_facility_id_not_null()
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema bronze
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION bronze.check_facility_id_not_null()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.facility_id IS NULL THEN
        RAISE EXCEPTION 'facility_id cannot be null';
    END IF;
    RETURN NEW;
END;
$function$
