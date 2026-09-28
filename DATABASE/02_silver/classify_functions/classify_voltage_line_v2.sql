-- silver.classify_voltage_line_v2(value double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_voltage_line_v2(value double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 360 OR value > 440 THEN RETURN 'Critical'; END IF;
    IF value >= 380 AND value <= 420 THEN RETURN 'Acceptable'; END IF;
    IF (value >= 371.2 AND value < 380) OR (value > 420 AND value <= 428.8) THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zones: 360-371.2 and 428.8-440
END;
$function$
