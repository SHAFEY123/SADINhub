-- Recovered from PostgreSQL server log postgresql-2026-07-24_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

WITH fact_sample AS (
        SELECT *
        FROM silver.fact_energy_readings_staging
        WHERE date_key = 20250301
    )
    SELECT
        'FACT_TO_ENERGY_METER' AS relationship_checked,
        COUNT(*) AS issue_count
    FROM fact_sample AS fact
    LEFT JOIN silver.dim_energy_meter_staging AS m
        ON m.energy_meter_key = fact.energy_meter_key
    WHERE m.energy_meter_key IS NULL
    
    UNION ALL
    
    SELECT
        'FACT_TO_DATE',
        COUNT(*)
    FROM fact_sample AS fact
    LEFT JOIN silver.dim_date_staging AS d
        ON d.date_key = fact.date_key
    WHERE d.date_key IS NULL
    
    UNION ALL
    
    SELECT
        'FACT_TO_ZONE',
        COUNT(*)
    FROM fact_sample AS fact
    LEFT JOIN silver.dim_zone_staging AS z
        ON z.zone_key = fact.zone_key
    WHERE fact.zone_key IS NOT NULL
      AND z.zone_key IS NULL
    
    UNION ALL
    
    SELECT
        'FACT_TO_FACILITY',
        COUNT(*)
    FROM fact_sample AS fact
    LEFT JOIN silver.dim_facility_staging AS f
        ON f.facility_key = fact.facility_key
    WHERE fact.facility_key IS NOT NULL
      AND f.facility_key IS NULL
    
    UNION ALL
    
    SELECT
        'FACT_TO_BILLING_ACCOUNT',
        COUNT(*)
    FROM fact_sample AS fact
    LEFT JOIN silver.dim_grid_billing_account_staging AS a
        ON a.grid_billing_account_key = fact.grid_billing_account_key
    WHERE fact.grid_billing_account_key IS NOT NULL
      AND a.grid_billing_account_key IS NULL;
