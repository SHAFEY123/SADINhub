-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- silver.agg_energy_3d
    -- Rolled up from silver.agg_energy_1d.
    -- 3-day buckets anchored to the epoch so they're consistent
    -- (day 0-2, 3-5, 6-8, ...) rather than drifting per meter.
    -- ============================================================
    
    CREATE TABLE IF NOT EXISTS silver.agg_energy_3d (
        energy_meter_key            uuid NOT NULL,
        facility_key                uuid,
        zone_key                    uuid,
        grid_billing_account_key    uuid,
        bucket_start_utc             timestamp without time zone NOT NULL,
    
        kwh_consumption              double precision,
        kvarh_consumption            double precision,
        kvah_consumption             double precision,
    
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
    
        avg_kva1 double precision, max_kva1 double precision,
        avg_kva2 double precision, max_kva2 double precision,
        avg_kva3 double precision, max_kva3 double precision,
        avg_tkva double precision, max_tkva double precision,
    
        avg_kvar1 double precision, max_kvar1 double precision,
        avg_kvar2 double precision, max_kvar2 double precision,
        avg_kvar3 double precision, max_kvar3 double precision,
        avg_tkvar double precision, max_tkvar double precision,
    
        reading_count                integer,
    
        status_vn1  text, status_vn2  text, status_vn3  text,
        status_v1   text, status_v2   text, status_v3   text,
        status_amp1 text, status_amp2 text, status_amp3 text,
        status_hz   text,
        status_pf1  text, status_pf2  text, status_pf3  text,
        status_kw1  text, status_kw2  text, status_kw3  text, status_tkw  text,
        status_kva1 text, status_kva2 text, status_kva3 text, status_tkva text,
        status_kvar1 text, status_kvar2 text, status_kvar3 text, status_tkvar text,
        overall_status text,
    
        loaded_at                    timestamp without time zone DEFAULT now(),
    
        PRIMARY KEY (energy_meter_key, bucket_start_utc)
    );
    
    INSERT INTO silver.agg_energy_3d (
        energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_start_utc,
        kwh_consumption, kvarh_consumption, kvah_consumption,
        avg_vn1, min_vn1, max_vn1, avg_vn2, min_vn2, max_vn2, avg_vn3, min_vn3, max_vn3,
        avg_v1, min_v1, max_v1, avg_v2, min_v2, max_v2, avg_v3, min_v3, max_v3,
        avg_amp1, max_amp1, avg_amp2, max_amp2, avg_amp3, max_amp3,
        avg_frequency_hz, min_frequency_hz, max_frequency_hz,
        avg_pf1, min_pf1, avg_pf2, min_pf2, avg_pf3, min_pf3,
        avg_kw1, max_kw1, avg_kw2, max_kw2, avg_kw3, max_kw3, avg_tkw, max_tkw,
        avg_kva1, max_kva1, avg_kva2, max_kva2, avg_kva3, max_kva3, avg_tkva, max_tkva,
        avg_kvar1, max_kvar1, avg_kvar2, max_kvar2, avg_kvar3, max_kvar3, avg_tkvar, max_tkvar,
        reading_count,
        status_vn1, status_vn2, status_vn3, status_v1, status_v2, status_v3,
        status_amp1, status_amp2, status_amp3, status_hz,
        status_pf1, status_pf2, status_pf3,
        status_kw1, status_kw2, status_kw3, status_tkw,
        status_kva1, status_kva2, status_kva3, status_tkva,
        status_kvar1, status_kvar2, status_kvar3, status_tkvar,
        overall_status
    )
    WITH last_loaded AS (
        SELECT COALESCE(MAX(bucket_start_utc), '1970-01-01'::timestamp) AS cutoff
        FROM silver.agg_energy_3d
    ),
    source AS (
        SELECT
            d.*,
            -- 3-day buckets anchored to epoch (day 0), so grouping is stable
            ('1970-01-01'::date + (floor((d.bucket_start_utc::date - '1970-01-01'::date) / 3) * 3))::timestamp AS bucket_3d
        FROM silver.agg_energy_1d d, last_loaded l
        WHERE d.bucket_start_utc > l.cutoff
    )
    SELECT
        energy_meter_key, facility_key, zone_key, grid_billing_account_key,
        bucket_3d,
    
        SUM(kwh_consumption), SUM(kvarh_consumption), SUM(kvah_consumption),
    
        SUM(avg_vn1 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_vn1), MAX(max_vn1),
        SUM(avg_vn2 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_vn2), MAX(max_vn2),
        SUM(avg_vn3 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_vn3), MAX(max_vn3),
    
        SUM(avg_v1 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_v1), MAX(max_v1),
        SUM(avg_v2 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_v2), MAX(max_v2),
        SUM(avg_v3 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_v3), MAX(max_v3),
    
        SUM(avg_amp1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_amp1),
        SUM(avg_amp2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_amp2),
        SUM(avg_amp3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_amp3),
    
        SUM(avg_frequency_hz * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_frequency_hz), MAX(max_frequency_hz),
    
        SUM(avg_pf1 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_pf1),
        SUM(avg_pf2 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_pf2),
        SUM(avg_pf3 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_pf3),
    
        SUM(avg_kw1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kw1),
        SUM(avg_kw2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kw2),
        SUM(avg_kw3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kw3),
        SUM(avg_tkw * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_tkw),
    
        SUM(avg_kva1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kva1),
        SUM(avg_kva2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kva2),
        SUM(avg_kva3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kva3),
        SUM(avg_tkva * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_tkva),
    
        SUM(avg_kvar1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kvar1),
        SUM(avg_kvar2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kvar2),
        SUM(avg_kvar3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kvar3),
        SUM(avg_tkvar * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_tkvar),
    
        SUM(reading_count)::integer,
    
        silver.worst_status(VARIADIC array_agg(status_vn1)),
        silver.worst_status(VARIADIC array_agg(status_vn2)),
        silver.worst_status(VARIADIC array_agg(status_vn3)),
        silver.worst_status(VARIADIC array_agg(status_v1)),
        silver.worst_status(VARIADIC array_agg(status_v2)),
        silver.worst_status(VARIADIC array_agg(status_v3)),
        silver.worst_status(VARIADIC array_agg(status_amp1)),
        silver.worst_status(VARIADIC array_agg(status_amp2)),
        silver.worst_status(VARIADIC array_agg(status_amp3)),
        silver.worst_status(VARIADIC array_agg(status_hz)),
        silver.worst_status(VARIADIC array_agg(status_pf1)),
        silver.worst_status(VARIADIC array_agg(status_pf2)),
        silver.worst_status(VARIADIC array_agg(status_pf3)),
        silver.worst_status(VARIADIC array_agg(status_kw1)),
        silver.worst_status(VARIADIC array_agg(status_kw2)),
        silver.worst_status(VARIADIC array_agg(status_kw3)),
        silver.worst_status(VARIADIC array_agg(status_tkw)),
        silver.worst_status(VARIADIC array_agg(status_kva1)),
        silver.worst_status(VARIADIC array_agg(status_kva2)),
        silver.worst_status(VARIADIC array_agg(status_kva3)),
        silver.worst_status(VARIADIC array_agg(status_tkva)),
        silver.worst_status(VARIADIC array_agg(status_kvar1)),
        silver.worst_status(VARIADIC array_agg(status_kvar2)),
        silver.worst_status(VARIADIC array_agg(status_kvar3)),
        silver.worst_status(VARIADIC array_agg(status_tkvar)),
        silver.worst_status(VARIADIC array_agg(overall_status))
    
    FROM source
    GROUP BY energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_3d
    ON CONFLICT (energy_meter_key, bucket_start_utc) DO NOTHING;
