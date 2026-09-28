-- pgAdmin 4 query history, decoded from pgadmin4.db
-- Only currently retained queries for sadinhub are exported.
-- This is partial history, not a complete record or a rebuild script.
-- Kept because these queries document how the data was investigated.
-- 20 entries recovered.

-- ==========================================================================
-- 2026-09-03T12:41:20.375Z  database=sadinhub  succeeded=True  rows=38
-- ==========================================================================
WITH readings AS (
    SELECT
        energy_meter_key,
        reading_timestamp_utc,
        active_energy_cumulative_kwh,

        LAG(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_kwh,

        LAG(active_energy_cumulative_kwh, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_kwh,

        LAG(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_timestamp_utc,

        LAG(reading_timestamp_utc, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_timestamp_utc,

        LEAD(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_kwh,

        LEAD(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_timestamp_utc

    FROM silver.fact_energy_readings_snapshot

    WHERE energy_meter_key IN (
        'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2',
        '9fc6d98a-5c79-48df-abd5-c0a21e61f40c'
    )

    AND active_energy_cumulative_kwh IS NOT NULL
),

stats AS (
    SELECT
        energy_meter_key,

        PERCENTILE_CONT(0.99)
        WITHIN GROUP (
            ORDER BY active_energy_cumulative_kwh - previous_kwh
        ) FILTER (
            WHERE active_energy_cumulative_kwh > previous_kwh
        ) AS p99_positive_change

    FROM readings

    GROUP BY energy_meter_key
),

drops AS (
    SELECT
        r.*,
        s.p99_positive_change,

        previous_kwh - active_energy_cumulative_kwh
            AS drop_size_kwh

    FROM readings r

    JOIN stats s
        ON s.energy_meter_key = r.energy_meter_key

    WHERE active_energy_cumulative_kwh < previous_kwh
),

classified AS (
    SELECT
        d.*,

        recovery.return_timestamp_utc,
        recovery.return_from_kwh,
        recovery.return_to_kwh

    FROM drops d

    LEFT JOIN LATERAL (

        SELECT
            r2.reading_timestamp_utc
                AS return_timestamp_utc,

            r2.previous_kwh
                AS return_from_kwh,

            r2.active_energy_cumulative_kwh
                AS return_to_kwh

        FROM readings r2

        WHERE r2.energy_meter_key = d.energy_meter_key

          AND r2.reading_timestamp_utc
              > d.reading_timestamp_utc

          -- returns to or above old high baseline
          AND r2.active_energy_cumulative_kwh
              >= d.previous_kwh

          -- return itself is a huge upward jump
          AND (
              r2.active_energy_cumulative_kwh
              - r2.previous_kwh
          ) > (10 * d.p99_positive_change)

          -- readings around the return are close together
          AND EXTRACT(
              EPOCH FROM (
                  r2.reading_timestamp_utc
                  - r2.previous_timestamp_utc
              )
          ) / 60.0 <= 30

        ORDER BY r2.reading_timestamp_utc

        LIMIT 1

    ) recovery ON TRUE
)

SELECT
    m.meter_label,

    c.reading_timestamp_utc + INTERVAL '3 hours'
        AS decrement_timestamp_saudi,

    ROUND(c.previous_kwh::numeric, 2)
        AS previous_kwh,

    ROUND(c.active_energy_cumulative_kwh::numeric, 2)
        AS current_kwh,

    ROUND(c.drop_size_kwh::numeric, 2)
        AS decrement_size_kwh,

    ROUND(c.two_back_kwh::numeric, 2)
        AS two_back_kwh,

    ROUND(c.next_kwh::numeric, 2)
        AS next_kwh,

    c.return_timestamp_utc + INTERVAL '3 hours'
        AS later_abrupt_return_saudi,

    ROUND(c.return_from_kwh::numeric, 2)
        AS return_from_kwh,

    ROUND(c.return_to_kwh::numeric, 2)
        AS return_to_kwh,

    CASE

        /* Tiny decrement relative to normal meter movement */
        WHEN c.drop_size_kwh
             <= 10 * c.p99_positive_change
        THEN 'MINOR_DECREMENT'


        /* HIGH -> LOW -> HIGH */
        WHEN c.next_kwh >= c.previous_kwh

         AND EXTRACT(
             EPOCH FROM (
                 c.next_timestamp_utc
                 - c.reading_timestamp_utc
             )
         ) / 60.0 <= 30

         AND (
             c.next_kwh
             - c.active_energy_cumulative_kwh
         ) > 10 * c.p99_positive_change

        THEN 'ISOLATED_LOW_SAMPLE'


        /* LOW -> abnormal HIGH -> LOW */
        WHEN c.two_back_kwh IS NOT NULL

         AND (
             c.previous_kwh - c.two_back_kwh
         ) > 10 * c.p99_positive_change

         AND EXTRACT(
             EPOCH FROM (
                 c.previous_timestamp_utc
                 - c.two_back_timestamp_utc
             )
         ) / 60.0 <= 30

         AND ABS(
             c.active_energy_cumulative_kwh
             - c.two_back_kwh
         ) <= 10 * c.p99_positive_change

        THEN 'RETURN_TO_LOW_AFTER_UPWARD_SPIKE'


        /* HIGH -> LOW sequence -> abrupt HIGH later */
        WHEN c.return_timestamp_utc IS NOT NULL

        THEN 'TEMPORARY_DOWNWARD_SWITCH'


        /* HIGH -> LOW and no abrupt return found */
        ELSE 'UNRESOLVED_DOWNWARD_SHIFT'

    END AS decrement_classification

FROM classified c

JOIN gold.meter m
    ON m.energy_meter_key = c.energy_meter_key

ORDER BY
    m.meter_label,
    c.reading_timestamp_utc;

-- ==========================================================================
-- 2026-09-06T07:59:01.482Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
WITH readings AS (
    SELECT
        energy_meter_key,
        reading_timestamp_utc,
        active_energy_cumulative_kwh,

        LAG(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_kwh,

        LAG(active_energy_cumulative_kwh, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_kwh,

        LAG(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_timestamp_utc,

        LAG(reading_timestamp_utc, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_timestamp_utc,

        LEAD(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_kwh,

        LEAD(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_timestamp_utc

    FROM silver.fact_energy_readings_snapshot

    WHERE energy_meter_key IN (
        'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2',
        '9fc6d98a-5c79-48df-abd5-c0a21e61f40c'
    )

    AND active_energy_cumulative_kwh IS NOT NULL
),

stats AS (
    SELECT
        energy_meter_key,

        PERCENTILE_CONT(0.99)
        WITHIN GROUP (
            ORDER BY active_energy_cumulative_kwh - previous_kwh
        ) FILTER (
            WHERE active_energy_cumulative_kwh > previous_kwh
        ) AS p99_positive_change

    FROM readings
    GROUP BY energy_meter_key
),

drops AS (
    SELECT
        r.*,
        s.p99_positive_change,

        previous_kwh - active_energy_cumulative_kwh
            AS decrement_size_kwh

    FROM readings r

    JOIN stats s
        ON s.energy_meter_key = r.energy_meter_key

    WHERE active_energy_cumulative_kwh < previous_kwh
),

classified AS (
    SELECT
        d.*,

        recovery.return_timestamp_utc,
        recovery.return_from_kwh,
        recovery.return_to_kwh

    FROM drops d

    LEFT JOIN LATERAL (
        SELECT
            r2.reading_timestamp_utc AS return_timestamp_utc,
            r2.previous_kwh AS return_from_kwh,
            r2.active_energy_cumulative_kwh AS return_to_kwh

        FROM readings r2

        WHERE r2.energy_meter_key = d.energy_meter_key

          AND r2.reading_timestamp_utc >
              d.reading_timestamp_utc

          AND r2.active_energy_cumulative_kwh >=
              d.previous_kwh

          AND (
              r2.active_energy_cumulative_kwh -
              r2.previous_kwh
          ) > (10 * d.p99_positive_change)

          AND EXTRACT(
              EPOCH FROM (
                  r2.reading_timestamp_utc -
                  r2.previous_timestamp_utc
              )
          ) / 60.0 <= 30

        ORDER BY r2.reading_timestamp_utc
        LIMIT 1

    ) recovery ON TRUE
)

SELECT
    CASE
        WHEN c.energy_meter_key =
            'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2'
            THEN 'PB1'
        ELSE 'PB2'
    END AS meter,

    c.reading_timestamp_utc + INTERVAL '3 hours'
        AS decrement_timestamp_saudi,

    c.previous_kwh,

    c.active_energy_cumulative_kwh
        AS current_kwh,

    c.decrement_size_kwh,

    c.next_kwh,

    CASE
        WHEN c.decrement_size_kwh
            <= 10 * c.p99_positive_change
        THEN 'Minor Decrement'

        WHEN c.next_kwh >= c.previous_kwh
         AND EXTRACT(
             EPOCH FROM (
                 c.next_timestamp_utc -
                 c.reading_timestamp_utc
             )
         ) / 60.0 <= 30
         AND (
             c.next_kwh -
             c.active_energy_cumulative_kwh
         ) > 10 * c.p99_positive_change
        THEN 'Isolated Low Sample'

        WHEN c.two_back_kwh IS NOT NULL
         AND (
             c.previous_kwh -
             c.two_back_kwh
         ) > 10 * c.p99_positive_change
         AND EXTRACT(
             EPOCH FROM (
                 c.previous_timestamp_utc -
                 c.two_back_timestamp_utc
             )
         ) / 60.0 <= 30
         AND ABS(
             c.active_energy_cumulative_kwh -
             c.two_back_kwh
         ) <= 10 * c.p99_positive_change
        THEN 'Return to Low After Upward Spike'

        WHEN c.return_timestamp_utc IS NOT NULL
        THEN 'Temporary Downward Switch'

        ELSE 'Unresolved Downward Shift'

    END AS problem_type

FROM classified c

ORDER BY
    c.energy_meter_key,
    c.reading_timestamp_utc;

-- ==========================================================================
-- 2026-09-06T07:59:13.402Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
WITH readings AS (
    SELECT
        energy_meter_key,
        reading_timestamp_utc,
        active_energy_cumulative_kwh,

        LAG(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_kwh,

        LAG(active_energy_cumulative_kwh, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_kwh,

        LAG(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_timestamp_utc,

        LAG(reading_timestamp_utc, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_timestamp_utc,

        LEAD(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_kwh,

        LEAD(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_timestamp_utc

    FROM silver.fact_energy_readings_snapshot

    WHERE energy_meter_key IN (
        'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2',
        '9fc6d98a-5c79-48df-abd5-c0a21e61f40c'
    )

    AND active_energy_cumulative_kwh IS NOT NULL
),

stats AS (
    SELECT
        energy_meter_key,

        PERCENTILE_CONT(0.99)
        WITHIN GROUP (
            ORDER BY active_energy_cumulative_kwh - previous_kwh
        ) FILTER (
            WHERE active_energy_cumulative_kwh > previous_kwh
        ) AS p99_positive_change

    FROM readings
    GROUP BY energy_meter_key
),

drops AS (
    SELECT
        r.*,
        s.p99_positive_change,

        previous_kwh - active_energy_cumulative_kwh
            AS decrement_size_kwh

    FROM readings r

    JOIN stats s
        ON s.energy_meter_key = r.energy_meter_key

    WHERE active_energy_cumulative_kwh < previous_kwh
),

classified AS (
    SELECT
        d.*,

        recovery.return_timestamp_utc,
        recovery.return_from_kwh,
        recovery.return_to_kwh

    FROM drops d

    LEFT JOIN LATERAL (
        SELECT
            r2.reading_timestamp_utc AS return_timestamp_utc,
            r2.previous_kwh AS return_from_kwh,
            r2.active_energy_cumulative_kwh AS return_to_kwh

        FROM readings r2

        WHERE r2.energy_meter_key = d.energy_meter_key

          AND r2.reading_timestamp_utc >
              d.reading_timestamp_utc

          AND r2.active_energy_cumulative_kwh >=
              d.previous_kwh

          AND (
              r2.active_energy_cumulative_kwh -
              r2.previous_kwh
          ) > (10 * d.p99_positive_change)

          AND EXTRACT(
              EPOCH FROM (
                  r2.reading_timestamp_utc -
                  r2.previous_timestamp_utc
              )
          ) / 60.0 <= 30

        ORDER BY r2.reading_timestamp_utc
        LIMIT 1

    ) recovery ON TRUE
)

SELECT
    CASE
        WHEN c.energy_meter_key =
            'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2'
            THEN 'PB1'
        ELSE 'PB2'
    END AS meter,

    c.reading_timestamp_utc + INTERVAL '3 hours'
        AS decrement_timestamp_saudi,

    c.previous_kwh,

    c.active_energy_cumulative_kwh
        AS current_kwh,

    c.decrement_size_kwh,

    c.next_kwh,

    CASE
        WHEN c.decrement_size_kwh
            <= 10 * c.p99_positive_change
        THEN 'Minor Decrement'

        WHEN c.next_kwh >= c.previous_kwh
         AND EXTRACT(
             EPOCH FROM (
                 c.next_timestamp_utc -
                 c.reading_timestamp_utc
             )
         ) / 60.0 <= 30
         AND (
             c.next_kwh -
             c.active_energy_cumulative_kwh
         ) > 10 * c.p99_positive_change
        THEN 'Isolated Low Sample'

        WHEN c.two_back_kwh IS NOT NULL
         AND (
             c.previous_kwh -
             c.two_back_kwh
         ) > 10 * c.p99_positive_change
         AND EXTRACT(
             EPOCH FROM (
                 c.previous_timestamp_utc -
                 c.two_back_timestamp_utc
             )
         ) / 60.0 <= 30
         AND ABS(
             c.active_energy_cumulative_kwh -
             c.two_back_kwh
         ) <= 10 * c.p99_positive_change
        THEN 'Return to Low After Upward Spike'

        WHEN c.return_timestamp_utc IS NOT NULL
        THEN 'Temporary Downward Switch'

        ELSE 'Unresolved Downward Shift'

    END AS problem_type

FROM classified c

ORDER BY
    c.energy_meter_key,
    c.reading_timestamp_utc;

-- ==========================================================================
-- 2026-09-06T07:59:20.082Z  database=sadinhub  succeeded=True  rows=38
-- ==========================================================================
WITH readings AS (
    SELECT
        energy_meter_key,
        reading_timestamp_utc,
        active_energy_cumulative_kwh,

        LAG(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_kwh,

        LAG(active_energy_cumulative_kwh, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_kwh,

        LAG(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS previous_timestamp_utc,

        LAG(reading_timestamp_utc, 2) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS two_back_timestamp_utc,

        LEAD(active_energy_cumulative_kwh, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_kwh,

        LEAD(reading_timestamp_utc, 1) OVER (
            PARTITION BY energy_meter_key
            ORDER BY reading_timestamp_utc
        ) AS next_timestamp_utc

    FROM silver.fact_energy_readings_snapshot

    WHERE energy_meter_key IN (
        'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2',
        '9fc6d98a-5c79-48df-abd5-c0a21e61f40c'
    )

    AND active_energy_cumulative_kwh IS NOT NULL
),

stats AS (
    SELECT
        energy_meter_key,

        PERCENTILE_CONT(0.99)
        WITHIN GROUP (
            ORDER BY active_energy_cumulative_kwh - previous_kwh
        ) FILTER (
            WHERE active_energy_cumulative_kwh > previous_kwh
        ) AS p99_positive_change

    FROM readings
    GROUP BY energy_meter_key
),

drops AS (
    SELECT
        r.*,
        s.p99_positive_change,

        previous_kwh - active_energy_cumulative_kwh
            AS decrement_size_kwh

    FROM readings r

    JOIN stats s
        ON s.energy_meter_key = r.energy_meter_key

    WHERE active_energy_cumulative_kwh < previous_kwh
),

classified AS (
    SELECT
        d.*,

        recovery.return_timestamp_utc,
        recovery.return_from_kwh,
        recovery.return_to_kwh

    FROM drops d

    LEFT JOIN LATERAL (
        SELECT
            r2.reading_timestamp_utc AS return_timestamp_utc,
            r2.previous_kwh AS return_from_kwh,
            r2.active_energy_cumulative_kwh AS return_to_kwh

        FROM readings r2

        WHERE r2.energy_meter_key = d.energy_meter_key

          AND r2.reading_timestamp_utc >
              d.reading_timestamp_utc

          AND r2.active_energy_cumulative_kwh >=
              d.previous_kwh

          AND (
              r2.active_energy_cumulative_kwh -
              r2.previous_kwh
          ) > (10 * d.p99_positive_change)

          AND EXTRACT(
              EPOCH FROM (
                  r2.reading_timestamp_utc -
                  r2.previous_timestamp_utc
              )
          ) / 60.0 <= 30

        ORDER BY r2.reading_timestamp_utc
        LIMIT 1

    ) recovery ON TRUE
)

SELECT
    CASE
        WHEN c.energy_meter_key =
            'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2'
            THEN 'PB1'
        ELSE 'PB2'
    END AS meter,

    c.reading_timestamp_utc + INTERVAL '3 hours'
        AS decrement_timestamp_saudi,

    c.previous_kwh,

    c.active_energy_cumulative_kwh
        AS current_kwh,

    c.decrement_size_kwh,

    c.next_kwh,

    CASE
        WHEN c.decrement_size_kwh
            <= 10 * c.p99_positive_change
        THEN 'Minor Decrement'

        WHEN c.next_kwh >= c.previous_kwh
         AND EXTRACT(
             EPOCH FROM (
                 c.next_timestamp_utc -
                 c.reading_timestamp_utc
             )
         ) / 60.0 <= 30
         AND (
             c.next_kwh -
             c.active_energy_cumulative_kwh
         ) > 10 * c.p99_positive_change
        THEN 'Isolated Low Sample'

        WHEN c.two_back_kwh IS NOT NULL
         AND (
             c.previous_kwh -
             c.two_back_kwh
         ) > 10 * c.p99_positive_change
         AND EXTRACT(
             EPOCH FROM (
                 c.previous_timestamp_utc -
                 c.two_back_timestamp_utc
             )
         ) / 60.0 <= 30
         AND ABS(
             c.active_energy_cumulative_kwh -
             c.two_back_kwh
         ) <= 10 * c.p99_positive_change
        THEN 'Return to Low After Upward Spike'

        WHEN c.return_timestamp_utc IS NOT NULL
        THEN 'Temporary Downward Switch'

        ELSE 'Unresolved Downward Shift'

    END AS problem_type

FROM classified c

ORDER BY
    c.energy_meter_key,
    c.reading_timestamp_utc;

-- ==========================================================================
-- 2026-09-06T10:58:56.962Z  database=sadinhub  succeeded=True  rows=97
-- ==========================================================================
SELECT
    table_name,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'gold'
  AND table_name IN (
      'energy_raw',
      'energy_consumption_validated',
      'meter'
  )
ORDER BY table_name, ordinal_position;

-- ==========================================================================
-- 2026-09-06T11:07:06.431Z  database=sadinhub  succeeded=True  rows=29
-- ==========================================================================
SELECT
    meter_label,

    MIN(reading_date_saudi) AS first_date,
    MAX(reading_date_saudi) AS last_date,

    COUNT(*) AS total_rows,
    COUNT(DISTINCT reading_date_saudi) AS days_with_records,

    MAX(reading_date_saudi)
        - MIN(reading_date_saudi) + 1 AS calendar_days_in_span,

    COUNT(*) FILTER (
        WHERE interval_quality = 'LONG_GAP'
    ) AS long_gap_intervals,

    ROUND(MAX(gap_minutes), 1) AS longest_interval_minutes,

    COUNT(*) FILTER (
        WHERE validated_kwh_consumption IS NULL
    ) AS null_consumption_rows,

    COUNT(*) FILTER (
        WHERE validated_kwh_consumption < 0
    ) AS negative_consumption_rows,

    STRING_AGG(
        DISTINCT interval_quality,
        ', ' ORDER BY interval_quality
    ) AS interval_labels

FROM gold.energy_consumption_validated
GROUP BY energy_meter_key, meter_label
ORDER BY meter_label;

-- ==========================================================================
-- 2026-09-06T13:47:46.492Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
-- ============================================================
-- Sign mismatch between Power Factor and Active Power, per phase
--
-- Electrically, PF and active power should carry the same sign
-- on a given phase (both flip together if current-transformer
-- polarity is reversed). A mismatch -- one negative, the other
-- not, on the same phase, same reading -- is a genuine
-- inconsistency worth investigating.
-- ============================================================

WITH mismatches AS (
    SELECT
        e.reading_timestamp_utc,
        m.meter_label,
        1 AS phase,
        e.power_factor_phase_1 AS pf,
        e.active_power_phase_1_kw AS active_power_kw
    FROM gold.energy_raw e
    LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
    WHERE (e.power_factor_phase_1 < 0 AND e.active_power_phase_1_kw >= 0)
       OR (e.power_factor_phase_1 >= 0 AND e.active_power_phase_1_kw < 0)

    UNION ALL

    SELECT
        e.reading_timestamp_utc,
        m.meter_label,
        2 AS phase,
        e.power_factor_phase_2,
        e.active_power_phase_2_kw
    FROM gold.energy_raw e
    LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
    WHERE (e.power_factor_phase_2 < 0 AND e.active_power_phase_2_kw >= 0)
       OR (e.power_factor_phase_2 >= 0 AND e.active_power_phase_2_kw < 0)

    UNION ALL

    SELECT
        e.reading_timestamp_utc,
        m.meter_label,
        3 AS phase,
        e.power_factor_phase_3,
        e.active_power_phase_3_kw
    FROM gold.energy_raw e
    LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
    WHERE (e.power_factor_phase_3 < 0 AND e.active_power_phase_3_kw >= 0)
       OR (e.power_factor_phase_3 >= 0 AND e.active_power_phase_3_kw < 0)
)

-- Summary: how many mismatches per meter, per phase
SELECT meter_label, phase, COUNT(*) AS mismatch_count
FROM mismatches
GROUP BY meter_label, phase
ORDER BY mismatch_count DESC;

-- Detail (comment the summary above out and use this instead if
-- you want the actual rows, not just counts):
-- SELECT * FROM mismatches ORDER BY meter_label, phase, reading_timestamp_utc;

-- ==========================================================================
-- 2026-09-06T13:48:19.428Z  database=sadinhub  succeeded=True  rows=4
-- ==========================================================================
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_name ILIKE '%dictionar%' OR table_name ILIKE '%telemetr%key%';

-- ==========================================================================
-- 2026-09-07T08:44:59.203Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
SELECT DISTINCT
    key_id,
    key
FROM keys
WHERE LOWER(key) LIKE '%pf%'
ORDER BY key;

-- ==========================================================================
-- 2026-09-07T08:48:14.843Z  database=sadinhub  succeeded=True  rows=8
-- ==========================================================================
SELECT
    table_schema,
    table_name,
    column_name
FROM information_schema.columns
WHERE column_name IN ('key', 'key_id')
ORDER BY table_schema, table_name, column_name;

-- ==========================================================================
-- 2026-09-07T09:00:01.913Z  database=sadinhub  succeeded=True  rows=3
-- ==========================================================================
SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
  AND table_name = 'telemetries_dictionaries'
ORDER BY ordinal_position;

-- ==========================================================================
-- 2026-09-07T09:00:17.753Z  database=sadinhub  succeeded=True  rows=3
-- ==========================================================================
SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
  AND table_name = 'telemetries_dictionaries'
ORDER BY ordinal_position;

-- ==========================================================================
-- 2026-09-07T09:03:31.482Z  database=sadinhub  succeeded=True  rows=4
-- ==========================================================================
SELECT
    id,
    key
FROM bronze.telemetries_dictionaries
WHERE LOWER(key) LIKE '%pf%'
ORDER BY key;

-- ==========================================================================
-- 2026-09-07T09:09:22.499Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
SELECT
    em.energy_meter_key,
    em.meter_label,
    em.device_id
FROM gold.meter em
WHERE em.meter_label = 'ZN.12-PB_child__1_ch3pm';

-- ==========================================================================
-- 2026-09-07T09:27:07.754Z  database=sadinhub  succeeded=True  rows=54
-- ==========================================================================
SELECT
    table_schema,
    table_name,
    column_name
FROM information_schema.columns
WHERE column_name IN (
    'energy_meter_key',
    'device_id',
    'meter_label'
)
ORDER BY table_schema, table_name, column_name;

-- ==========================================================================
-- 2026-09-07T09:43:42.670Z  database=sadinhub  succeeded=True  rows=1
-- ==========================================================================
SELECT
    meter_label,
    device_id
FROM bronze.energy_meters
WHERE meter_label = 'ZN.12-PB_child__1_ch3pm';

-- ==========================================================================
-- 2026-09-07T09:44:03.846Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
SELECT
    COUNT(*) FILTER (WHERE value::double precision < 0)  AS pf3_lt_0,
    COUNT(*) FILTER (WHERE value::double precision = 0)  AS pf3_eq_0,
    COUNT(*) FILTER (WHERE value::double precision <= 0) AS pf3_le_0
FROM bronze.telemetries
WHERE device_id = 'f7715eeb-8c09-4a89-8d2c-74926eb78785'
  AND key_id = 37;

-- ==========================================================================
-- 2026-09-07T09:44:23.725Z  database=sadinhub  succeeded=True  rows=8
-- ==========================================================================
SELECT
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'bronze'
  AND table_name = 'telemetries'
ORDER BY ordinal_position;

-- ==========================================================================
-- 2026-09-07T09:45:20.167Z  database=sadinhub  succeeded=True  rows=1
-- ==========================================================================
SELECT
    COUNT(*) FILTER (WHERE dbl < 0)  AS pf3_lt_0,
    COUNT(*) FILTER (WHERE dbl = 0)  AS pf3_eq_0,
    COUNT(*) FILTER (WHERE dbl <= 0) AS pf3_le_0
FROM bronze.telemetries
WHERE device_id = 'f7715eeb-8c09-4a89-8d2c-74926eb78785'
  AND key_id = 37;

-- ==========================================================================
-- 2026-09-08T09:52:26.145Z  database=sadinhub  succeeded=False  rows=None
-- ==========================================================================
select fact_energy_readings_flagged from silver
