-- Recovered from PostgreSQL server log postgresql-2026-08-09_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- silver.fact_energy_readings_snapshot (CORRECTED)
    --
    -- Combines the REAL measured values (from staging) with their
    -- quality status (from flagged) -- one row per actual reading,
    -- real timestamp, real number, plus its status flag. No
    -- averaging, no bucketing, nothing invented.
    --
    -- fact_energy_readings_flagged alone only has status_* columns,
    -- no actual values -- confirmed via information_schema. This
    -- version fixes that by joining back to fact_energy_readings_staging
    -- for the real numbers.
    --
    -- Full refresh (TRUNCATE + reload), same reasoning as before:
    -- flagged's spike-detection depends on reading order, so an
    -- incremental filter risks a wrong "previous reading" at the seam.
    -- ============================================================
    
    DROP TABLE IF EXISTS silver.fact_energy_readings_snapshot CASCADE;
    
    CREATE TABLE silver.fact_energy_readings_snapshot AS
    SELECT
        s.energy_meter_key, s.facility_key, s.zone_key, s.grid_billing_account_key,
        s.reading_timestamp_utc,
    
        -- Cumulative counters (real values, as reported)
        s.active_energy_cumulative_kwh,
        s.reactive_energy_cumulative_kvarh,
        s.apparent_energy_cumulative_kvah,
    
        -- Voltage (Line-to-Neutral)
        s.voltage_neutral_1_v, s.voltage_neutral_2_v, s.voltage_neutral_3_v,
    
        -- Voltage (Line-to-Line)
        s.voltage_line_1_v, s.voltage_line_2_v, s.voltage_line_3_v,
    
        -- Current
        s.current_phase_1_a, s.current_phase_2_a, s.current_phase_3_a,
    
        -- Frequency
        s.frequency_hz,
    
        -- Power Factor
        s.power_factor_phase_1, s.power_factor_phase_2, s.power_factor_phase_3, s.power_factor_average,
    
        -- Active Power
        s.active_power_phase_1_kw, s.active_power_phase_2_kw, s.active_power_phase_3_kw, s.active_power_total_kw,
    
        -- Apparent Power
        s.apparent_power_phase_1_kva, s.apparent_power_phase_2_kva, s.apparent_power_phase_3_kva, s.apparent_power_total_kva,
    
        -- Reactive Power
        s.reactive_power_phase_1_kvar, s.reactive_power_phase_2_kvar, s.reactive_power_phase_3_kvar, s.reactive_power_total_kvar,
    
        -- Quality status, per reading (from the flagged view)
        g.status_vn1, g.status_vn2, g.status_vn3, g.status_vna,
        g.status_v1, g.status_v2, g.status_v3, g.status_va,
        g.status_amp1, g.status_amp2, g.status_amp3, g.status_ampa,
        g.status_hz,
        g.status_pf1, g.status_pf2, g.status_pf3, g.status_pfa,
        g.status_kw1, g.status_kw2, g.status_kw3, g.status_tkw,
        g.status_kva1, g.status_kva2, g.status_kva3, g.status_tkva,
        g.status_kvar1, g.status_kvar2, g.status_kvar3, g.status_tkvar,
        g.status_kwh, g.status_kvah, g.status_kvarh,
        g.overall_status
    
    FROM silver.fact_energy_readings_staging s
    JOIN silver.fact_energy_readings_flagged g
        ON g.energy_meter_key = s.energy_meter_key
       AND g.reading_timestamp_utc = s.reading_timestamp_utc;
    
    ALTER TABLE silver.fact_energy_readings_snapshot
        ADD CONSTRAINT pk_energy_readings_snapshot
        PRIMARY KEY (energy_meter_key, reading_timestamp_utc);
