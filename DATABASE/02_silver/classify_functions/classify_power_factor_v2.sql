-- silver.classify_power_factor_v2(value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_power_factor_v2(value double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0.6 OR value > 1 THEN RETURN 'Critical'; END IF;
    IF value >= 0.8 AND value <= 1 THEN RETURN 'Acceptable'; END IF;
    IF value >= 0.78 AND value < 0.8 THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zone: 0.6-0.78
END;
$function$
