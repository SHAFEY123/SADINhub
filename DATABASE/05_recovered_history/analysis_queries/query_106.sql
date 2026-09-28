-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- Add status columns to silver.agg_energy_4h
    --
    -- Rolled up from silver.agg_energy_1h using worst_status() --
    -- a 4-hour block inherits the WORST status any of its 4
    -- component hours had, per metric.
    -- ============================================================
    
    ALTER TABLE silver.agg_energy_4h
        ADD COLUMN IF NOT EXISTS status_vn1  text,
        ADD COLUMN IF NOT EXISTS status_vn2  text,
        ADD COLUMN IF NOT EXISTS status_vn3  text,
        ADD COLUMN IF NOT EXISTS status_v1   text,
        ADD COLUMN IF NOT EXISTS status_v2   text,
        ADD COLUMN IF NOT EXISTS status_v3   text,
        ADD COLUMN IF NOT EXISTS status_amp1 text,
        ADD COLUMN IF NOT EXISTS status_amp2 text,
        ADD COLUMN IF NOT EXISTS status_amp3 text,
        ADD COLUMN IF NOT EXISTS status_hz   text,
        ADD COLUMN IF NOT EXISTS status_pf1  text,
        ADD COLUMN IF NOT EXISTS status_pf2  text,
        ADD COLUMN IF NOT EXISTS status_pf3  text,
        ADD COLUMN IF NOT EXISTS status_kw1  text,
        ADD COLUMN IF NOT EXISTS status_kw2  text,
        ADD COLUMN IF NOT EXISTS status_kw3  text,
        ADD COLUMN IF NOT EXISTS status_tkw  text,
        ADD COLUMN IF NOT EXISTS status_kva1 text,
        ADD COLUMN IF NOT EXISTS status_kva2 text,
        ADD COLUMN IF NOT EXISTS status_kva3 text,
        ADD COLUMN IF NOT EXISTS status_tkva text,
        ADD COLUMN IF NOT EXISTS status_kvar1 text,
        ADD COLUMN IF NOT EXISTS status_kvar2 text,
        ADD COLUMN IF NOT EXISTS status_kvar3 text,
        ADD COLUMN IF NOT EXISTS status_tkvar text,
        ADD COLUMN IF NOT EXISTS overall_status text;
    
    -- Roll up worst-case status per metric from the 4 hourly rows in each block
    WITH rolled_up AS (
        SELECT
            h.energy_meter_key,
            date_trunc('day', h.bucket_start_utc)
                + (floor(extract(hour FROM h.bucket_start_utc) / 4) * interval '4 hour') AS bucket_4h,
    
            silver.worst_status(VARIADIC array_agg(h.status_vn1))  AS status_vn1,
            silver.worst_status(VARIADIC array_agg(h.status_vn2))  AS status_vn2,
            silver.worst_status(VARIADIC array_agg(h.status_vn3))  AS status_vn3,
            silver.worst_status(VARIADIC array_agg(h.status_v1))   AS status_v1,
            silver.worst_status(VARIADIC array_agg(h.status_v2))   AS status_v2,
            silver.worst_status(VARIADIC array_agg(h.status_v3))   AS status_v3,
            silver.worst_status(VARIADIC array_agg(h.status_amp1)) AS status_amp1,
            silver.worst_status(VARIADIC array_agg(h.status_amp2)) AS status_amp2,
            silver.worst_status(VARIADIC array_agg(h.status_amp3)) AS status_amp3,
            silver.worst_status(VARIADIC array_agg(h.status_hz))   AS status_hz,
            silver.worst_status(VARIADIC array_agg(h.status_pf1))  AS status_pf1,
            silver.worst_status(VARIADIC array_agg(h.status_pf2))  AS status_pf2,
            silver.worst_status(VARIADIC array_agg(h.status_pf3))  AS status_pf3,
            silver.worst_status(VARIADIC array_agg(h.status_kw1))  AS status_kw1,
            silver.worst_status(VARIADIC array_agg(h.status_kw2))  AS status_kw2,
            silver.worst_status(VARIADIC array_agg(h.status_kw3))  AS status_kw3,
            silver.worst_status(VARIADIC array_agg(h.status_tkw))  AS status_tkw,
            silver.worst_status(VARIADIC array_agg(h.status_kva1)) AS status_kva1,
            silver.worst_status(VARIADIC array_agg(h.status_kva2)) AS status_kva2,
            silver.worst_status(VARIADIC array_agg(h.status_kva3)) AS status_kva3,
            silver.worst_status(VARIADIC array_agg(h.status_tkva)) AS status_tkva,
            silver.worst_status(VARIADIC array_agg(h.status_kvar1)) AS status_kvar1,
            silver.worst_status(VARIADIC array_agg(h.status_kvar2)) AS status_kvar2,
            silver.worst_status(VARIADIC array_agg(h.status_kvar3)) AS status_kvar3,
            silver.worst_status(VARIADIC array_agg(h.status_tkvar)) AS status_tkvar,
            silver.worst_status(VARIADIC array_agg(h.overall_status)) AS overall_status
        FROM silver.agg_energy_1h h
        GROUP BY h.energy_meter_key,
                 date_trunc('day', h.bucket_start_utc)
                    + (floor(extract(hour FROM h.bucket_start_utc) / 4) * interval '4 hour')
    )
    UPDATE silver.agg_energy_4h a
    SET
        status_vn1 = r.status_vn1, status_vn2 = r.status_vn2, status_vn3 = r.status_vn3,
        status_v1 = r.status_v1, status_v2 = r.status_v2, status_v3 = r.status_v3,
        status_amp1 = r.status_amp1, status_amp2 = r.status_amp2, status_amp3 = r.status_amp3,
        status_hz = r.status_hz,
        status_pf1 = r.status_pf1, status_pf2 = r.status_pf2, status_pf3 = r.status_pf3,
        status_kw1 = r.status_kw1, status_kw2 = r.status_kw2, status_kw3 = r.status_kw3, status_tkw = r.status_tkw,
        status_kva1 = r.status_kva1, status_kva2 = r.status_kva2, status_kva3 = r.status_kva3, status_tkva = r.status_tkva,
        status_kvar1 = r.status_kvar1, status_kvar2 = r.status_kvar2, status_kvar3 = r.status_kvar3, status_tkvar = r.status_tkvar,
        overall_status = r.overall_status
    FROM rolled_up r
    WHERE a.energy_meter_key = r.energy_meter_key
      AND a.bucket_start_utc = r.bucket_4h
      AND a.overall_status IS NULL;  -- only backfill unclassified rows, safe to re-run
