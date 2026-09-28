-- silver.classify_current_v2(value double precision, cb_max double precision, phase_kw double precision)
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_functiondef() - full source held by the server


CREATE OR REPLACE FUNCTION silver.classify_current_v2(value double precision, cb_max double precision, phase_kw double precision)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    margin double precision;
    third  double precision;
BEGIN
    IF value IS NULL OR cb_max IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0 THEN RETURN 'Invalid'; END IF;
    IF value > cb_max THEN RETURN 'Critical'; END IF;

    margin := 0.15 * cb_max;
    third  := margin / 3.0;

    -- Upper side -- unchanged
    IF value > (cb_max - third) THEN RETURN 'Problematic'; END IF;
    IF value > (cb_max - margin) THEN RETURN 'Review Required'; END IF;

    -- Lower fringe zone (0 to margin) -- new agreement-based logic
    IF value < margin THEN
        IF value = 0 AND phase_kw = 0 THEN RETURN 'Acceptable'; END IF;
        IF value > 0 AND phase_kw = 0 THEN RETURN 'Major Problem'; END IF;
        IF value = 0 AND phase_kw <> 0 THEN RETURN 'Major Issue'; END IF;
        RETURN 'Acceptable';  -- both nonzero -- consistent, any magnitude
    END IF;

    -- Safe middle -- unchanged
    RETURN 'Acceptable';
END;
$function$
