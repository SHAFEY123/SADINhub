-- View gold.date
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema gold
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW gold.date AS
 SELECT date_key,
    calendar_date,
    calendar_year,
    calendar_quarter,
    month_number,
    month_name,
    month_short_name,
    week_of_year,
    iso_day_of_week,
    day_name,
    day_short_name,
    day_of_month,
    day_of_year,
    is_weekend,
    month_start_date,
    month_end_date,
    quarter_start_date,
    year_start_date
   FROM silver.dim_date_staging;
