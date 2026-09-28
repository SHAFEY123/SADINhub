-- Recovered from PostgreSQL server log postgresql-2026-08-10_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- Rebuild silver.fact_energy_readings_snapshot with corrected
    -- statuses. Also fixes the earlier oversight: this version
    -- includes voltage_line_average_v and voltage_neutral_average_v
    -- as real value columns (even though they're NULL for every
    -- meter, they belong in the raw data for completeness).
    -- ============================================================
    
    DROP TABLE IF EXISTS silver.fact_energy_readings_snapshot CASCADE;
    
    CREATE TABLE silver.fact_energy_readings_snapshot AS
    SELECT
        s.energy_meter_key, s.facility_key, s.zone_key, s.grid_billing_account_key,
        s.reading_timestamp_utc,
    
        s.active_energy_cumulative_kwh,
        s.reactive_energy_cumulative_kvarh,
        s.apparent_energy_cumulative_kvah,
    
        s.voltage_neutral_1_v, s.voltage_neutral_2_v, s.voltage_neutral_3_v, s.voltage_neutral_average_v,
        s.voltage_line_1_v, s.voltage_line_2_v, s.voltage_line_3_v, s.voltage_line_average_v,
    
        s.current_phase_1_a, s.current_phase_2_a, s.current_phase_3_a,
    
        s.frequency_hz,
    
        s.power_factor_phase_1, s.power_factor_phase_2, s.power_factor_phase_3, s.power_factor_average,
    
        s.active_power_phase_1_kw, s.active_power_phase_2_kw, s.active_power_phase_3_kw, s.active_power_total_kw,
        s.apparent_power_phase_1_kva, s.apparent_power_phase_2_kva, s.apparent_power_phase_3_kva, s.apparent_power_total_kva,
        s.reactive_power_phase_1_kvar, s.reactive_power_phase_2_kvar, s.reactive_power_phase_3_kvar, s.reactive_power_total_kvar,
    
        g.status_vn1, g.status_vn2, g.status_vn3,
        g.status_v1, g.status_v2, g.status_v3,
        g.status_amp1, g.status_amp2, g.status_amp3,
        g.status_hz,
        g.status_pf1, g.status_pf2, g.status_pf3, g.status_pfa,
        g.status_kwh,
        g.overall_status
    
    FROM silver.fact_energy_readings_staging s
    JOIN silver.fact_energy_readings_flagged g
        ON g.energy_meter_key = s.energy_meter_key
       AND g.reading_timestamp_utc = s.reading_timestamp_utc;
    
    ALTER TABLE silver.fact_energy_readings_snapshot
        ADD CONSTRAINT pk_energy_readings_snapshot
        PRIMARY KEY (energy_meter_key, reading_timestamp_utc);
    
    -- Quick check -- reference meter, one hour, should show real
    -- corrected statuses and no more constant Invalid
    SELECT reading_timestamp_utc, status_vn1, status_pf1, status_amp1, status_kwh, overall_status
    FROM silver.fact_energy_readings_snapshot
    WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
      AND reading_timestamp_utc >= '2025-07-01' AND reading_timestamp_utc < '2025-07-01 01:00:00'
    ORDER BY reading_timestamp_utc;
