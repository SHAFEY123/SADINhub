-- View silver.telemetries_landing
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.telemetries_landing AS
 SELECT t.device_id,
    t.key_id,
    t."timestamp",
    t.bool,
        CASE
            WHEN t.dbl IS NULL THEN NULL::double precision
            WHEN td.key::text = ANY (ARRAY['V1'::character varying, 'V2'::character varying, 'V3'::character varying, 'Vn1'::character varying, 'Vn2'::character varying, 'Vn3'::character varying, 'Va'::character varying, 'Vna'::character varying]::text[]) THEN round(t.dbl::numeric, 1)::double precision
            WHEN td.key::text = ANY (ARRAY['Amp1'::character varying, 'Amp2'::character varying, 'Amp3'::character varying, 'Ampa'::character varying]::text[]) THEN round(t.dbl::numeric, 1)::double precision
            WHEN td.key::text = 'Hz'::text THEN round(t.dbl::numeric, 2)::double precision
            WHEN td.key::text = ANY (ARRAY['PF1'::character varying, 'PF2'::character varying, 'PF3'::character varying, 'PFa'::character varying]::text[]) THEN round(t.dbl::numeric, 2)::double precision
            WHEN td.key::text = ANY (ARRAY['kW1'::character varying, 'kW2'::character varying, 'kW3'::character varying, 'TkW'::character varying]::text[]) THEN round(t.dbl::numeric, 3)::double precision
            WHEN td.key::text = ANY (ARRAY['kVAr1'::character varying, 'kVAr2'::character varying, 'kVAr3'::character varying, 'TkVAr'::character varying]::text[]) THEN round(t.dbl::numeric, 1)::double precision
            WHEN td.key::text = ANY (ARRAY['kWh'::character varying, 'kVArh'::character varying, 'kVAh'::character varying]::text[]) THEN round(t.dbl::numeric, 1)::double precision
            WHEN td.key::text = ANY (ARRAY['kVA1'::character varying, 'kVA2'::character varying, 'kVA3'::character varying, 'TkVA'::character varying]::text[]) THEN round(t.dbl::numeric, 3)::double precision
            ELSE round(t.dbl::numeric, 9)::double precision
        END AS dbl,
    t."json"::jsonb AS "json",
    t.long,
    t.str::text COLLATE "C" AS str,
    (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
    (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
    (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text)::date AS reading_date_saudi,
    (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text)::time without time zone AS reading_time_saudi,
    to_char((to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text)::integer AS saudi_date_key,
    to_char((to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text)::integer AS saudi_time_key
   FROM bronze.telemetries t
     LEFT JOIN bronze.telemetries_dictionaries td ON td.id = t.key_id;
