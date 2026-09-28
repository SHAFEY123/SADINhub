-- Materialised view silver.dq_meter_daily_completeness_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds
-- A materialised view stores its rows; REFRESH MATERIALIZED VIEW
-- rebuilds them from the query below.


CREATE MATERIALIZED VIEW silver.dq_meter_daily_completeness_staging AS
 WITH tkw_readings AS (
         SELECT t.device_id,
            t."timestamp",
            (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date AS reading_date,
            lag(t."timestamp") OVER (PARTITION BY t.device_id, ((to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date) ORDER BY t."timestamp") AS previous_timestamp_same_day
           FROM bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON td.id = t.key_id AND td.key::text = 'TkW'::text
             JOIN silver.dq_device_cadence_staging b ON b.energy_meter_key = t.device_id AND b.cadence_baseline_is_reliable
        ), daily_observed AS (
         SELECT r.device_id,
            r.reading_date,
            count(DISTINCT r."timestamp")::integer AS actual_reading_count,
            min(r."timestamp") AS first_timestamp_ms,
            max(r."timestamp") AS last_timestamp_ms,
            max((r."timestamp" - r.previous_timestamp_same_day)::numeric / 1000.0) FILTER (WHERE r.previous_timestamp_same_day IS NOT NULL) AS maximum_within_day_gap_seconds
           FROM tkw_readings r
          GROUP BY r.device_id, r.reading_date
        ), daily_large_gaps AS (
         SELECT r.device_id,
            r.reading_date,
            count(*) FILTER (WHERE r.previous_timestamp_same_day IS NOT NULL AND ((r."timestamp" - r.previous_timestamp_same_day)::numeric / 1000.0) > (b.observed_gap_seconds * 1.5))::integer AS large_gap_count
           FROM tkw_readings r
             JOIN silver.dq_device_cadence_staging b ON b.energy_meter_key = r.device_id
          GROUP BY r.device_id, r.reading_date
        ), device_calendar AS (
         SELECT b.energy_meter_key,
            gs.reading_date::date AS reading_date
           FROM silver.dq_device_cadence_staging b
             CROSS JOIN LATERAL generate_series(b.first_reading_date::timestamp without time zone, b.last_reading_date::timestamp without time zone, '1 day'::interval) gs(reading_date)
          WHERE b.cadence_baseline_is_reliable
        ), quality_base AS (
         SELECT b.energy_meter_key,
            b.source_energy_meter_id,
            b.facility_key,
            b.zone_key,
            b.zone_name,
            b.device_name,
            b.meter_label,
            b.gateway_id,
            b.cadence_status,
            b.nominal_cadence_status,
            c.reading_date,
            b.nominal_gap_seconds,
            b.nominal_gap_minutes,
            b.nominal_expected_daily_reading_count,
            b.observed_gap_seconds,
            b.observed_gap_minutes,
            b.observed_expected_daily_reading_count,
            COALESCE(o.actual_reading_count, 0) AS actual_reading_count,
            GREATEST(b.nominal_expected_daily_reading_count - COALESCE(o.actual_reading_count, 0), 0) AS nominal_missing_reading_count,
            GREATEST(b.observed_expected_daily_reading_count - COALESCE(o.actual_reading_count, 0), 0) AS observed_missing_reading_count,
            GREATEST(COALESCE(o.actual_reading_count, 0) - b.nominal_expected_daily_reading_count, 0) AS nominal_extra_reading_count,
            GREATEST(COALESCE(o.actual_reading_count, 0) - b.observed_expected_daily_reading_count, 0) AS observed_extra_reading_count,
            COALESCE(lg.large_gap_count, 0) AS large_gap_count,
            o.maximum_within_day_gap_seconds,
            o.first_timestamp_ms,
            o.last_timestamp_ms,
            COALESCE(o.actual_reading_count, 0)::numeric / NULLIF(b.nominal_expected_daily_reading_count, 0)::numeric * 100::numeric AS nominal_raw_completeness_percent,
            COALESCE(o.actual_reading_count, 0)::numeric / NULLIF(b.observed_expected_daily_reading_count, 0)::numeric * 100::numeric AS observed_raw_completeness_percent
           FROM device_calendar c
             JOIN silver.dq_device_cadence_staging b ON b.energy_meter_key = c.energy_meter_key
             LEFT JOIN daily_observed o ON o.device_id = c.energy_meter_key AND o.reading_date = c.reading_date
             LEFT JOIN daily_large_gaps lg ON lg.device_id = c.energy_meter_key AND lg.reading_date = c.reading_date
        ), classified AS (
         SELECT q.energy_meter_key,
            q.source_energy_meter_id,
            q.facility_key,
            q.zone_key,
            q.zone_name,
            q.device_name,
            q.meter_label,
            q.gateway_id,
            q.cadence_status,
            q.nominal_cadence_status,
            q.reading_date,
            q.nominal_gap_seconds,
            q.nominal_gap_minutes,
            q.nominal_expected_daily_reading_count,
            q.observed_gap_seconds,
            q.observed_gap_minutes,
            q.observed_expected_daily_reading_count,
            q.actual_reading_count,
            q.nominal_missing_reading_count,
            q.observed_missing_reading_count,
            q.nominal_extra_reading_count,
            q.observed_extra_reading_count,
            q.large_gap_count,
            q.maximum_within_day_gap_seconds,
            q.first_timestamp_ms,
            q.last_timestamp_ms,
            q.nominal_raw_completeness_percent,
            q.observed_raw_completeness_percent,
                CASE
                    WHEN q.actual_reading_count = 0 THEN 'CRITICAL_NO_DATA'::text
                    WHEN q.actual_reading_count >= q.observed_expected_daily_reading_count THEN 'COMPLETE_TO_OBSERVED_BASELINE'::text
                    WHEN q.observed_missing_reading_count <= 1 AND q.large_gap_count = 0 THEN 'COMPLETE_WITH_DAY_BOUNDARY_VARIATION'::text
                    WHEN q.observed_raw_completeness_percent >= 95::numeric THEN 'WARNING_MINOR_MISSING_INTERVALS'::text
                    WHEN q.observed_raw_completeness_percent >= 80::numeric THEN 'LOW_COMPLETENESS_REVIEW'::text
                    ELSE 'CRITICAL_INCOMPLETE_DAY'::text
                END COLLATE "C" AS observed_daily_quality_status,
                CASE
                    WHEN q.actual_reading_count = 0 THEN 'CRITICAL_NO_DATA'::text
                    WHEN q.nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text AND q.observed_raw_completeness_percent >= 99::numeric AND q.large_gap_count = 0 THEN 'BELOW_288_DUE_TO_STABLE_NONSTANDARD_CADENCE'::text
                    WHEN q.nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text THEN 'NONSTANDARD_CADENCE_WITH_DATA_GAPS'::text
                    WHEN q.actual_reading_count >= q.nominal_expected_daily_reading_count AND q.large_gap_count = 0 THEN 'MEETS_NOMINAL_288_COUNT'::text
                    WHEN q.actual_reading_count = (q.nominal_expected_daily_reading_count - 1) AND q.large_gap_count = 0 THEN 'ONE_READING_BELOW_NOMINAL_BOUNDARY_VARIATION'::text
                    WHEN q.nominal_raw_completeness_percent >= 95::numeric THEN 'BELOW_NOMINAL_COUNT_MINOR'::text
                    WHEN q.nominal_raw_completeness_percent >= 80::numeric THEN 'BELOW_NOMINAL_COUNT_REVIEW'::text
                    ELSE 'CRITICAL_BELOW_NOMINAL_COUNT'::text
                END COLLATE "C" AS nominal_reporting_status
           FROM quality_base q
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    zone_name,
    device_name,
    meter_label,
    gateway_id,
    reading_date,
    nominal_gap_seconds,
    nominal_gap_minutes,
    nominal_expected_daily_reading_count,
    observed_gap_seconds,
    observed_gap_minutes,
    observed_expected_daily_reading_count,
    observed_gap_seconds AS expected_gap_seconds,
    observed_gap_minutes AS expected_gap_minutes,
    observed_expected_daily_reading_count AS expected_daily_reading_count,
    actual_reading_count,
    nominal_missing_reading_count,
    observed_missing_reading_count,
    observed_missing_reading_count AS missing_reading_count,
    nominal_extra_reading_count,
    observed_extra_reading_count,
    round(nominal_raw_completeness_percent, 2) AS nominal_raw_completeness_percent,
    round(LEAST(nominal_raw_completeness_percent, 100::numeric), 2) AS nominal_completeness_percent,
    round(observed_raw_completeness_percent, 2) AS observed_raw_completeness_percent,
    round(LEAST(observed_raw_completeness_percent, 100::numeric), 2) AS observed_completeness_percent,
    round(observed_raw_completeness_percent, 2) AS raw_completeness_percent,
    round(LEAST(observed_raw_completeness_percent, 100::numeric), 2) AS completeness_percent,
    large_gap_count,
    round(maximum_within_day_gap_seconds, 3) AS maximum_within_day_gap_seconds,
        CASE
            WHEN first_timestamp_ms IS NULL THEN NULL::timestamp without time zone
            ELSE (to_timestamp((first_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)
        END AS first_reading_utc,
        CASE
            WHEN last_timestamp_ms IS NULL THEN NULL::timestamp without time zone
            ELSE (to_timestamp((last_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)
        END AS last_reading_utc,
    cadence_status,
    nominal_cadence_status,
    observed_daily_quality_status,
    observed_daily_quality_status AS daily_quality_status,
    nominal_reporting_status,
        CASE
            WHEN actual_reading_count = 0 OR observed_raw_completeness_percent < 80::numeric THEN 'CRITICAL'::text
            WHEN observed_raw_completeness_percent < 95::numeric THEN 'ERROR'::text
            WHEN observed_raw_completeness_percent < 99::numeric OR large_gap_count > 0 THEN 'WARNING'::text
            ELSE 'INFO'::text
        END COLLATE "C" AS severity,
        CASE
            WHEN actual_reading_count = 0 OR observed_raw_completeness_percent < 80::numeric THEN 'CRITICAL'::text
            WHEN observed_raw_completeness_percent < 95::numeric THEN 'ERROR'::text
            WHEN nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text THEN 'WARNING'::text
            WHEN nominal_raw_completeness_percent < 95::numeric THEN 'ERROR'::text
            WHEN nominal_raw_completeness_percent < 99::numeric OR large_gap_count > 0 THEN 'WARNING'::text
            ELSE 'INFO'::text
        END COLLATE "C" AS nominal_reporting_severity,
        CASE
            WHEN actual_reading_count = 0 OR observed_raw_completeness_percent < 80::numeric THEN false
            ELSE true
        END AS usable_for_daily_dashboard,
        CASE
            WHEN observed_raw_completeness_percent >= 99::numeric AND large_gap_count = 0 THEN true
            ELSE false
        END AS usable_for_ml_training,
        CASE
            WHEN nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text THEN true
            ELSE false
        END AS requires_cadence_normalization_for_ml,
        CASE
            WHEN actual_reading_count >= nominal_expected_daily_reading_count THEN true
            ELSE false
        END AS nominal_daily_count_met
   FROM classified WITH NO DATA;
