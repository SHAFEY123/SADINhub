-- View silver.dim_date_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.dim_date_staging AS
 WITH calendar AS (
         SELECT gs.gs::date AS calendar_date
           FROM generate_series('2024-01-01'::date::timestamp with time zone, '2030-12-31'::date::timestamp with time zone, '1 day'::interval) gs(gs)
        )
 SELECT to_char(calendar_date::timestamp with time zone, 'YYYYMMDD'::text)::integer AS date_key,
    calendar_date,
    EXTRACT(year FROM calendar_date)::integer AS calendar_year,
    EXTRACT(quarter FROM calendar_date)::integer AS calendar_quarter,
    EXTRACT(month FROM calendar_date)::integer AS month_number,
    to_char(calendar_date::timestamp with time zone, 'Month'::text) COLLATE "C" AS month_name,
    to_char(calendar_date::timestamp with time zone, 'Mon'::text) COLLATE "C" AS month_short_name,
    EXTRACT(week FROM calendar_date)::integer AS week_of_year,
    EXTRACT(isodow FROM calendar_date)::integer AS iso_day_of_week,
    to_char(calendar_date::timestamp with time zone, 'Day'::text) COLLATE "C" AS day_name,
    to_char(calendar_date::timestamp with time zone, 'Dy'::text) COLLATE "C" AS day_short_name,
    EXTRACT(day FROM calendar_date)::integer AS day_of_month,
    EXTRACT(doy FROM calendar_date)::integer AS day_of_year,
    EXTRACT(isodow FROM calendar_date) = ANY (ARRAY[6::numeric, 7::numeric]) AS is_weekend,
    date_trunc('month'::text, calendar_date::timestamp with time zone)::date AS month_start_date,
    (date_trunc('month'::text, calendar_date::timestamp with time zone) + '1 mon -1 days'::interval)::date AS month_end_date,
    date_trunc('quarter'::text, calendar_date::timestamp with time zone)::date AS quarter_start_date,
    date_trunc('year'::text, calendar_date::timestamp with time zone)::date AS year_start_date
   FROM calendar;
