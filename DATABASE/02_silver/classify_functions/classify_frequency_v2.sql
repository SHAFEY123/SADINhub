-- silver.classify_frequency_v2(value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_frequency_v2(value double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 59 OR value > 61 THEN RETURN 'Critical'; END IF;
    IF value >= 59.3 AND value <= 60.5 THEN RETURN 'Acceptable'; END IF;
    RETURN 'Problematic';  -- remaining zones: 59-59.3 and 60.5-61
END;
$function$
