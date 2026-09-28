-- Materialised view silver.dq_device_cadence_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds
-- A materialised view stores its rows; REFRESH MATERIALIZED VIEW
-- rebuilds them from the query below.


CREATE MATERIALIZED VIEW silver.dq_device_cadence_staging AS
 WITH tkw_readings AS (
         SELECT t.device_id,
            t."timestamp",
            lag(t."timestamp") OVER (PARTITION BY t.device_id ORDER BY t."timestamp") AS previous_timestamp
           FROM bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON td.id = t.key_id AND td.key::text = 'TkW'::text
             JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = t.device_id
        ), reading_coverage AS (
         SELECT t.device_id,
            count(*) AS total_tkw_reading_count,
            min(t."timestamp") AS first_timestamp_ms,
            max(t."timestamp") AS last_timestamp_ms,
            count(DISTINCT (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date)::integer AS days_with_tkw_data
           FROM tkw_readings t
          GROUP BY t.device_id
        ), all_gaps AS (
         SELECT tkw_readings.device_id,
            tkw_readings."timestamp",
            tkw_readings.previous_timestamp,
            (tkw_readings."timestamp" - tkw_readings.previous_timestamp)::numeric / 1000.0 AS gap_seconds
           FROM tkw_readings
          WHERE tkw_readings.previous_timestamp IS NOT NULL
        ), cadence_candidates AS (
         SELECT all_gaps.device_id,
            all_gaps."timestamp",
            all_gaps.previous_timestamp,
            all_gaps.gap_seconds
           FROM all_gaps
          WHERE all_gaps.gap_seconds >= 30::numeric AND all_gaps.gap_seconds <= 1800::numeric
        ), cadence_statistics AS (
         SELECT cadence_candidates.device_id,
            count(*) AS baseline_interval_count,
            percentile_cont(0.10::double precision) WITHIN GROUP (ORDER BY (cadence_candidates.gap_seconds::double precision)) AS p10_gap_seconds,
            percentile_cont(0.50::double precision) WITHIN GROUP (ORDER BY (cadence_candidates.gap_seconds::double precision)) AS observed_gap_seconds,
            percentile_cont(0.90::double precision) WITHIN GROUP (ORDER BY (cadence_candidates.gap_seconds::double precision)) AS p90_gap_seconds,
            avg(cadence_candidates.gap_seconds) AS average_candidate_gap_seconds,
            stddev_samp(cadence_candidates.gap_seconds) AS candidate_gap_stddev_seconds
           FROM cadence_candidates
          GROUP BY cadence_candidates.device_id
        ), gap_totals AS (
         SELECT all_gaps.device_id,
            count(*) AS all_interval_count,
            count(*) FILTER (WHERE all_gaps.gap_seconds > 1800::numeric) AS gap_over_30_minutes_count,
            max(all_gaps.gap_seconds) AS maximum_observed_gap_seconds
           FROM all_gaps
          GROUP BY all_gaps.device_id
        ), cadence_base AS (
         SELECT m.energy_meter_key,
            m.source_energy_meter_id,
            m.facility_key,
            m.zone_key,
            z.zone_name,
            m.device_name,
            m.meter_label,
            m.gateway_id,
            m.mapping_status,
            rc.total_tkw_reading_count,
            rc.days_with_tkw_data,
            rc.first_timestamp_ms,
            rc.last_timestamp_ms,
            cs.baseline_interval_count,
            gt.all_interval_count,
            cs.p10_gap_seconds,
            cs.observed_gap_seconds,
            cs.p90_gap_seconds,
            cs.average_candidate_gap_seconds,
            cs.candidate_gap_stddev_seconds,
            COALESCE(gt.gap_over_30_minutes_count, 0::bigint) AS gap_over_30_minutes_count,
            gt.maximum_observed_gap_seconds
           FROM silver.dim_energy_meter_staging m
             JOIN silver.dim_zone_staging z ON z.zone_key = m.zone_key
             LEFT JOIN reading_coverage rc ON rc.device_id = m.energy_meter_key
             LEFT JOIN cadence_statistics cs ON cs.device_id = m.energy_meter_key
             LEFT JOIN gap_totals gt ON gt.device_id = m.energy_meter_key
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    zone_name,
    device_name,
    meter_label,
    gateway_id,
    mapping_status,
    total_tkw_reading_count,
    days_with_tkw_data,
        CASE
            WHEN first_timestamp_ms IS NULL THEN NULL::timestamp without time zone
            ELSE (to_timestamp((first_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)
        END AS first_reading_utc,
        CASE
            WHEN last_timestamp_ms IS NULL THEN NULL::timestamp without time zone
            ELSE (to_timestamp((last_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)
        END AS last_reading_utc,
        CASE
            WHEN first_timestamp_ms IS NULL THEN NULL::date
            ELSE (to_timestamp((first_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date
        END AS first_reading_date,
        CASE
            WHEN last_timestamp_ms IS NULL THEN NULL::date
            ELSE (to_timestamp((last_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date
        END AS last_reading_date,
    baseline_interval_count,
    all_interval_count,
    round(p10_gap_seconds::numeric, 3) AS p10_gap_seconds,
    300.000 AS nominal_gap_seconds,
    5.000 AS nominal_gap_minutes,
    288 AS nominal_expected_daily_reading_count,
    round(observed_gap_seconds::numeric, 3) AS observed_gap_seconds,
    round((observed_gap_seconds / 60.0::double precision)::numeric, 3) AS observed_gap_minutes,
        CASE
            WHEN observed_gap_seconds IS NULL THEN NULL::integer
            ELSE round(86400.0::double precision / observed_gap_seconds)::integer
        END AS observed_expected_daily_reading_count,
    round(observed_gap_seconds::numeric, 3) AS expected_gap_seconds,
    round((observed_gap_seconds / 60.0::double precision)::numeric, 3) AS expected_gap_minutes,
        CASE
            WHEN observed_gap_seconds IS NULL THEN NULL::integer
            ELSE round(86400.0::double precision / observed_gap_seconds)::integer
        END AS expected_daily_reading_count,
    round(p90_gap_seconds::numeric, 3) AS p90_gap_seconds,
    round((p90_gap_seconds - p10_gap_seconds)::numeric, 3) AS cadence_spread_seconds,
    round(average_candidate_gap_seconds, 3) AS average_candidate_gap_seconds,
    round(candidate_gap_stddev_seconds, 3) AS candidate_gap_stddev_seconds,
    round((observed_gap_seconds - 300.0::double precision)::numeric, 3) AS variance_from_nominal_seconds,
    round(((observed_gap_seconds - 300.0::double precision) / 300.0::double precision)::numeric * 100::numeric, 3) AS variance_from_nominal_percent,
    gap_over_30_minutes_count,
    round(maximum_observed_gap_seconds, 3) AS maximum_observed_gap_seconds,
        CASE
            WHEN observed_gap_seconds IS NULL OR baseline_interval_count < 100 THEN 'INSUFFICIENT_BASELINE'::text
            WHEN (p90_gap_seconds - p10_gap_seconds) > 60::double precision THEN 'UNSTABLE_CADENCE_REVIEW'::text
            WHEN abs(observed_gap_seconds - 300::double precision) <= 15::double precision THEN 'STANDARD_APPROXIMATELY_5_MINUTES'::text
            ELSE 'NON_STANDARD_STABLE_CADENCE'::text
        END COLLATE "C" AS cadence_status,
        CASE
            WHEN observed_gap_seconds IS NULL OR baseline_interval_count < 100 THEN 'INSUFFICIENT_BASELINE'::text
            WHEN (p90_gap_seconds - p10_gap_seconds) > 60::double precision THEN 'UNSTABLE_CADENCE_REVIEW'::text
            WHEN abs(observed_gap_seconds - 300::double precision) <= 15::double precision THEN 'MEETS_NOMINAL_APPROX_5_MINUTE_CADENCE'::text
            ELSE 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text
        END COLLATE "C" AS nominal_cadence_status,
        CASE
            WHEN observed_gap_seconds IS NULL OR baseline_interval_count < 100 THEN false
            WHEN (p90_gap_seconds - p10_gap_seconds) <= 60::double precision THEN true
            ELSE false
        END AS cadence_baseline_is_reliable
   FROM cadence_base WITH NO DATA;
