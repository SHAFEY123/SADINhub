-- silver.classify_voltage_neutral_v2(value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_voltage_neutral_v2(value double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 207 OR value > 253 THEN RETURN 'Critical'; END IF;
    IF value >= 215 AND value <= 245 THEN RETURN 'Acceptable'; END IF;
    IF (value >= 209.94 AND value < 215) OR (value > 245 AND value <= 250.06) THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zones: 207-209.94 and 250.06-253
END;
$function$
