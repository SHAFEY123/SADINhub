-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

-- =============================================================================
    -- measurement_value_consistency_audit.sql
    -- =============================================================================
    -- PURPOSE
    --   Read-only audit of measurement *values* (not cadence/completeness, which
    --   are already covered by the Silver DQ materialized views). Checks whether
    --   electrical readings in the energy fact are physically plausible and
    --   internally consistent, ahead of loading Gold.
    --
    -- SCOPE
    --   1. Hard physical-range violations (power factor, negative magnitudes,
    --      implausible frequency)
    --   2. Non-monotonic cumulative registers (kWh / kVAh / kVArh going backwards)
    --   3. Statistical spikes in active power (TkW) relative to each meter's own
    --      typical delta -- not a fixed threshold, since normal load size varies
    --      a lot by meter
    --   4. Phase imbalance / partial phase dropout across V1/V2/V3
    --
    -- THIS SCRIPT DOES NOT MODIFY DATA.
    --   No INSERT / UPDATE / DELETE / CREATE TABLE. Safe to run against Bronze,
    --   Silver, or a replica at any time -- same discipline as your other
    --   verify_*.sql / audit_*.sql scripts.
    --
    -- SCHEMA ASSUMPTIONS -- verify against create_silver_star_schema_staging_views.sql
    --   silver.fact_energy_readings_staging
    --       energy_meter_key       -- FK to dim_energy_meter_staging
    --       reading_timestamp_utc  -- converted from source epoch ms
    --       v1, v2, v3, va, amp1, amp2, amp3, ampa, hz,
    --       pf1, pf2, pf3, pfa, tkw, tkva, tkvar, kwh, kvah, kvarh
    --   silver.dim_energy_meter_staging
    --       energy_meter_key, meter_name, zone_key
    --   silver.dim_zone_staging
    --       zone_key, zone_name
    --   Column names here are lowercase/unquoted (Postgres default folding). If
    --   your view was created with quoted, case-preserving names (e.g. "V1",
    --   "TkW"), find/replace to match -- Postgres is case-sensitive for quoted
    --   identifiers. Also confirm reading_timestamp_utc's exact type (timestamp
    --   vs timestamptz) and adjust the literals in the params CTE if needed.
    --
    -- PERFORMANCE NOTE
    --   fact_energy_readings_staging is an ordinary (unmaterialized) view over a
    --   large source -- per the earlier slow-query finding, date_key is
    --   calculated rather than indexed. Start with a narrow window (default: one
    --   week) and, per that same lesson, uncomment the single-meter filter below
    --   before widening the date range. Once this logic is validated, consider
    --   materializing it as silver.dq_measurement_validity_staging, mirroring
    --   the existing dq_* pattern.
    -- =============================================================================
    
    
    -- ---------------------------------------------------------------------------
    -- 0. Parameters -- edit before running
    -- ---------------------------------------------------------------------------
    WITH params AS (
        SELECT
            '2025-03-01'::timestamptz AS window_start,               -- inclusive
            '2025-03-08'::timestamptz AS window_end,                 -- exclusive
            0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
            5.0                        AS spike_zscore_threshold            -- std devs
    ),
    
    -- ---------------------------------------------------------------------------
    -- 1. Base reading set for the window, with meter/zone context
    -- ---------------------------------------------------------------------------
    base_readings AS (
        SELECT
            f.energy_meter_key,
            m.meter_name,
            z.zone_name,
            f.reading_timestamp_utc,
            f.v1, f.v2, f.v3, f.va,
            f.amp1, f.amp2, f.amp3, f.ampa,
            f.hz,
            f.pf1, f.pf2, f.pf3, f.pfa,
            f.tkw, f.tkva, f.tkvar,
            f.kwh, f.kvah, f.kvarh
        FROM silver.fact_energy_readings_staging f
        INNER JOIN silver.dim_energy_meter_staging m
            ON m.energy_meter_key = f.energy_meter_key
        INNER JOIN silver.dim_zone_staging z
            ON z.zone_key = m.zone_key
        CROSS JOIN params p
        WHERE f.reading_timestamp_utc >= p.window_start
          AND f.reading_timestamp_utc <  p.window_end
          -- Uncomment to debug a single meter first, per the earlier slow-query lesson:
          -- AND f.energy_meter_key = 123
    ),
    
    -- ---------------------------------------------------------------------------
    -- 2. Hard physical-range violations
    --    Power factor must fall within [-1, 1] regardless of system. Current,
    --    apparent power, and frequency are magnitude-type measurements and
    --    should never be negative.
    -- ---------------------------------------------------------------------------
    range_violations AS (
        SELECT
            b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
            'PF_OUT_OF_RANGE' AS issue_type,
            format('pf1=%s pf2=%s pf3=%s pfa=%s', b.pf1, b.pf2, b.pf3, b.pfa) AS detail
        FROM base_readings b
        WHERE b.pf1 NOT BETWEEN -1 AND 1
           OR b.pf2 NOT BETWEEN -1 AND 1
           OR b.pf3 NOT BETWEEN -1 AND 1
           OR b.pfa NOT BETWEEN -1 AND 1
    
        UNION ALL
    
        SELECT
            b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
            'NEGATIVE_MAGNITUDE_VALUE',
            format('amp1=%s amp2=%s amp3=%s tkva=%s', b.amp1, b.amp2, b.amp3, b.tkva)
        FROM base_readings b
        WHERE b.amp1 < 0 OR b.amp2 < 0 OR b.amp3 < 0 OR b.ampa < 0
           OR b.tkva < 0
    
        UNION ALL
    
        SELECT
            b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
            'FREQUENCY_OUT_OF_BAND',
            format('hz=%s', b.hz)
        FROM base_readings b
        -- Loose sanity band covering both 50Hz and 60Hz grids.
        -- Tighten to your actual nominal frequency once confirmed with the team
        -- (e.g. 59-61 for a 60Hz grid).
        WHERE b.hz IS NOT NULL
          AND b.hz NOT BETWEEN 45 AND 65
    ),
    
    -- ---------------------------------------------------------------------------
    -- 3. Non-monotonic cumulative registers (kWh / kVAh / kVArh)
    --    These should only increase, except at a legitimate meter reset/rollover.
    --    A large drop close to zero looks like a rollover; a small drop looks
    --    like a data error and needs manual review. This mirrors the open
    --    "resets/rollovers" business rule already flagged as unconfirmed.
    -- ---------------------------------------------------------------------------
    register_deltas AS (
        SELECT
            b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
            b.kwh,
            LAG(b.kwh) OVER (
                PARTITION BY b.energy_meter_key ORDER BY b.reading_timestamp_utc
            ) AS prev_kwh
        FROM base_readings b
    ),
    register_violations AS (
        SELECT
            rd.energy_meter_key, rd.meter_name, rd.zone_name, rd.reading_timestamp_utc,
            CASE
                WHEN rd.kwh < rd.prev_kwh * 0.1 THEN 'LIKELY_ROLLOVER_OR_RESET'
                ELSE 'KWH_DECREASE_ANOMALY'
            END AS issue_type,
            format('prev_kwh=%s new_kwh=%s', rd.prev_kwh, rd.kwh) AS detail
        FROM register_deltas rd
        WHERE rd.prev_kwh IS NOT NULL
          AND rd.kwh < rd.prev_kwh
    ),
    
    -- ---------------------------------------------------------------------------
    -- 4. Active-power (TkW) spikes relative to each meter's own typical delta
    --    Uses each meter's own delta distribution rather than a fixed threshold,
    --    since normal load levels vary a lot by meter.
    -- ---------------------------------------------------------------------------
    power_deltas AS (
        SELECT
            b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
            b.tkw - LAG(b.tkw) OVER (
                PARTITION BY b.energy_meter_key ORDER BY b.reading_timestamp_utc
            ) AS delta_tkw
        FROM base_readings b
    ),
    power_delta_stats AS (
        SELECT
            energy_meter_key,
            AVG(delta_tkw)         AS mean_delta,
            STDDEV_SAMP(delta_tkw) AS stddev_delta
        FROM power_deltas
        WHERE delta_tkw IS NOT NULL
        GROUP BY energy_meter_key
        HAVING STDDEV_SAMP(delta_tkw) > 0   -- avoid divide-by-zero for flat meters
    ),
    power_spikes AS (
        SELECT
            pd.energy_meter_key, pd.meter_name, pd.zone_name, pd.reading_timestamp_utc,
            'TKW_SPIKE' AS issue_type,
            format(
                'delta=%s zscore=%s',
                pd.delta_tkw,
                -- Cast to numeric before ROUND -- ROUND(double precision, int)
                -- doesn't exist in Postgres, per the earlier cadence-query fix.
                ROUND(((pd.delta_tkw - s.mean_delta) / s.stddev_delta)::numeric, 2)
            ) AS detail
        FROM power_deltas pd
        INNER JOIN power_delta_stats s
            ON s.energy_meter_key = pd.energy_meter_key
        CROSS JOIN params p
        WHERE pd.delta_tkw IS NOT NULL
          AND ABS((pd.delta_tkw - s.mean_delta) / s.stddev_delta) > p.spike_zscore_threshold
    ),
    
    -- ---------------------------------------------------------------------------
    -- 5. Phase imbalance and partial phase dropout across V1/V2/V3
    --    A healthy 3-phase reading has similar voltage on all phases. A phase at
    --    near-zero while the others are normal suggests a partial-packet issue,
    --    the same pattern already diagnosed for Zone 17.
    -- ---------------------------------------------------------------------------
    phase_checks AS (
        SELECT
            b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
            GREATEST(b.v1, b.v2, b.v3) AS max_v,
            LEAST(b.v1, b.v2, b.v3)    AS min_v
        FROM base_readings b
        WHERE b.v1 IS NOT NULL AND b.v2 IS NOT NULL AND b.v3 IS NOT NULL
    ),
    phase_violations AS (
        SELECT
            pc.energy_meter_key, pc.meter_name, pc.zone_name, pc.reading_timestamp_utc,
            CASE
                WHEN pc.min_v < 5 AND pc.max_v > 50 THEN 'PARTIAL_PHASE_DROPOUT'
                ELSE 'PHASE_IMBALANCE'
            END AS issue_type,
            format('min_v=%s max_v=%s', pc.min_v, pc.max_v) AS detail
        FROM phase_checks pc
        CROSS JOIN params p
        WHERE (pc.min_v < 5 AND pc.max_v > 50)
           OR (pc.min_v > 0 AND (pc.max_v - pc.min_v) / pc.min_v > p.phase_imbalance_ratio_threshold)
    ),
    
    -- ---------------------------------------------------------------------------
    -- 6. Combine all issue types into one result set
    -- ---------------------------------------------------------------------------
    all_issues AS (
        SELECT * FROM range_violations
        UNION ALL
        SELECT * FROM register_violations
        UNION ALL
        SELECT * FROM power_spikes
        UNION ALL
        SELECT * FROM phase_violations
    )
    
    -- =============================================================================
    -- SECTION A (default): detailed flagged rows -- run this first
    -- =============================================================================
    SELECT *
    FROM all_issues
    ORDER BY zone_name, meter_name, reading_timestamp_utc;
    
    -- =============================================================================
    -- SECTION B: prioritized rollup -- comment out Section A above and use this
    -- instead once you want counts per meter/issue type rather than raw rows.
    -- (Wrap the whole statement above, params through all_issues, as a subquery.)
    -- =============================================================================
    -- SELECT zone_name, meter_name, issue_type, COUNT(*) AS issue_count
    -- FROM ( <paste the WITH ... all_issues block and SELECT * FROM all_issues here> ) t
    -- GROUP BY zone_name, meter_name, issue_type
    -- ORDER BY issue_count DESC;
