-- Materialised view silver.dq_missing_intervals_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds
-- A materialised view stores its rows; REFRESH MATERIALIZED VIEW
-- rebuilds them from the query below.


CREATE MATERIALIZED VIEW silver.dq_missing_intervals_staging AS
 WITH ordered_readings AS (
         SELECT t.device_id,
            t."timestamp",
            lag(t."timestamp") OVER (PARTITION BY t.device_id ORDER BY t."timestamp") AS previous_timestamp
           FROM bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON td.id = t.key_id AND td.key::text = 'TkW'::text
             JOIN silver.dq_device_cadence_staging b_1 ON b_1.energy_meter_key = t.device_id AND b_1.cadence_baseline_is_reliable
        ), detected_gaps AS (
         SELECT r.device_id,
            r.previous_timestamp,
            r."timestamp",
            (r."timestamp" - r.previous_timestamp)::numeric / 1000.0 AS actual_gap_seconds,
            b_1.nominal_gap_seconds,
            b_1.observed_gap_seconds,
            GREATEST(round((r."timestamp" - r.previous_timestamp)::numeric / 1000.0 / b_1.observed_gap_seconds)::integer - 1, 1) AS estimated_missing_readings_observed_cadence,
            GREATEST(round((r."timestamp" - r.previous_timestamp)::numeric / 1000.0 / b_1.nominal_gap_seconds)::integer - 1, 1) AS estimated_missing_readings_nominal_5min
           FROM ordered_readings r
             JOIN silver.dq_device_cadence_staging b_1 ON b_1.energy_meter_key = r.device_id
          WHERE r.previous_timestamp IS NOT NULL AND ((r."timestamp" - r.previous_timestamp)::numeric / 1000.0) > (b_1.observed_gap_seconds * 1.5)
        )
 SELECT b.energy_meter_key,
    b.source_energy_meter_id,
    b.facility_key,
    b.zone_key,
    b.zone_name,
    b.device_name,
    b.meter_label,
    b.gateway_id,
    (to_timestamp((g.previous_timestamp::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text) AS previous_reading_utc,
    (to_timestamp((g."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text) AS next_reading_utc,
    (to_timestamp((g.previous_timestamp::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date AS gap_start_date,
    (to_timestamp((g."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text)::date AS gap_end_date,
    round(g.nominal_gap_seconds, 3) AS nominal_gap_seconds,
    round(g.observed_gap_seconds, 3) AS observed_gap_seconds,
    round(g.observed_gap_seconds, 3) AS expected_gap_seconds,
    round(g.actual_gap_seconds, 3) AS actual_gap_seconds,
    round(g.actual_gap_seconds / 60.0, 3) AS actual_gap_minutes,
    g.estimated_missing_readings_observed_cadence,
    g.estimated_missing_readings_nominal_5min,
    g.estimated_missing_readings_observed_cadence AS estimated_missing_readings,
        CASE
            WHEN g.estimated_missing_readings_observed_cadence >= 144 THEN 'CRITICAL'::text
            WHEN g.estimated_missing_readings_observed_cadence >= 12 THEN 'ERROR'::text
            ELSE 'WARNING'::text
        END COLLATE "C" AS severity,
        CASE
            WHEN g.estimated_missing_readings_observed_cadence >= 144 THEN 'EXTENDED_DEVICE_OR_GATEWAY_OUTAGE'::text
            WHEN g.estimated_missing_readings_observed_cadence >= 12 THEN 'LONG_MISSING_TELEMETRY_PERIOD'::text
            ELSE 'MISSING_TELEMETRY_INTERVAL'::text
        END COLLATE "C" AS issue_code
   FROM detected_gaps g
     JOIN silver.dq_device_cadence_staging b ON b.energy_meter_key = g.device_id WITH NO DATA;
