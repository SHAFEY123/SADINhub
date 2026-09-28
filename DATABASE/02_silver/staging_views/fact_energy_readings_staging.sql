-- View silver.fact_energy_readings_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.fact_energy_readings_staging AS
 WITH electrical_source AS (
         SELECT meter.energy_meter_key,
            meter.source_energy_meter_id,
            meter.facility_key,
            meter.zone_key,
            meter.grid_billing_account_key,
            t."timestamp" AS source_timestamp_ms,
            (to_timestamp((t."timestamp"::numeric / 1000.0)::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
            td.key AS telemetry_key,
            COALESCE(t.dbl, t.long::double precision) AS numeric_reading_value
           FROM silver.telemetries_landing t
             JOIN silver.dim_energy_meter_staging meter ON meter.energy_meter_key = t.device_id
             JOIN silver.telemetries_dictionaries_landing td ON td.id = t.key_id
          WHERE td.key = ANY (ARRAY['V1'::text, 'V2'::text, 'V3'::text, 'Va'::text, 'Vn1'::text, 'Vn2'::text, 'Vn3'::text, 'Vna'::text, 'Amp1'::text, 'Amp2'::text, 'Amp3'::text, 'Ampa'::text, 'Hz'::text, 'PF1'::text, 'PF2'::text, 'PF3'::text, 'PFa'::text, 'kW1'::text, 'kW2'::text, 'kW3'::text, 'TkW'::text, 'kVA1'::text, 'kVA2'::text, 'kVA3'::text, 'TkVA'::text, 'kVAr1'::text, 'kVAr2'::text, 'kVAr3'::text, 'TkVAr'::text, 'kWh'::text, 'kVAh'::text, 'kVArh'::text])
        ), pivoted AS (
         SELECT electrical_source.energy_meter_key,
            electrical_source.source_energy_meter_id,
            electrical_source.facility_key,
            electrical_source.zone_key,
            electrical_source.grid_billing_account_key,
            to_char(electrical_source.reading_timestamp_utc::date::timestamp with time zone, 'YYYYMMDD'::text)::integer AS date_key,
            to_char(electrical_source.reading_timestamp_utc, 'HH24MISS'::text)::integer AS time_key,
            electrical_source.source_timestamp_ms,
            electrical_source.reading_timestamp_utc,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'V1'::text) AS voltage_line_1_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'V2'::text) AS voltage_line_2_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'V3'::text) AS voltage_line_3_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Va'::text) AS voltage_line_average_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Vn1'::text) AS voltage_neutral_1_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Vn2'::text) AS voltage_neutral_2_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Vn3'::text) AS voltage_neutral_3_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Vna'::text) AS voltage_neutral_average_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Amp1'::text) AS current_phase_1_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Amp2'::text) AS current_phase_2_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Amp3'::text) AS current_phase_3_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Ampa'::text) AS current_average_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'Hz'::text) AS frequency_hz,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'PF1'::text) AS power_factor_phase_1,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'PF2'::text) AS power_factor_phase_2,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'PF3'::text) AS power_factor_phase_3,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'PFa'::text) AS power_factor_average,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kW1'::text) AS active_power_phase_1_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kW2'::text) AS active_power_phase_2_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kW3'::text) AS active_power_phase_3_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'TkW'::text) AS active_power_total_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVA1'::text) AS apparent_power_phase_1_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVA2'::text) AS apparent_power_phase_2_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVA3'::text) AS apparent_power_phase_3_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'TkVA'::text) AS apparent_power_total_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVAr1'::text) AS reactive_power_phase_1_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVAr2'::text) AS reactive_power_phase_2_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVAr3'::text) AS reactive_power_phase_3_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'TkVAr'::text) AS reactive_power_total_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kWh'::text) AS active_energy_cumulative_kwh,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVAh'::text) AS apparent_energy_cumulative_kvah,
            max(electrical_source.numeric_reading_value) FILTER (WHERE electrical_source.telemetry_key = 'kVArh'::text) AS reactive_energy_cumulative_kvarh,
            count(*)::integer AS source_measurement_row_count,
            count(DISTINCT electrical_source.telemetry_key)::integer AS populated_measurement_count,
            (count(*) - count(DISTINCT electrical_source.telemetry_key))::integer AS duplicate_measurement_row_count,
            (to_timestamp((electrical_source.source_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
            (to_timestamp((electrical_source.source_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text)::date AS reading_date_saudi,
            (to_timestamp((electrical_source.source_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text)::time without time zone AS reading_time_saudi,
            to_char((to_timestamp((electrical_source.source_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text)::integer AS saudi_date_key,
            to_char((to_timestamp((electrical_source.source_timestamp_ms::numeric / 1000.0)::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text)::integer AS saudi_time_key
           FROM electrical_source
          GROUP BY electrical_source.energy_meter_key, electrical_source.source_energy_meter_id, electrical_source.facility_key, electrical_source.zone_key, electrical_source.grid_billing_account_key, electrical_source.source_timestamp_ms, electrical_source.reading_timestamp_utc
        )
 SELECT p.energy_meter_key,
    p.source_energy_meter_id,
    p.facility_key,
    p.zone_key,
    p.grid_billing_account_key,
    p.date_key,
    p.time_key,
    p.source_timestamp_ms,
    p.reading_timestamp_utc,
    p.voltage_line_1_v,
    p.voltage_line_2_v,
    p.voltage_line_3_v,
    p.voltage_line_average_v,
    p.voltage_neutral_1_v,
    p.voltage_neutral_2_v,
    p.voltage_neutral_3_v,
    p.voltage_neutral_average_v,
    p.current_phase_1_a,
    p.current_phase_2_a,
    p.current_phase_3_a,
    p.current_average_a,
    p.frequency_hz,
    p.power_factor_phase_1,
    p.power_factor_phase_2,
    p.power_factor_phase_3,
    p.power_factor_average,
    p.active_power_phase_1_kw,
    p.active_power_phase_2_kw,
    p.active_power_phase_3_kw,
    p.active_power_total_kw,
    p.apparent_power_phase_1_kva,
    p.apparent_power_phase_2_kva,
    p.apparent_power_phase_3_kva,
    p.apparent_power_total_kva,
    p.reactive_power_phase_1_kvar,
    p.reactive_power_phase_2_kvar,
    p.reactive_power_phase_3_kvar,
    p.reactive_power_total_kvar,
    p.active_energy_cumulative_kwh,
    p.apparent_energy_cumulative_kvah,
    p.reactive_energy_cumulative_kvarh,
    p.source_measurement_row_count,
    p.populated_measurement_count,
    p.duplicate_measurement_row_count,
    p.reading_timestamp_saudi,
    p.reading_date_saudi,
    p.reading_time_saudi,
    p.saudi_date_key,
    p.saudi_time_key,
        CASE
            WHEN m.phase_count = 3 AND num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3 THEN round(((p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision)::numeric, 2)::double precision
            ELSE NULL::double precision
        END AS calculated_current_average_a,
        CASE
            WHEN m.phase_count = 3 AND num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3 THEN round((GREATEST(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) - LEAST(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a))::numeric, 2)::double precision
            ELSE NULL::double precision
        END AS current_phase_spread_a,
        CASE
            WHEN m.phase_count = 3 AND num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3 AND abs((p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision) > 0.1::double precision THEN round((100.0::double precision * GREATEST(abs(p.current_phase_1_a - (p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision), abs(p.current_phase_2_a - (p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision), abs(p.current_phase_3_a - (p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision)) / abs((p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision))::numeric, 2)::double precision
            ELSE NULL::double precision
        END AS current_imbalance_pct,
        CASE
            WHEN m.phase_count IS NULL THEN 'PHASE_COUNT_UNKNOWN'::text
            WHEN m.phase_count <> 3 THEN 'NOT_APPLICABLE_NON_THREE_PHASE'::text
            WHEN num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) < 3 THEN 'INSUFFICIENT_PHASE_DATA'::text
            WHEN abs((p.current_phase_1_a + p.current_phase_2_a + p.current_phase_3_a) / 3.0::double precision) <= 0.1::double precision THEN 'LOW_LOAD_NOT_EVALUATED'::text
            ELSE 'EVALUATED'::text
        END COLLATE "C" AS current_imbalance_evaluation_status,
        CASE
            WHEN m.phase_count = 3 AND num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3 THEN round(((p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision)::numeric, 2)::double precision
            ELSE NULL::double precision
        END AS calculated_voltage_average_v,
        CASE
            WHEN m.phase_count = 3 AND num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3 THEN round((GREATEST(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) - LEAST(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v))::numeric, 2)::double precision
            ELSE NULL::double precision
        END AS voltage_phase_spread_v,
        CASE
            WHEN m.phase_count = 3 AND num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3 AND abs((p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision) > 1.0::double precision THEN round((100.0::double precision * GREATEST(abs(p.voltage_line_1_v - (p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision), abs(p.voltage_line_2_v - (p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision), abs(p.voltage_line_3_v - (p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision)) / abs((p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision))::numeric, 2)::double precision
            ELSE NULL::double precision
        END AS voltage_imbalance_pct,
        CASE
            WHEN m.phase_count IS NULL THEN 'PHASE_COUNT_UNKNOWN'::text
            WHEN m.phase_count <> 3 THEN 'NOT_APPLICABLE_NON_THREE_PHASE'::text
            WHEN num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) < 3 THEN 'INSUFFICIENT_PHASE_DATA'::text
            WHEN abs((p.voltage_line_1_v + p.voltage_line_2_v + p.voltage_line_3_v) / 3.0::double precision) <= 1.0::double precision THEN 'LOW_VOLTAGE_NOT_EVALUATED'::text
            ELSE 'EVALUATED'::text
        END COLLATE "C" AS voltage_imbalance_evaluation_status
   FROM pivoted p
     LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = p.energy_meter_key;
