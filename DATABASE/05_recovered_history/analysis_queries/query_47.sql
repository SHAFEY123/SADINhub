-- Recovered from PostgreSQL server log postgresql-2026-07-29_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH checked_readings AS (
        SELECT
            r.*,
    
            /* Number of approved measurements containing any value */
            num_nonnulls(
                r.v1,
                r.v2,
                r.v3,
                r.vn1,
                r.vn2,
                r.vn3,
                r.amp1,
                r.amp2,
                r.amp3,
                r.tkw,
                r.kw1,
                r.kw2,
                r.kw3,
                r.tkvar,
                r.pfa,
                r.pf1,
                r.pf2,
                r.pf3,
                r.hz,
                r.kwh,
                r.kvarh
            ) AS populated_value_count,
    
            /* Number of approved measurements that are not zero or NULL */
            num_nonnulls(
                NULLIF(r.v1, 0),
                NULLIF(r.v2, 0),
                NULLIF(r.v3, 0),
                NULLIF(r.vn1, 0),
                NULLIF(r.vn2, 0),
                NULLIF(r.vn3, 0),
                NULLIF(r.amp1, 0),
                NULLIF(r.amp2, 0),
                NULLIF(r.amp3, 0),
                NULLIF(r.tkw, 0),
                NULLIF(r.kw1, 0),
                NULLIF(r.kw2, 0),
                NULLIF(r.kw3, 0),
                NULLIF(r.tkvar, 0),
                NULLIF(r.pfa, 0),
                NULLIF(r.pf1, 0),
                NULLIF(r.pf2, 0),
                NULLIF(r.pf3, 0),
                NULLIF(r.hz, 0),
                NULLIF(r.kwh, 0),
                NULLIF(r.kvarh, 0)
            ) AS useful_value_count,
    
            /* Number of approved measurements equal to zero */
            (
                CASE WHEN r.v1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.v2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.v3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.vn1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.vn2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.vn3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.amp1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.amp2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.amp3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.tkw = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.kw1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.kw2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.kw3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.tkvar = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.pfa = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.pf1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.pf2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.pf3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.hz = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.kwh = 0 THEN 1 ELSE 0 END +
                CASE WHEN r.kvarh = 0 THEN 1 ELSE 0 END
            ) AS zero_value_count
    
        FROM silver.fact_energy_readings_staging AS r
    )
    
    SELECT
        *,
        CASE
            WHEN useful_value_count = 0
                THEN 'EXCLUDE_FROM_GOLD'
            ELSE 'KEEP_FOR_GOLD'
        END AS gold_status
    FROM checked_readings
    ORDER BY useful_value_count ASC
    LIMIT 500;
