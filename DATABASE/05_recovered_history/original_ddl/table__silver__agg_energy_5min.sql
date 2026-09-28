-- Recovered from PostgreSQL server log postgresql-2026-08-09_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- silver.agg_energy_5min
    --
    -- Identical structure and logic to silver.agg_energy_30min --
    -- raw scan of silver.fact_energy_readings_staging, cumulative
    -- counters (kWh, kVArh) as sum-of-positive-deltas, everything
    -- else as AVG/MIN/MAX, apparent-power family excluded (confirmed
    -- empty facility-wide). Only difference: 5-minute buckets instead
    -- of 30-minute ones.
    --
    -- EXPECTED SHAPE: since raw readings arrive roughly every 5
    -- minutes already, most buckets will contain exactly 1 reading,
    -- so avg = min = max in most rows. Buckets with a real gap in
    -- that window simply won't produce a row (same behavior as every
    -- other grain -- no row is emitted for a bucket with zero
    -- readings). Occasional buckets may show reading_count = 2 if two
    -- readings land inside the same 5-minute window due to timing
    -- jitter in the source telemetry.
    --
    -- Safe to re-run repeatedly (incremental load).
    -- ============================================================
    
    CREATE TABLE IF NOT EXISTS silver.agg_energy_5min (
        energy_meter_key            uuid NOT NULL,
        facility_key                uuid,
        zone_key                    uuid,
        grid_billing_account_key    uuid,
        bucket_start_utc             timestamp without time zone NOT NULL,
    
        kwh_consumption              double precision,
        kvarh_consumption            double precision,
    
        avg_vn1 double precision, min_vn1 double precision, max_vn1 double precision,
        avg_vn2 double precision, min_vn2 double precision, max_vn2 double precision,
        avg_vn3 double precision, min_vn3 double precision, max_vn3 double precision,
    
        avg_v1 double precision, min_v1 double precision, max_v1 double precision,
        avg_v2 double precision, min_v2 double precision, max_v2 double precision,
        avg_v3 double precision, min_v3 double precision, max_v3 double precision,
    
        avg_amp1 double precision, max_amp1 double precision,
        avg_amp2 double precision, max_amp2 double precision,
        avg_amp3 double precision, max_amp3 double precision,
    
        avg_frequency_hz double precision, min_frequency_hz double precision, max_frequency_hz double precision,
    
        avg_pf1 double precision, min_pf1 double precision,
        avg_pf2 double precision, min_pf2 double precision,
        avg_pf3 double precision, min_pf3 double precision,
    
        avg_kw1 double precision, max_kw1 double precision,
        avg_kw2 double precision, max_kw2 double precision,
        avg_kw3 double precision, max_kw3 double precision,
        avg_tkw double precision, max_tkw double precision,
    
        avg_kvar1 double precision, max_kvar1 double precision,
        avg_kvar2 double precision, max_kvar2 double precision,
        avg_kvar3 double precision, max_kvar3 double precision,
        avg_tkvar double precision, max_tkvar double precision,
    
        reading_count                integer,
        loaded_at                    timestamp without time zone DEFAULT now(),
    
        PRIMARY KEY (energy_meter_key, bucket_start_utc)
    );
    
    -- ============================================================
    -- Incremental load
    -- ============================================================
    
    INSERT INTO silver.agg_energy_5min (
        energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_start_utc,
        kwh_consumption, kvarh_consumption,
        avg_vn1, min_vn1, max_vn1, avg_vn2, min_vn2, max_vn2, avg_vn3, min_vn3, max_vn3,
        avg_v1, min_v1, max_v1, avg_v2, min_v2, max_v2, avg_v3, min_v3, max_v3,
        avg_amp1, max_amp1, avg_amp2, max_amp2, avg_amp3, max_amp3,
        avg_frequency_hz, min_frequency_hz, max_frequency_hz,
        avg_pf1, min_pf1, avg_pf2, min_pf2, avg_pf3, min_pf3,
        avg_kw1, max_kw1, avg_kw2, max_kw2, avg_kw3, max_kw3, avg_tkw, max_tkw,
        avg_kvar1, max_kvar1, avg_kvar2, max_kvar2, avg_kvar3, max_kvar3, avg_tkvar, max_tkvar,
        reading_count
    )
    WITH last_loaded AS (
        SELECT COALESCE(MAX(bucket_start_utc), '1970-01-01'::timestamp) AS cutoff
        FROM silver.agg_energy_5min
    ),
    base AS (
        SELECT f.*
        FROM silver.fact_energy_readings_staging f, last_loaded l
        WHERE f.reading_timestamp_utc > l.cutoff
    ),
    deltas AS (
        SELECT
            *,
            GREATEST(active_energy_cumulative_kwh
                - LAG(active_energy_cumulative_kwh) OVER (PARTITION BY energy_meter_key ORDER BY reading_timestamp_utc), 0) AS kwh_delta,
            GREATEST(reactive_energy_cumulative_kvarh
                - LAG(reactive_energy_cumulative_kvarh) OVER (PARTITION BY energy_meter_key ORDER BY reading_timestamp_utc), 0) AS kvarh_delta
        FROM base
    ),
    bucketed AS (
        SELECT
            *,
            date_trunc('hour', reading_timestamp_utc)
                + (floor(extract(minute FROM reading_timestamp_utc) / 5.0)::int * interval '5 minutes') AS bucket_start_utc
        FROM deltas
    )
    SELECT
        energy_meter_key, facility_key, zone_key, grid_billing_account_key,
        bucket_start_utc,
    
        SUM(kwh_delta)   AS kwh_consumption,
        SUM(kvarh_delta) AS kvarh_consumption,
    
        AVG(voltage_neutral_1_v), MIN(voltage_neutral_1_v), MAX(voltage_neutral_1_v),
        AVG(voltage_neutral_2_v), MIN(voltage_neutral_2_v), MAX(voltage_neutral_2_v),
        AVG(voltage_neutral_3_v), MIN(voltage_neutral_3_v), MAX(voltage_neutral_3_v),
    
        AVG(voltage_line_1_v), MIN(voltage_line_1_v), MAX(voltage_line_1_v),
        AVG(voltage_line_2_v), MIN(voltage_line_2_v), MAX(voltage_line_2_v),
        AVG(voltage_line_3_v), MIN(voltage_line_3_v), MAX(voltage_line_3_v),
    
        AVG(current_phase_1_a), MAX(current_phase_1_a),
        AVG(current_phase_2_a), MAX(current_phase_2_a),
        AVG(current_phase_3_a), MAX(current_phase_3_a),
    
        AVG(frequency_hz), MIN(frequency_hz), MAX(frequency_hz),
    
        AVG(power_factor_phase_1), MIN(power_factor_phase_1),
        AVG(power_factor_phase_2), MIN(power_factor_phase_2),
        AVG(power_factor_phase_3), MIN(power_factor_phase_3),
    
        AVG(active_power_phase_1_kw), MAX(active_power_phase_1_kw),
        AVG(active_power_phase_2_kw), MAX(active_power_phase_2_kw),
        AVG(active_power_phase_3_kw), MAX(active_power_phase_3_kw),
        AVG(active_power_total_kw),   MAX(active_power_total_kw),
    
        AVG(reactive_power_phase_1_kvar), MAX(reactive_power_phase_1_kvar),
        AVG(reactive_power_phase_2_kvar), MAX(reactive_power_phase_2_kvar),
        AVG(reactive_power_phase_3_kvar), MAX(reactive_power_phase_3_kvar),
        AVG(reactive_power_total_kvar),   MAX(reactive_power_total_kvar),
    
        COUNT(*) AS reading_count
    
    FROM bucketed
    GROUP BY energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_start_utc
    ON CONFLICT (energy_meter_key, bucket_start_utc) DO NOTHING;
