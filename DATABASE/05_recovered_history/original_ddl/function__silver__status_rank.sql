-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

CREATE OR REPLACE FUNCTION silver.status_rank(
        p_status text
    )
    RETURNS integer
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT CASE p_status
            WHEN 'Acceptable'      THEN 1
            WHEN 'Review Required' THEN 2
            WHEN 'Anomaly'         THEN 3
            WHEN 'Problematic'     THEN 4
            WHEN 'Critical'        THEN 5
            WHEN 'Invalid'         THEN 6
            ELSE 0
        END;
    $$;
    
    
    -- ============================================================
    -- 2. Return the worst status from multiple checks
    --
    -- Example:
    -- silver.worst_status('Acceptable', 'Problematic')
    -- returns Problematic
    -- ============================================================
    
    CREATE OR REPLACE FUNCTION silver.worst_status(
        VARIADIC p_statuses text[]
    )
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT status_value
        FROM unnest(p_statuses) AS status_value
        WHERE status_value IS NOT NULL
        ORDER BY silver.status_rank(status_value) DESC
        LIMIT 1;
    $$;
    
    
    -- ============================================================
    -- 3. Standard scalar classification
    --
    -- Used for:
    -- Voltage
    -- Current
    -- Frequency
    -- Active Power
    -- Apparent Power
    -- Reactive Power
    --
    -- Logic:
    -- Invalid physical range
    -- Critical hard limit
    -- Anomaly >= high spike threshold
    -- Review Required outside acceptable range
    -- Acceptable otherwise
    -- ============================================================
    
    CREATE OR REPLACE FUNCTION silver.classify_standard(
        p_value           double precision,
        p_prev_value      double precision,
        p_hard_min        double precision,
        p_hard_max        double precision,
        p_acceptable_min  double precision,
        p_acceptable_max  double precision,
        p_invalid_min     double precision DEFAULT NULL,
        p_invalid_max     double precision DEFAULT NULL,
        p_spike_pct       double precision DEFAULT 50.0
    )
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT CASE
            WHEN p_value IS NULL THEN NULL
    
            -- Invalid physical or sanity range
            WHEN p_invalid_min IS NOT NULL
             AND p_value < p_invalid_min
                THEN 'Invalid'
    
            WHEN p_invalid_max IS NOT NULL
             AND p_value > p_invalid_max
                THEN 'Invalid'
    
            -- Hard operational limits
            WHEN p_hard_min IS NOT NULL
             AND p_value < p_hard_min
                THEN 'Critical'
    
            WHEN p_hard_max IS NOT NULL
             AND p_value > p_hard_max
                THEN 'Critical'
    
            -- High spike against previous reading
            WHEN p_prev_value IS NOT NULL
             AND p_prev_value <> 0
             AND ABS(p_value - p_prev_value)
                 / ABS(p_prev_value) * 100 >= p_spike_pct
                THEN 'Anomaly'
    
            -- Outside acceptable range but not outside hard limit
            WHEN p_acceptable_min IS NOT NULL
             AND p_value < p_acceptable_min
                THEN 'Review Required'
    
            WHEN p_acceptable_max IS NOT NULL
             AND p_value > p_acceptable_max
                THEN 'Review Required'
    
            ELSE 'Acceptable'
        END;
    $$;
    
    
    -- ============================================================
    -- 4. Power Factor
    --
    -- Invalid: outside physical range -1 through 1
    -- Problematic: below 0.6
    -- Review Required: 0.6 through below 0.8
    -- Anomaly: high spike, unless already Problematic
    -- Acceptable: 0.8 through 1.0
    -- ============================================================
    
    CREATE OR REPLACE FUNCTION silver.classify_power_factor(
        p_value      double precision,
        p_prev_value double precision,
        p_spike_pct  double precision DEFAULT 50.0
    )
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT CASE
            WHEN p_value IS NULL THEN NULL
    
            WHEN p_value < -1
              OR p_value > 1
                THEN 'Invalid'
    
            -- Problematic outranks Anomaly
            WHEN p_value < 0.6
                THEN 'Problematic'
    
            WHEN p_prev_value IS NOT NULL
             AND p_prev_value <> 0
             AND ABS(p_value - p_prev_value)
                 / ABS(p_prev_value) * 100 >= p_spike_pct
                THEN 'Anomaly'
    
            WHEN p_value < 0.8
                THEN 'Review Required'
    
            ELSE 'Acceptable'
        END;
    $$;
    
    
    -- ============================================================
    -- 5. Accumulated Energy
    --
    -- Used for:
    -- kWh
    -- kVAh
    -- kVArh
    --
    -- Invalid: negative
    -- Critical: above user-defined maximum
    -- Anomaly: cumulative counter decremented
    -- ============================================================
    
    CREATE OR REPLACE FUNCTION silver.classify_energy(
        p_value      double precision,
        p_prev_value double precision,
        p_user_max   double precision DEFAULT NULL
    )
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT CASE
            WHEN p_value IS NULL THEN NULL
    
            WHEN p_value < 0
                THEN 'Invalid'
    
            WHEN p_user_max IS NOT NULL
             AND p_value > p_user_max
                THEN 'Critical'
    
            WHEN p_prev_value IS NOT NULL
             AND p_value < p_prev_value
                THEN 'Anomaly'
    
            ELSE 'Acceptable'
        END;
    $$;
    
    
    -- ============================================================
    -- 6. Total versus sum-of-phases consistency
    --
    -- Used for:
    -- TkW   versus kW1 + kW2 + kW3
    -- TkVA  versus kVA1 + kVA2 + kVA3
    -- TkVAr versus kVAr1 + kVAr2 + kVAr3
    --
    -- Outside +/-5% = Invalid
    -- ============================================================
    
    CREATE OR REPLACE FUNCTION silver.classify_consistency(
        p_total         double precision,
        p_phase_sum     double precision,
        p_tolerance_pct double precision DEFAULT 5.0
    )
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT CASE
            WHEN p_total IS NULL
              OR p_phase_sum IS NULL
                THEN NULL
    
            WHEN p_phase_sum = 0
                THEN CASE
                    WHEN p_total = 0 THEN 'Acceptable'
                    ELSE 'Invalid'
                END
    
            WHEN ABS(p_total - p_phase_sum)
                 / ABS(p_phase_sum) * 100 > p_tolerance_pct
                THEN 'Invalid'
    
            ELSE 'Acceptable'
        END;
    $$;
    
    
    -- ============================================================
    -- 7. Phase imbalance classification
    --
    -- p_evaluation_status must be:
    -- WITHIN_ACCEPTABLE
    -- OUTSIDE_ACCEPTABLE
    -- EVALUATED (backward-compatible mode)
    --
    -- Problematic:
    -- imbalance exists while all phases are acceptable
    --
    -- Critical:
    -- imbalance exists and one or more phases are outside
    -- the acceptable range
    --
    -- Default phase-spread threshold is 5%.
    -- This remains configurable because the sheet does not give
    -- a separate exact phase-imbalance percentage.
    -- ============================================================
    
    CREATE OR REPLACE FUNCTION silver.classify_phase_imbalance(
        p_imbalance_pct              double precision,
        p_evaluation_status          text,
        p_problematic_threshold_pct  double precision DEFAULT 5.0,
        p_critical_threshold_pct     double precision DEFAULT 5.0
    )
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
    AS $$
        SELECT CASE
            WHEN p_imbalance_pct IS NULL
              OR p_evaluation_status IS NULL
                THEN NULL
    
            WHEN UPPER(p_evaluation_status) = 'OUTSIDE_ACCEPTABLE'
             AND p_imbalance_pct > p_critical_threshold_pct
                THEN 'Critical'
    
            WHEN UPPER(p_evaluation_status) = 'WITHIN_ACCEPTABLE'
             AND p_imbalance_pct > p_problematic_threshold_pct
                THEN 'Problematic'
    
            -- Compatibility with previous calls using EVALUATED
            WHEN UPPER(p_evaluation_status) = 'EVALUATED'
             AND p_imbalance_pct > p_critical_threshold_pct
                THEN 'Critical'
    
            WHEN UPPER(p_evaluation_status) = 'EVALUATED'
             AND p_imbalance_pct > p_problematic_threshold_pct
                THEN 'Problematic'
    
            ELSE 'Acceptable'
        END;
