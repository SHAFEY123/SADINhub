-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- silver.fact_energy_readings_flagged
    --
    -- Row-level data quality flagging view built on top of
    -- silver.fact_energy_readings_staging.
    --
    -- Adds boolean flag columns per the SADINhub flagging criteria
    -- (voltage, current, frequency, power factor, active/apparent/
    -- reactive power, accumulated energy).
    --
    -- IMPORTANT PLACEHOLDERS TO EDIT BEFORE PRODUCTION USE:
    --   - v_cb_max_rating_a   : circuit breaker max current rating
    --                            (varies per meter -- currently a
    --                            single placeholder constant)
    --   - v_kva_user_max      : user-defined max apparent power
    --   - v_kvar_user_max     : user-defined max reactive power
    --   - v_kwh_user_max      : user-defined max cumulative kWh
    --   - v_kvah_user_max     : user-defined max cumulative kVAh
    --   - v_kvarh_user_max    : user-defined max cumulative kVArh
    --
    -- Once meter-specific CB ratings / user-defined maxes are
    -- available (e.g. from a lookup table), replace the constants
    -- below with a JOIN to that table instead.
    -- ============================================================
    
    CREATE OR REPLACE VIEW silver.fact_energy_readings_flagged AS
    WITH constants AS (
        SELECT
            30.0  AS spike_moderate_pct,      -- >=30% change vs previous reading
            50.0  AS spike_high_pct,          -- >=50% change vs previous reading
            5.0   AS consistency_tolerance_pct, -- total vs sum-of-phases tolerance
            -- --- PLACEHOLDERS: replace with real values or a lookup join ---
            9999999.0 AS v_cb_max_rating_a,   -- TODO: per-meter CB current rating
            9999999.0 AS v_cb_max_rating_kw,  -- TODO: per-meter CB active power rating
            9999999.0 AS v_kva_user_max,      -- TODO: user-defined kVA ceiling
            9999999.0 AS v_kvar_user_max,     -- TODO: user-defined kVAr ceiling
            9999999.0 AS v_kwh_user_max,      -- TODO: user-defined kWh ceiling
            9999999.0 AS v_kvah_user_max,     -- TODO: user-defined kVAh ceiling
            9999999.0 AS v_kvarh_user_max     -- TODO: user-defined kVArh ceiling
    ),
    base AS (
        SELECT
            f.*,
            c.spike_moderate_pct,
            c.spike_high_pct,
            c.consistency_tolerance_pct,
            c.v_cb_max_rating_a,
            c.v_cb_max_rating_kw,
            c.v_kva_user_max,
            c.v_kvar_user_max,
            c.v_kwh_user_max,
            c.v_kvah_user_max,
            c.v_kvarh_user_max,
    
            -- Previous-reading values for spike detection (per meter, ordered by time)
            LAG(f.voltage_neutral_1_v)      OVER w AS prev_vn1,
            LAG(f.voltage_neutral_2_v)      OVER w AS prev_vn2,
            LAG(f.voltage_neutral_3_v)      OVER w AS prev_vn3,
            LAG(f.voltage_neutral_average_v) OVER w AS prev_vna,
    
            LAG(f.current_phase_1_a)        OVER w AS prev_amp1,
            LAG(f.current_phase_2_a)        OVER w AS prev_amp2,
            LAG(f.current_phase_3_a)        OVER w AS prev_amp3,
            LAG(f.current_average_a)        OVER w AS prev_ampa,
    
            LAG(f.frequency_hz)             OVER w AS prev_hz,
    
            LAG(f.power_factor_phase_1)     OVER w AS prev_pf1,
            LAG(f.power_factor_phase_2)     OVER w AS prev_pf2,
            LAG(f.power_factor_phase_3)     OVER w AS prev_pf3,
            LAG(f.power_factor_average)     OVER w AS prev_pfa,
    
            LAG(f.active_power_phase_1_kw)  OVER w AS prev_kw1,
            LAG(f.active_power_phase_2_kw)  OVER w AS prev_kw2,
            LAG(f.active_power_phase_3_kw)  OVER w AS prev_kw3,
            LAG(f.active_power_total_kw)    OVER w AS prev_tkw,
    
            LAG(f.apparent_power_phase_1_kva) OVER w AS prev_kva1,
            LAG(f.apparent_power_phase_2_kva) OVER w AS prev_kva2,
            LAG(f.apparent_power_phase_3_kva) OVER w AS prev_kva3,
            LAG(f.apparent_power_total_kva)   OVER w AS prev_tkva,
    
            LAG(f.reactive_power_phase_1_kvar) OVER w AS prev_kvar1,
            LAG(f.reactive_power_phase_2_kvar) OVER w AS prev_kvar2,
            LAG(f.reactive_power_phase_3_kvar) OVER w AS prev_kvar3,
            LAG(f.reactive_power_total_kvar)   OVER w AS prev_tkvar,
    
            LAG(f.active_energy_cumulative_kwh)     OVER w AS prev_kwh,
            LAG(f.apparent_energy_cumulative_kvah)  OVER w AS prev_kvah,
            LAG(f.reactive_energy_cumulative_kvarh) OVER w AS prev_kvarh
    
        FROM silver.fact_energy_readings_staging f
        CROSS JOIN constants c
        WINDOW w AS (PARTITION BY f.energy_meter_key ORDER BY f.reading_timestamp_utc)
    )
    SELECT
        b.*,
    
        -- ============================================================
        -- VOLTAGE (Line-to-Neutral): Vn1, Vn2, Vn3, Vna
        -- Hard limit 207-253V | Acceptable 215-245V
        -- ============================================================
        (b.voltage_neutral_1_v < 207 OR b.voltage_neutral_1_v > 253) AS vn1_hard_limit_flag,
        (b.voltage_neutral_1_v < 215 OR b.voltage_neutral_1_v > 245) AS vn1_acceptable_range_flag,
        (b.prev_vn1 IS NOT NULL AND b.prev_vn1 <> 0
            AND ABS(b.voltage_neutral_1_v - b.prev_vn1) / ABS(b.prev_vn1) * 100 >= b.spike_high_pct)     AS vn1_high_spike_flag,
        (b.prev_vn1 IS NOT NULL AND b.prev_vn1 <> 0
            AND ABS(b.voltage_neutral_1_v - b.prev_vn1) / ABS(b.prev_vn1) * 100 >= b.spike_moderate_pct)  AS vn1_moderate_spike_flag,
    
        (b.voltage_neutral_2_v < 207 OR b.voltage_neutral_2_v > 253) AS vn2_hard_limit_flag,
        (b.voltage_neutral_2_v < 215 OR b.voltage_neutral_2_v > 245) AS vn2_acceptable_range_flag,
        (b.prev_vn2 IS NOT NULL AND b.prev_vn2 <> 0
            AND ABS(b.voltage_neutral_2_v - b.prev_vn2) / ABS(b.prev_vn2) * 100 >= b.spike_high_pct)     AS vn2_high_spike_flag,
        (b.prev_vn2 IS NOT NULL AND b.prev_vn2 <> 0
            AND ABS(b.voltage_neutral_2_v - b.prev_vn2) / ABS(b.prev_vn2) * 100 >= b.spike_moderate_pct)  AS vn2_moderate_spike_flag,
    
        (b.voltage_neutral_3_v < 207 OR b.voltage_neutral_3_v > 253) AS vn3_hard_limit_flag,
        (b.voltage_neutral_3_v < 215 OR b.voltage_neutral_3_v > 245) AS vn3_acceptable_range_flag,
        (b.prev_vn3 IS NOT NULL AND b.prev_vn3 <> 0
            AND ABS(b.voltage_neutral_3_v - b.prev_vn3) / ABS(b.prev_vn3) * 100 >= b.spike_high_pct)     AS vn3_high_spike_flag,
        (b.prev_vn3 IS NOT NULL AND b.prev_vn3 <> 0
            AND ABS(b.voltage_neutral_3_v - b.prev_vn3) / ABS(b.prev_vn3) * 100 >= b.spike_moderate_pct)  AS vn3_moderate_spike_flag,
    
        -- Phase spread check: max<min within acceptable range (i.e. any phase outside 215-245 while others are within)
        (GREATEST(b.voltage_neutral_1_v, b.voltage_neutral_2_v, b.voltage_neutral_3_v)
            - LEAST(b.voltage_neutral_1_v, b.voltage_neutral_2_v, b.voltage_neutral_3_v)) AS vn_phase_spread_v,
    
        -- ============================================================
        -- CURRENT: Amp1, Amp2, Amp3, Ampa
        -- Hard limit: 0 to CB max rating
        -- ============================================================
        (b.current_phase_1_a < 0 OR b.current_phase_1_a > b.v_cb_max_rating_a) AS amp1_hard_limit_flag,
        (b.prev_amp1 IS NOT NULL AND b.prev_amp1 <> 0
            AND ABS(b.current_phase_1_a - b.prev_amp1) / ABS(b.prev_amp1) * 100 >= b.spike_high_pct)     AS amp1_high_spike_flag,
        (b.prev_amp1 IS NOT NULL AND b.prev_amp1 <> 0
            AND ABS(b.current_phase_1_a - b.prev_amp1) / ABS(b.prev_amp1) * 100 >= b.spike_moderate_pct)  AS amp1_moderate_spike_flag,
    
        (b.current_phase_2_a < 0 OR b.current_phase_2_a > b.v_cb_max_rating_a) AS amp2_hard_limit_flag,
        (b.prev_amp2 IS NOT NULL AND b.prev_amp2 <> 0
            AND ABS(b.current_phase_2_a - b.prev_amp2) / ABS(b.prev_amp2) * 100 >= b.spike_high_pct)     AS amp2_high_spike_flag,
        (b.prev_amp2 IS NOT NULL AND b.prev_amp2 <> 0
            AND ABS(b.current_phase_2_a - b.prev_amp2) / ABS(b.prev_amp2) * 100 >= b.spike_moderate_pct)  AS amp2_moderate_spike_flag,
    
        (b.current_phase_3_a < 0 OR b.current_phase_3_a > b.v_cb_max_rating_a) AS amp3_hard_limit_flag,
        (b.prev_amp3 IS NOT NULL AND b.prev_amp3 <> 0
            AND ABS(b.current_phase_3_a - b.prev_amp3) / ABS(b.prev_amp3) * 100 >= b.spike_high_pct)     AS amp3_high_spike_flag,
        (b.prev_amp3 IS NOT NULL AND b.prev_amp3 <> 0
            AND ABS(b.current_phase_3_a - b.prev_amp3) / ABS(b.prev_amp3) * 100 >= b.spike_moderate_pct)  AS amp3_moderate_spike_flag,
    
        (GREATEST(b.current_phase_1_a, b.current_phase_2_a, b.current_phase_3_a)
            - LEAST(b.current_phase_1_a, b.current_phase_2_a, b.current_phase_3_a)) AS current_phase_spread_a,
    
        -- ============================================================
        -- FREQUENCY: Hz
        -- Hard limit 59.3-60.5 | Acceptable 59-61
        -- ============================================================
        (b.frequency_hz < 59.3 OR b.frequency_hz > 60.5) AS hz_hard_limit_flag,
        (b.frequency_hz < 59.0 OR b.frequency_hz > 61.0) AS hz_acceptable_range_flag,
        (b.prev_hz IS NOT NULL AND b.prev_hz <> 0
            AND ABS(b.frequency_hz - b.prev_hz) / ABS(b.prev_hz) * 100 >= b.spike_high_pct)     AS hz_high_spike_flag,
        (b.prev_hz IS NOT NULL AND b.prev_hz <> 0
            AND ABS(b.frequency_hz - b.prev_hz) / ABS(b.prev_hz) * 100 >= b.spike_moderate_pct)  AS hz_moderate_spike_flag,
    
        -- ============================================================
        -- POWER FACTOR: PF1, PF2, PF3, PFa
        -- Valid physical range -1 to 1 | Hard limit 0.6-1.0 | Acceptable 0.8-1.0
        -- ============================================================
        (b.power_factor_phase_1 < -1 OR b.power_factor_phase_1 > 1) AS pf1_invalid_range_flag,
        (b.power_factor_phase_1 < 0.6)  AS pf1_below_hard_limit_flag,
        (b.power_factor_phase_1 < 0.8)  AS pf1_below_acceptable_flag,
        (b.prev_pf1 IS NOT NULL AND b.prev_pf1 <> 0
            AND ABS(b.power_factor_phase_1 - b.prev_pf1) / ABS(b.prev_pf1) * 100 >= b.spike_high_pct)    AS pf1_high_spike_flag,
    
        (b.power_factor_phase_2 < -1 OR b.power_factor_phase_2 > 1) AS pf2_invalid_range_flag,
        (b.power_factor_phase_2 < 0.6)  AS pf2_below_hard_limit_flag,
        (b.power_factor_phase_2 < 0.8)  AS pf2_below_acceptable_flag,
        (b.prev_pf2 IS NOT NULL AND b.prev_pf2 <> 0
            AND ABS(b.power_factor_phase_2 - b.prev_pf2) / ABS(b.prev_pf2) * 100 >= b.spike_high_pct)    AS pf2_high_spike_flag,
    
        (b.power_factor_phase_3 < -1 OR b.power_factor_phase_3 > 1) AS pf3_invalid_range_flag,
        (b.power_factor_phase_3 < 0.6)  AS pf3_below_hard_limit_flag,
        (b.power_factor_phase_3 < 0.8)  AS pf3_below_acceptable_flag,
        (b.prev_pf3 IS NOT NULL AND b.prev_pf3 <> 0
            AND ABS(b.power_factor_phase_3 - b.prev_pf3) / ABS(b.prev_pf3) * 100 >= b.spike_high_pct)    AS pf3_high_spike_flag,
    
        -- ============================================================
        -- ACTIVE POWER: kW1, kW2, kW3, TkW
        -- Hard limit: 0 to CB max rating | TkW should ~= sum(kW1,kW2,kW3) +-5%
        -- ============================================================
        (b.active_power_phase_1_kw < 0 OR b.active_power_phase_1_kw > b.v_cb_max_rating_kw) AS kw1_hard_limit_flag,
        (b.prev_kw1 IS NOT NULL AND b.prev_kw1 <> 0
            AND ABS(b.active_power_phase_1_kw - b.prev_kw1) / ABS(b.prev_kw1) * 100 >= b.spike_high_pct) AS kw1_high_spike_flag,
    
        (b.active_power_phase_2_kw < 0 OR b.active_power_phase_2_kw > b.v_cb_max_rating_kw) AS kw2_hard_limit_flag,
        (b.prev_kw2 IS NOT NULL AND b.prev_kw2 <> 0
            AND ABS(b.active_power_phase_2_kw - b.prev_kw2) / ABS(b.prev_kw2) * 100 >= b.spike_high_pct) AS kw2_high_spike_flag,
    
        (b.active_power_phase_3_kw < 0 OR b.active_power_phase_3_kw > b.v_cb_max_rating_kw) AS kw3_hard_limit_flag,
        (b.prev_kw3 IS NOT NULL AND b.prev_kw3 <> 0
            AND ABS(b.active_power_phase_3_kw - b.prev_kw3) / ABS(b.prev_kw3) * 100 >= b.spike_high_pct) AS kw3_high_spike_flag,
    
        (b.active_power_total_kw < 0) AS tkw_negative_flag,
        (
            num_nonnulls(b.active_power_phase_1_kw, b.active_power_phase_2_kw, b.active_power_phase_3_kw, b.active_power_total_kw) = 4
            AND ABS(
                b.active_power_total_kw
                - (b.active_power_phase_1_kw + b.active_power_phase_2_kw + b.active_power_phase_3_kw)
            ) / NULLIF(ABS(b.active_power_phase_1_kw + b.active_power_phase_2_kw + b.active_power_phase_3_kw), 0) * 100
            > b.consistency_tolerance_pct
        ) AS tkw_sum_consistency_flag,
    
        -- ============================================================
        -- APPARENT POWER: kVA1, kVA2, kVA3, TkVA
        -- Hard limit: 0 to user-defined max | TkVA should ~= sum +-5%
        -- ============================================================
        (b.apparent_power_phase_1_kva < 0 OR b.apparent_power_phase_1_kva > b.v_kva_user_max) AS kva1_hard_limit_flag,
        (b.apparent_power_phase_2_kva < 0 OR b.apparent_power_phase_2_kva > b.v_kva_user_max) AS kva2_hard_limit_flag,
        (b.apparent_power_phase_3_kva < 0 OR b.apparent_power_phase_3_kva > b.v_kva_user_max) AS kva3_hard_limit_flag,
        (b.apparent_power_total_kva < 0) AS tkva_negative_flag,
        (
            num_nonnulls(b.apparent_power_phase_1_kva, b.apparent_power_phase_2_kva, b.apparent_power_phase_3_kva, b.apparent_power_total_kva) = 4
            AND ABS(
                b.apparent_power_total_kva
                - (b.apparent_power_phase_1_kva + b.apparent_power_phase_2_kva + b.apparent_power_phase_3_kva)
            ) / NULLIF(ABS(b.apparent_power_phase_1_kva + b.apparent_power_phase_2_kva + b.apparent_power_phase_3_kva), 0) * 100
            > b.consistency_tolerance_pct
        ) AS tkva_sum_consistency_flag,
    
        -- ============================================================
        -- REACTIVE POWER: kVAr1, kVAr2, kVAr3, TkVAr
        -- Any value allowed (leading/lagging) | TkVAr should ~= sum +-5%
        -- ============================================================
        (
            num_nonnulls(b.reactive_power_phase_1_kvar, b.reactive_power_phase_2_kvar, b.reactive_power_phase_3_kvar, b.reactive_power_total_kvar) = 4
            AND ABS(
                b.reactive_power_total_kvar
                - (b.reactive_power_phase_1_kvar + b.reactive_power_phase_2_kvar + b.reactive_power_phase_3_kvar)
            ) / NULLIF(ABS(b.reactive_power_phase_1_kvar + b.reactive_power_phase_2_kvar + b.reactive_power_phase_3_kvar), 0) * 100
            > b.consistency_tolerance_pct
        ) AS tkvar_sum_consistency_flag,
    
        -- ============================================================
        -- ACCUMULATED ENERGY: kWh, kVAh, kVArh
        -- Cannot decrement | Hard limit: 0 to user-defined max
        -- ============================================================
        (b.prev_kwh IS NOT NULL AND b.active_energy_cumulative_kwh < b.prev_kwh) AS kwh_decrement_flag,
        (b.active_energy_cumulative_kwh < 0 OR b.active_energy_cumulative_kwh > b.v_kwh_user_max) AS kwh_hard_limit_flag,
    
        (b.prev_kvah IS NOT NULL AND b.apparent_energy_cumulative_kvah < b.prev_kvah) AS kvah_decrement_flag,
        (b.apparent_energy_cumulative_kvah < 0 OR b.apparent_energy_cumulative_kvah > b.v_kvah_user_max) AS kvah_hard_limit_flag,
    
        (b.prev_kvarh IS NOT NULL AND b.reactive_energy_cumulative_kvarh < b.prev_kvarh) AS kvarh_decrement_flag,
        (b.reactive_energy_cumulative_kvarh < 0 OR b.reactive_energy_cumulative_kvarh > b.v_kvarh_user_max) AS kvarh_hard_limit_flag
    
    FROM base b;
