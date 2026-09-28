-- Recovered from PostgreSQL server log postgresql-2026-08-10_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- Corrected classify_* functions
    --
    -- Changes from the originals:
    -- - 5 tiers only, no Anomaly (prev_value comparison removed
    --   from every function except energy's decrement check)
    -- - Invalid is now reserved for NULL/corrupt data only -- the
    --   old numeric Invalid thresholds (e.g. PF>1.0) are absorbed
    --   into Critical, since Critical already covers those values
    -- - classify_current now takes each meter's own CB rating as
    --   a parameter, instead of a fixed threshold
    -- - classify_voltage_line / classify_voltage_neutral now use
    --   the confirmed nested-band shape with 2%-of-Max margins
    -- - classify_active_power, classify_apparent_power,
    --   classify_reactive_power are NOT rewritten -- confirmed
    --   dropped entirely, calls to them will be removed from the
    --   views/tables in the next step, not from this file
    -- ============================================================
    
    -- ------------------------------------------------------------
    -- Voltage (Line-to-Line): Min 360, Max 440, Acceptable 380-420
    -- Margin = 2% of Max (440) = 8.8
    -- ------------------------------------------------------------
    CREATE OR REPLACE FUNCTION silver.classify_voltage_line(value double precision)
    RETURNS text AS $$
    BEGIN
        IF value IS NULL THEN RETURN 'Invalid'; END IF;
        IF value < 360 OR value > 440 THEN RETURN 'Critical'; END IF;
        IF value >= 380 AND value <= 420 THEN RETURN 'Acceptable'; END IF;
        IF (value >= 371.2 AND value < 380) OR (value > 420 AND value <= 428.8) THEN RETURN 'Review Required'; END IF;
        RETURN 'Problematic';  -- remaining zones: 360-371.2 and 428.8-440
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    
    -- ------------------------------------------------------------
    -- Voltage (Line-to-Neutral): Min 207, Max 253, Acceptable 215-245
    -- Margin = 2% of Max (253) = 5.06
    -- ------------------------------------------------------------
    CREATE OR REPLACE FUNCTION silver.classify_voltage_neutral(value double precision)
    RETURNS text AS $$
    BEGIN
        IF value IS NULL THEN RETURN 'Invalid'; END IF;
        IF value < 207 OR value > 253 THEN RETURN 'Critical'; END IF;
        IF value >= 215 AND value <= 245 THEN RETURN 'Acceptable'; END IF;
        IF (value >= 209.94 AND value < 215) OR (value > 245 AND value <= 250.06) THEN RETURN 'Review Required'; END IF;
        RETURN 'Problematic';  -- remaining zones: 207-209.94 and 250.06-253
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    
    -- ------------------------------------------------------------
    -- Frequency: Min 59, Max 61, Acceptable 59.3-60.5
    -- No Review Required tier -- straight Acceptable -> Problematic
    -- ------------------------------------------------------------
    CREATE OR REPLACE FUNCTION silver.classify_frequency(value double precision)
    RETURNS text AS $$
    BEGIN
        IF value IS NULL THEN RETURN 'Invalid'; END IF;
        IF value < 59 OR value > 61 THEN RETURN 'Critical'; END IF;
        IF value >= 59.3 AND value <= 60.5 THEN RETURN 'Acceptable'; END IF;
        RETURN 'Problematic';  -- remaining zones: 59-59.3 and 60.5-61
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    
    -- ------------------------------------------------------------
    -- Power Factor: Min 0.6, Max 1, Acceptable 0.8-1 (Acceptable
    -- Max = Max, so there's no upper Review Required/Problematic band)
    -- ------------------------------------------------------------
    CREATE OR REPLACE FUNCTION silver.classify_power_factor(value double precision)
    RETURNS text AS $$
    BEGIN
        IF value IS NULL THEN RETURN 'Invalid'; END IF;
        IF value < 0.6 OR value > 1 THEN RETURN 'Critical'; END IF;
        IF value >= 0.8 AND value <= 1 THEN RETURN 'Acceptable'; END IF;
        IF value >= 0.78 AND value < 0.8 THEN RETURN 'Review Required'; END IF;
        RETURN 'Problematic';  -- remaining zone: 0.6-0.78
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    
    -- ------------------------------------------------------------
    -- Current: per-meter CB rating. Margin = 15% of cb_max, split
    -- into thirds -- inner third (nearer Acceptable) = Review
    -- Required, outer two-thirds (nearer the edge) = Problematic.
    -- ------------------------------------------------------------
    CREATE OR REPLACE FUNCTION silver.classify_current(value double precision, cb_max double precision)
    RETURNS text AS $$
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
    $$ LANGUAGE plpgsql IMMUTABLE;
    
    -- ------------------------------------------------------------
    -- Accumulated Energy (kWh only): the one function that still
    -- needs the previous reading -- a decrement is only detectable
    -- by comparing to what came right before it.
    -- ------------------------------------------------------------
    CREATE OR REPLACE FUNCTION silver.classify_accumulated_energy(value double precision, prev_value double precision)
    RETURNS text AS $$
    BEGIN
        IF value IS NULL THEN RETURN 'Invalid'; END IF;
        IF prev_value IS NULL THEN RETURN 'Acceptable'; END IF;  -- first-ever reading for this meter, nothing to compare
        IF value < prev_value THEN RETURN 'Invalid'; END IF;      -- decrement -- counter went backward
        RETURN 'Acceptable';
    END;
    $$ LANGUAGE plpgsql IMMUTABLE;
    
    -- ============================================================
    -- Quick self-test -- run these to confirm each function behaves
    -- as expected before touching any real table.
    -- ============================================================
    SELECT
        silver.classify_voltage_line(400::double precision)   AS should_be_acceptable,
        silver.classify_voltage_line(375::double precision)   AS should_be_review_required,
        silver.classify_voltage_line(365::double precision)   AS should_be_problematic,
        silver.classify_voltage_line(300::double precision)   AS should_be_critical,
        silver.classify_voltage_line(NULL::double precision)  AS should_be_invalid;
    
    SELECT
        silver.classify_frequency(59.8::double precision)     AS should_be_acceptable,
        silver.classify_frequency(59.1::double precision)     AS should_be_problematic,
        silver.classify_frequency(58::double precision)       AS should_be_critical;
    
    SELECT
        silver.classify_power_factor(0.9::double precision)   AS should_be_acceptable,
        silver.classify_power_factor(0.79::double precision)  AS should_be_review_required,
        silver.classify_power_factor(0.7::double precision)   AS should_be_problematic,
        silver.classify_power_factor(1.5::double precision)   AS should_be_critical;
    
    -- Current, CB=80 (matches the worked example: Problematic 0-4 and 76-80,
    -- Review Required 4-12 and 68-76, Acceptable 12-68, Critical <0 or >80)
    SELECT
        silver.classify_current(40::double precision, 80::double precision)   AS should_be_acceptable,
        silver.classify_current(8::double precision, 80::double precision)    AS should_be_review_required,
        silver.classify_current(2::double precision, 80::double precision)    AS should_be_problematic,
        silver.classify_current(90::double precision, 80::double precision)   AS should_be_critical,
        silver.classify_current(50::double precision, NULL::double precision) AS should_be_invalid;
    
    SELECT
        silver.classify_accumulated_energy(48.0::double precision, 47.5::double precision) AS should_be_acceptable,
        silver.classify_accumulated_energy(47.0::double precision, 47.5::double precision) AS should_be_invalid_decrement,
        silver.classify_accumulated_energy(46.5::double precision, NULL::double precision) AS should_be_acceptable_first_reading;
