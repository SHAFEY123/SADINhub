-- silver.classify_current_v2(value double precision, cb_max double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_current_v2(value double precision, cb_max double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    margin double precision;
    third  double precision;
BEGIN
    IF value IS NULL OR cb_max IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0 OR value > cb_max THEN RETURN 'Critical'; END IF;

    margin := 0.15 * cb_max;
    third  := margin / 3.0;

    IF value >= margin AND value <= (cb_max - margin) THEN RETURN 'Acceptable'; END IF;

    IF (value >= third AND value < margin)
       OR (value > (cb_max - margin) AND value <= (cb_max - third)) THEN
        RETURN 'Review Required';
    END IF;

    RETURN 'Problematic';  -- remaining zones: 0-third and (cb_max-third)-cb_max
END;
$function$
