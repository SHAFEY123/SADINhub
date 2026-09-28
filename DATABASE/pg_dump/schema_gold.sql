--
-- PostgreSQL database dump
--

\restrict 8eSF6uYdXDehAU0sGfUzeOUKTJ5FZhh56bqNs9XBaqn996uTafra0UypmxwRaqk

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: gold; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA gold;


--
-- Name: billing_account; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.billing_account AS
 SELECT grid_billing_account_key,
    facility_key,
    zone_key,
    account_label,
    account_number,
    meter_serial_number,
    account_type_key,
    account_type_name,
    service_class_key,
    service_class_name,
    breaker_capacity,
    minimal_breaker_capacity,
    maximum_breaker_capacity,
    service_class_fee,
    multiplication_factor,
    start_period,
    end_period,
    configured_billing_days,
    source_created_at
   FROM silver.dim_grid_billing_account_staging;


--
-- Name: date; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.date AS
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


--
-- Name: energy_bill; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.energy_bill AS
 SELECT energy_bill_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    start_date_key,
    end_date_key,
    start_period,
    end_period,
    calculated_billing_days,
    invoice_number,
    beginning_reading,
    ending_reading,
    billed_consumption_kwh,
    billed_cost,
    system_beginning_reading,
    system_ending_reading,
    system_consumption_kwh,
    system_estimated_cost,
    consumption_variance_kwh,
    cost_variance,
    consumption_variance_percent,
    comparing_with_last_bill,
    comparing_with_grid_bill,
    system_reading_timestamp_utc,
    source_created_at
   FROM silver.fact_energy_bill_staging;


--
-- Name: energy_consumption_validated; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.energy_consumption_validated AS
 SELECT energy_meter_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    meter_label,
    reading_timestamp_utc,
    reading_timestamp_saudi,
    reading_date_saudi,
    active_energy_cumulative_kwh,
    previous_valid_timestamp,
    previous_valid_kwh,
    validated_kwh_consumption,
    consumption_cleaning_status,
    interval_quality,
    gap_minutes
   FROM silver.fact_energy_consumption_validated;


--
-- Name: energy_raw; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.energy_raw AS
 SELECT energy_meter_key,
    facility_key,
    zone_key,
    grid_billing_account_key,
    reading_timestamp_utc,
    active_energy_cumulative_kwh,
    reactive_energy_cumulative_kvarh,
    apparent_energy_cumulative_kvah,
    voltage_neutral_1_v,
    voltage_neutral_2_v,
    voltage_neutral_3_v,
    voltage_neutral_average_v,
    voltage_line_1_v,
    voltage_line_2_v,
    voltage_line_3_v,
    voltage_line_average_v,
    current_phase_1_a,
    current_phase_2_a,
    current_phase_3_a,
    frequency_hz,
    power_factor_phase_1,
    power_factor_phase_2,
    power_factor_phase_3,
    power_factor_average,
    active_power_phase_1_kw,
    active_power_phase_2_kw,
    active_power_phase_3_kw,
    active_power_total_kw,
    apparent_power_phase_1_kva,
    apparent_power_phase_2_kva,
    apparent_power_phase_3_kva,
    apparent_power_total_kva,
    reactive_power_phase_1_kvar,
    reactive_power_phase_2_kvar,
    reactive_power_phase_3_kvar,
    reactive_power_total_kvar,
    status_vn1,
    status_vn2,
    status_vn3,
    status_v1,
    status_v2,
    status_v3,
    status_amp1,
    status_amp2,
    status_amp3,
    status_hz,
    status_pf1,
    status_pf2,
    status_pf3,
    status_pfa,
    status_kwh,
    overall_status
   FROM silver.fact_energy_readings_snapshot;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: energy_reading_gaps; Type: TABLE; Schema: gold; Owner: -
--

CREATE TABLE gold.energy_reading_gaps (
    energy_meter_key uuid,
    meter_label text COLLATE pg_catalog."C",
    previous_reading_timestamp timestamp without time zone,
    current_reading_timestamp timestamp without time zone,
    gap_seconds numeric,
    gap_minutes numeric,
    gap_hours numeric,
    gap_days numeric
);


--
-- Name: facility; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.facility AS
 SELECT facility_key,
    facility_name,
    facility_type_key,
    facility_type_name,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    address_key,
    address_title,
    short_address,
    building_number,
    street_name,
    district_name,
    city_name,
    zip_code,
    additional_number,
    unit_number,
    source_created_at
   FROM silver.dim_facility_staging;


--
-- Name: mapping_audit; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.mapping_audit AS
 SELECT source_energy_meter_id,
    device_id,
    facility_id,
    zone_key,
    zone_name,
    source_device_name,
    source_meter_label,
    canonical_device_name,
    canonical_meter_label,
    source_meter_records_for_device,
    source_records_for_meter_label,
    business_rule_code,
    canonical_mapping_rank,
    mapping_decision,
    mapping_status,
    is_meter_active,
    meter_source_created_at
   FROM silver.energy_meter_mapping_audit_staging;


--
-- Name: meter; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.meter AS
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    parent_energy_meter_source_id,
    meter_label,
    meter_serial_number,
    phase_count,
    maximum_kwh,
    energy_meter_type_key,
    energy_meter_type_name,
    is_meter_active,
    device_name,
    device_label,
    device_serial_number,
    device_type_key,
    device_type_name,
    device_category_key,
    device_category_name,
    gateway_id,
    is_device_active,
    is_device_online,
    assembly_date,
    device_properties,
    source_meter_records_for_device,
    source_records_for_meter_label,
    meter_label_matches_device_name,
    mapping_status,
    meter_source_created_at
   FROM silver.dim_energy_meter_staging;


--
-- Name: quality_summary; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.quality_summary AS
 SELECT energy_meter_key,
    meter_label,
    total_readings,
    overall_acceptable_count,
    overall_review_required_count,
    overall_anomaly_count,
    overall_problematic_count,
    overall_critical_count,
    overall_invalid_count,
    computed_at
   FROM silver.data_quality_summary;


--
-- Name: zone; Type: VIEW; Schema: gold; Owner: -
--

CREATE VIEW gold.zone AS
 SELECT zone_key,
    facility_key,
    parent_zone_key,
    parent_zone_name,
    zone_name,
    zone_type_key,
    zone_type_name,
    hierarchy_level,
    is_building,
    is_active,
    has_children,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    html_hex_color,
    description,
    source_created_at
   FROM silver.dim_zone_staging;


--
-- PostgreSQL database dump complete
--

\unrestrict 8eSF6uYdXDehAU0sGfUzeOUKTJ5FZhh56bqNs9XBaqn996uTafra0UypmxwRaqk

