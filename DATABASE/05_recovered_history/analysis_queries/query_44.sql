-- Recovered from PostgreSQL server log postgresql-2026-07-29_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH checked_readings AS (
        SELECT
            device_id,
            reading_timestamp_utc,
            reading_timestamp_saudi,
            reading_date_saudi,
            reading_time_saudi,
    
            /* Team-approved voltage measurements */
            v1,
            v2,
            v3,
            vn1,
            vn2,
            vn3,
    
            /* Team-approved current measurements */
            amp1,
            amp2,
            amp3,
    
            /* Active power */
            tkw,
            kw1,
            kw2,
            kw3,
    
            /* Reactive power */
            tkvar,
    
            /* Power factor */
            pfa,
            pf1,
            pf2,
            pf3,
    
            /* Frequency and energy */
            hz,
            kwh,
            kvarh,
    
            /* Number of approved values that are not NULL */
            num_nonnulls(
                v1, v2, v3,
                vn1, vn2, vn3,
                amp1, amp2, amp3,
                tkw, kw1, kw2, kw3,
                tkvar,
                pfa, pf1, pf2, pf3,
                hz,
                kwh,
                kvarh
            ) AS populated_value_count,
    
            /* Number of approved values that are greater than or less than zero */
            num_nonnulls(
                NULLIF(v1, 0),
                NULLIF(v2, 0),
                NULLIF(v3, 0),
                NULLIF(vn1, 0),
                NULLIF(vn2, 0),
                NULLIF(vn3, 0),
                NULLIF(amp1, 0),
                NULLIF(amp2, 0),
                NULLIF(amp3, 0),
                NULLIF(tkw, 0),
                NULLIF(kw1, 0),
                NULLIF(kw2, 0),
                NULLIF(kw3, 0),
                NULLIF(tkvar, 0),
                NULLIF(pfa, 0),
                NULLIF(pf1, 0),
                NULLIF(pf2, 0),
                NULLIF(pf3, 0),
                NULLIF(hz, 0),
                NULLIF(kwh, 0),
                NULLIF(kvarh, 0)
            ) AS useful_value_count,
    
            /* Count individual zero values */
            (
                CASE WHEN v1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN v2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN v3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN vn1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN vn2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN vn3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN amp1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN amp2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN amp3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN tkw = 0 THEN 1 ELSE 0 END +
                CASE WHEN kw1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN kw2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN kw3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN tkvar = 0 THEN 1 ELSE 0 END +
                CASE WHEN pfa = 0 THEN 1 ELSE 0 END +
                CASE WHEN pf1 = 0 THEN 1 ELSE 0 END +
                CASE WHEN pf2 = 0 THEN 1 ELSE 0 END +
                CASE WHEN pf3 = 0 THEN 1 ELSE 0 END +
                CASE WHEN hz = 0 THEN 1 ELSE 0 END +
                CASE WHEN kwh = 0 THEN 1 ELSE 0 END +
                CASE WHEN kvarh = 0 THEN 1 ELSE 0 END
            ) AS zero_value_count
    
        FROM silver.fact_energy_readings_staging
        WHERE reading_date_saudi = DATE '2025-03-01'
    )
    
    SELECT
        *,
        CASE
            WHEN useful_value_count = 0
                THEN 'EXCLUDE_FROM_GOLD'
            ELSE 'KEEP_FOR_GOLD'
        END AS gold_status
    
    FROM checked_readings
    ORDER BY
        CASE
            WHEN useful_value_count = 0 THEN 0
            ELSE 1
        END,
        reading_timestamp_saudi,
        device_id
    
    LIMIT 500;
