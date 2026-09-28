-- View silver.water_bill_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.water_bill_landing AS
 SELECT id,
    water_grid_account_id,
    water_grid_invoice_number::text COLLATE "C" AS water_grid_invoice_number,
    grid_period_begin,
    grid_period_end,
        CASE
            WHEN grid_begin_reading IS NULL THEN NULL::real
            ELSE round(grid_begin_reading::numeric, 6)::real
        END AS grid_begin_reading,
        CASE
            WHEN grid_end_reading IS NULL THEN NULL::real
            ELSE round(grid_end_reading::numeric, 6)::real
        END AS grid_end_reading,
        CASE
            WHEN grid_consumption IS NULL THEN NULL::real
            ELSE round(grid_consumption::numeric, 6)::real
        END AS grid_consumption,
        CASE
            WHEN grid_cost IS NULL THEN NULL::real
            ELSE round(grid_cost::numeric, 6)::real
        END AS grid_cost,
        CASE
            WHEN system_begin_reading IS NULL THEN NULL::real
            ELSE round(system_begin_reading::numeric, 6)::real
        END AS system_begin_reading,
        CASE
            WHEN system_end_reading IS NULL THEN NULL::real
            ELSE round(system_end_reading::numeric, 6)::real
        END AS system_end_reading,
        CASE
            WHEN system_consumption IS NULL THEN NULL::real
            ELSE round(system_consumption::numeric, 6)::real
        END AS system_consumption,
        CASE
            WHEN system_cost IS NULL THEN NULL::real
            ELSE round(system_cost::numeric, 6)::real
        END AS system_cost,
    cost_details::jsonb AS cost_details,
        CASE
            WHEN consumption_different IS NULL THEN NULL::real
            ELSE round(consumption_different::numeric, 6)::real
        END AS consumption_different,
    created_on,
    created_by
   FROM bronze.water_bill;
