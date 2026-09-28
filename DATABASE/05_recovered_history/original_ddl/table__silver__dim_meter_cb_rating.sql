-- Recovered from PostgreSQL server log postgresql-2026-08-10_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- ============================================================
    -- silver.dim_meter_cb_rating
    -- Per-meter circuit breaker max rating, needed for Current
    -- classification (each meter has its own CB rating, unlike
    -- every other metric which uses one fixed threshold facility-wide).
    -- ============================================================
    
    CREATE TABLE IF NOT EXISTS silver.dim_meter_cb_rating (
        energy_meter_key    uuid PRIMARY KEY REFERENCES silver.dim_energy_meter_staging(energy_meter_key),
        cb_max_rating_a      double precision NOT NULL,
        updated_at           timestamp without time zone DEFAULT now()
    );
    
    -- Populate using meter_label to look up the real energy_meter_key,
    -- so we don't have to hand-type 31 UUIDs. The two name corrections
    -- already confirmed: 'ZN.20-PB' -> 'ZN.20-PB.1', 'ZN.21-PB.1' -> 'ZN.21-PB'.
    
    INSERT INTO silver.dim_meter_cb_rating (energy_meter_key, cb_max_rating_a)
    SELECT d.energy_meter_key, v.cb_max_rating_a
    FROM (VALUES
        ('ZN.1-PB.1_child__1_ch3pm',  100),
        ('ZN.1-PB.2_child__1_ch3pm',  100),
        ('ZN.2-PB_child__1_ch3pm',    100),
        ('ZN.3-PB.1_child__1_ch3pm',  100),
        ('ZN.3-PB.2_child__1_ch3pm',  100),
        ('ZN.4-PB.1_child__1_ch3pm',  100),
        ('ZN.4-PB.2_child__1_ch3pm',  125),
        ('ZN.5-PB_child__1_ch3pm',    100),
        ('ZN.6-PB_child__1_ch3pm',    250),
        ('ZN.7-PB_child__1_ch3pm',    250),
        ('ZN.8-PB.1_child__1_ch3pm',  160),
        ('ZN.8-PB.2_child__1_ch3pm',  160),
        ('ZN.9-PB_child__1_ch3pm',    250),
        ('ZN.10-PB.1_child__1_ch3pm', 80),
        ('ZN.10-PB.2_child__1_ch3pm', 80),
        ('ZN.11-PB.1_child__1_ch3pm', 80),
        ('ZN.11-PB.2_child__1_ch3pm', 80),
        ('ZN.12-PB_child__1_ch3pm',   100),
        ('ZN.13-PB.1_child__1_ch3pm', 125),
        ('ZN.13-PB.2_child__1_ch3pm', 125),
        ('ZN.14-PB_child__1_ch3pm',   80),
        ('ZN.15-PB.1_child__1_ch3pm', 125),
        ('ZN.15-PB.2_child__1_ch3pm', 250),
        ('ZN.16-PB_child__1_ch3pm',   200),
        ('ZN.17-PB_child__1_ch3pm',   250),
        ('ZN.18-PB_child__1_ch3pm',   100),
        ('ZN.19-PB.1_child__1_ch3pm', 160),
        ('ZN.19-PB.2_child__1_ch3pm', 250),
        ('ZN.20-PB.1_child__1_ch3pm', 100),  -- was 'ZN.20-PB' in source
        ('ZN.20-PB.2_child__1_ch3pm', 100),
        ('ZN.21-PB_child__1_ch3pm',   100)   -- was 'ZN.21-PB.1' in source
    ) AS v(meter_label, cb_max_rating_a)
    JOIN silver.dim_energy_meter_staging d ON d.meter_label = v.meter_label
    ON CONFLICT (energy_meter_key) DO UPDATE SET
        cb_max_rating_a = EXCLUDED.cb_max_rating_a,
        updated_at = now();
    
    -- Sanity check: should return exactly 31 rows, and the "missing"
    -- query right below it should return 0 rows (every canonical
    -- meter has a CB rating).
    SELECT COUNT(*) AS cb_ratings_loaded FROM silver.dim_meter_cb_rating;
    
    SELECT d.meter_label
    FROM silver.dim_energy_meter_staging d
    LEFT JOIN silver.dim_meter_cb_rating cb ON cb.energy_meter_key = d.energy_meter_key
    WHERE cb.energy_meter_key IS NULL;
