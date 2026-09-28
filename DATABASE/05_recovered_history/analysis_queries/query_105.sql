-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

SELECT
        energy_meter_key,
        reading_timestamp_utc,
    
        voltage_neutral_1_v,
        vn1_hard_limit_flag,
        vn1_acceptable_range_flag,
        vn1_high_spike_flag,
    
        current_phase_1_a,
        amp1_hard_limit_flag,
    
        active_power_phase_1_kw,
        active_power_phase_2_kw,
        active_power_phase_3_kw,
        active_power_total_kw,
        tkw_sum_consistency_flag,
    
        active_energy_cumulative_kwh,
        kwh_decrement_flag
    
    FROM silver.fact_energy_readings_flagged
    
    WHERE energy_meter_key =
          'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
    
      AND reading_timestamp_utc >=
          TIMESTAMP '2025-07-01 00:00:00'
    
      AND reading_timestamp_utc <
          TIMESTAMP '2025-07-02 00:00:00'
    
    ORDER BY reading_timestamp_utc;
