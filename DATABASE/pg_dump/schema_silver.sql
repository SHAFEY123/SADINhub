--
-- PostgreSQL database dump
--

\restrict kY0iHc7dxObRUcNlpTsZiwdDwHKwEIc4xdzZCeVLd7kRsEY5c4KaXq3wJnZDg1g

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
-- Name: silver; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA silver;


--
-- Name: classify_accumulated_energy_v2(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_accumulated_energy_v2(value double precision, prev_value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF prev_value IS NULL THEN RETURN 'Acceptable'; END IF;  -- first-ever reading for this meter, nothing to compare
    IF value < prev_value THEN RETURN 'Invalid'; END IF;      -- decrement -- counter went backward
    RETURN 'Acceptable';
END;
$$;


--
-- Name: classify_active_power(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_active_power(p_value double precision, p_prev_value double precision, p_cb_max_kw double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        0.0,
        p_cb_max_kw,
        0.0,
        p_cb_max_kw,
        NULL,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_apparent_power(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_apparent_power(p_value double precision, p_prev_value double precision, p_user_max double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        NULL,
        p_user_max,
        0.0,
        p_user_max,
        0.0,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_consistency(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_consistency(p_total double precision, p_phase_sum double precision, p_tolerance_pct double precision DEFAULT 5.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_total IS NULL
          OR p_phase_sum IS NULL
            THEN NULL

        WHEN p_phase_sum = 0
            THEN CASE
                WHEN p_total = 0 THEN 'Acceptable'
                ELSE 'Invalid'
            END

        WHEN ABS(p_total - p_phase_sum)
             / ABS(p_phase_sum) * 100 > p_tolerance_pct
            THEN 'Invalid'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_current(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_current(p_value double precision, p_prev_value double precision, p_cb_max_a double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        0.0,
        p_cb_max_a,
        0.0,
        p_cb_max_a,
        NULL,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_current_v2(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_current_v2(value double precision, cb_max double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    margin double precision;
    third  double precision;
BEGIN
    IF value IS NULL OR cb_max IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0 OR value > cb_max THEN RETURN 'Critical'; END IF;

    margin := 0.15 * cb_max;
    third  := margin / 3.0;

    IF value >= margin AND value <= (cb_max - margin) THEN RETURN 'Acceptable'; END IF;

    IF (value >= third AND value < margin)
       OR (value > (cb_max - margin) AND value <= (cb_max - third)) THEN
        RETURN 'Review Required';
    END IF;

    RETURN 'Problematic';  -- remaining zones: 0-third and (cb_max-third)-cb_max
END;
$$;


--
-- Name: classify_current_v2(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_current_v2(value double precision, cb_max double precision, phase_kw double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    margin double precision;
    third  double precision;
BEGIN
    IF value IS NULL OR cb_max IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0 THEN RETURN 'Invalid'; END IF;
    IF value > cb_max THEN RETURN 'Critical'; END IF;

    margin := 0.15 * cb_max;
    third  := margin / 3.0;

    -- Upper side -- unchanged
    IF value > (cb_max - third) THEN RETURN 'Problematic'; END IF;
    IF value > (cb_max - margin) THEN RETURN 'Review Required'; END IF;

    -- Lower fringe zone (0 to margin) -- new agreement-based logic
    IF value < margin THEN
        IF value = 0 AND phase_kw = 0 THEN RETURN 'Acceptable'; END IF;
        IF value > 0 AND phase_kw = 0 THEN RETURN 'Major Problem'; END IF;
        IF value = 0 AND phase_kw <> 0 THEN RETURN 'Major Issue'; END IF;
        RETURN 'Acceptable';  -- both nonzero -- consistent, any magnitude
    END IF;

    -- Safe middle -- unchanged
    RETURN 'Acceptable';
END;
$$;


--
-- Name: classify_energy(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_energy(p_value double precision, p_prev_value double precision, p_user_max double precision DEFAULT NULL::double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        WHEN p_value < 0
            THEN 'Invalid'

        WHEN p_user_max IS NOT NULL
         AND p_value > p_user_max
            THEN 'Critical'

        WHEN p_prev_value IS NOT NULL
         AND p_value < p_prev_value
            THEN 'Anomaly'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_frequency(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_frequency(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        59.0,   -- hard_min (was 59.3)
        61.0,   -- hard_max (was 60.5)
        59.3,   -- acceptable_min (was 59.0)
        60.5,   -- acceptable_max (was 61.0)
        0.0,    -- invalid_min (unchanged)
        61.0,   -- invalid_max (unchanged)
        50.0    -- spike_pct (unchanged)
    );
$$;


--
-- Name: classify_frequency_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_frequency_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 59 OR value > 61 THEN RETURN 'Critical'; END IF;
    IF value >= 59.3 AND value <= 60.5 THEN RETURN 'Acceptable'; END IF;
    RETURN 'Problematic';  -- remaining zones: 59-59.3 and 60.5-61
END;
$$;


--
-- Name: classify_phase_imbalance(double precision, text, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_phase_imbalance(p_imbalance_pct double precision, p_evaluation_status text, p_problematic_threshold_pct double precision DEFAULT 5.0, p_critical_threshold_pct double precision DEFAULT 5.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_imbalance_pct IS NULL
          OR p_evaluation_status IS NULL
            THEN NULL

        WHEN UPPER(p_evaluation_status) = 'OUTSIDE_ACCEPTABLE'
         AND p_imbalance_pct > p_critical_threshold_pct
            THEN 'Critical'

        WHEN UPPER(p_evaluation_status) = 'WITHIN_ACCEPTABLE'
         AND p_imbalance_pct > p_problematic_threshold_pct
            THEN 'Problematic'

        -- Compatibility with previous calls using EVALUATED
        WHEN UPPER(p_evaluation_status) = 'EVALUATED'
         AND p_imbalance_pct > p_critical_threshold_pct
            THEN 'Critical'

        WHEN UPPER(p_evaluation_status) = 'EVALUATED'
         AND p_imbalance_pct > p_problematic_threshold_pct
            THEN 'Problematic'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_power_factor(double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_power_factor(p_value double precision, p_prev_value double precision, p_spike_pct double precision DEFAULT 50.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        WHEN p_value < -1
          OR p_value > 1
            THEN 'Invalid'

        -- Problematic outranks Anomaly
        WHEN p_value < 0.6
            THEN 'Problematic'

        WHEN p_prev_value IS NOT NULL
         AND p_prev_value <> 0
         AND ABS(p_value - p_prev_value)
             / ABS(p_prev_value) * 100 >= p_spike_pct
            THEN 'Anomaly'

        WHEN p_value < 0.8
            THEN 'Review Required'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_power_factor_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_power_factor_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 0.6 OR value > 1 THEN RETURN 'Critical'; END IF;
    IF value >= 0.8 AND value <= 1 THEN RETURN 'Acceptable'; END IF;
    IF value >= 0.78 AND value < 0.8 THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zone: 0.6-0.78
END;
$$;


--
-- Name: classify_reactive_power(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_reactive_power(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        50.0
    );
$$;


--
-- Name: classify_standard(double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_standard(p_value double precision, p_prev_value double precision, p_hard_min double precision, p_hard_max double precision, p_acceptable_min double precision, p_acceptable_max double precision, p_invalid_min double precision DEFAULT NULL::double precision, p_invalid_max double precision DEFAULT NULL::double precision, p_spike_pct double precision DEFAULT 50.0) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE
        WHEN p_value IS NULL THEN NULL

        -- Invalid physical or sanity range
        WHEN p_invalid_min IS NOT NULL
         AND p_value < p_invalid_min
            THEN 'Invalid'

        WHEN p_invalid_max IS NOT NULL
         AND p_value > p_invalid_max
            THEN 'Invalid'

        -- Hard operational limits
        WHEN p_hard_min IS NOT NULL
         AND p_value < p_hard_min
            THEN 'Critical'

        WHEN p_hard_max IS NOT NULL
         AND p_value > p_hard_max
            THEN 'Critical'

        -- High spike against previous reading
        WHEN p_prev_value IS NOT NULL
         AND p_prev_value <> 0
         AND ABS(p_value - p_prev_value)
             / ABS(p_prev_value) * 100 >= p_spike_pct
            THEN 'Anomaly'

        -- Outside acceptable range but not outside hard limit
        WHEN p_acceptable_min IS NOT NULL
         AND p_value < p_acceptable_min
            THEN 'Review Required'

        WHEN p_acceptable_max IS NOT NULL
         AND p_value > p_acceptable_max
            THEN 'Review Required'

        ELSE 'Acceptable'
    END;
$$;


--
-- Name: classify_voltage_line(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_line(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        360.0,
        440.0,
        380.0,
        420.0,
        0.0,
        600.0,
        50.0
    );
$$;


--
-- Name: classify_voltage_line_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_line_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 360 OR value > 440 THEN RETURN 'Critical'; END IF;
    IF value >= 380 AND value <= 420 THEN RETURN 'Acceptable'; END IF;
    IF (value >= 371.2 AND value < 380) OR (value > 420 AND value <= 428.8) THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zones: 360-371.2 and 428.8-440
END;
$$;


--
-- Name: classify_voltage_neutral(double precision, double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_neutral(p_value double precision, p_prev_value double precision) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT silver.classify_standard(
        p_value,
        p_prev_value,
        207.0,
        253.0,
        215.0,
        245.0,
        0.0,
        600.0,
        50.0
    );
$$;


--
-- Name: classify_voltage_neutral_v2(double precision); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.classify_voltage_neutral_v2(value double precision) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    IF value IS NULL THEN RETURN 'Invalid'; END IF;
    IF value < 207 OR value > 253 THEN RETURN 'Critical'; END IF;
    IF value >= 215 AND value <= 245 THEN RETURN 'Acceptable'; END IF;
    IF (value >= 209.94 AND value < 215) OR (value > 245 AND value <= 250.06) THEN RETURN 'Review Required'; END IF;
    RETURN 'Problematic';  -- remaining zones: 207-209.94 and 250.06-253
END;
$$;


--
-- Name: status_rank(text); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.status_rank(p_status text) RETURNS integer
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT CASE p_status
        WHEN 'Acceptable'      THEN 1
        WHEN 'Review Required' THEN 2
        WHEN 'Anomaly'         THEN 3
        WHEN 'Problematic'     THEN 4
        WHEN 'Critical'        THEN 5
        WHEN 'Invalid'         THEN 6
        ELSE 0
    END;
$$;


--
-- Name: worst_status(text[]); Type: FUNCTION; Schema: silver; Owner: -
--

CREATE FUNCTION silver.worst_status(VARIADIC p_statuses text[]) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT status_value
    FROM unnest(p_statuses) AS status_value
    WHERE status_value IS NOT NULL
    ORDER BY silver.status_rank(status_value) DESC
    LIMIT 1;
$$;


--
-- Name: grid_billing_accounts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.grid_billing_accounts_landing AS
 SELECT id,
    ((label)::text COLLATE "C") AS label,
    number,
    ((meter_serial_number)::text COLLATE "C") AS meter_serial_number,
    type_id,
    service_class_id,
    breaker_capacity,
    start_period,
    end_period,
    days,
    facility_id,
    unit_id,
    created_by,
    created_on,
    multiplication_factor
   FROM bronze.grid_billing_accounts;


--
-- Name: VIEW grid_billing_accounts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.grid_billing_accounts_landing IS 'Landing view for bronze.grid_billing_accounts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: grid_billing_accounts_service_classes_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.grid_billing_accounts_service_classes_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    minimal_breaker_capacity,
    maximum_breaker_capacity,
    fee,
    facility_id,
    active,
    created_by,
    created_on
   FROM bronze.grid_billing_accounts_service_classes;


--
-- Name: VIEW grid_billing_accounts_service_classes_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.grid_billing_accounts_service_classes_landing IS 'Landing view for bronze.grid_billing_accounts_service_classes. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: grid_billing_accounts_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.grid_billing_accounts_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.grid_billing_accounts_types;


--
-- Name: VIEW grid_billing_accounts_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.grid_billing_accounts_types_landing IS 'Landing view for bronze.grid_billing_accounts_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_grid_billing_account_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_grid_billing_account_staging AS
 SELECT gba.id AS grid_billing_account_key,
    gba.facility_id AS facility_key,
    gba.unit_id AS zone_key,
    gba.label AS account_label,
    ((gba.number)::text COLLATE "C") AS account_number,
    gba.meter_serial_number,
    gba.type_id AS account_type_key,
    gbat.name AS account_type_name,
    gba.service_class_id AS service_class_key,
    gbasc.name AS service_class_name,
    gba.breaker_capacity,
    gbasc.minimal_breaker_capacity,
    gbasc.maximum_breaker_capacity,
    gbasc.fee AS service_class_fee,
    gba.multiplication_factor,
    gba.start_period,
    gba.end_period,
    gba.days AS configured_billing_days,
    gba.created_on AS source_created_at
   FROM ((silver.grid_billing_accounts_landing gba
     LEFT JOIN silver.grid_billing_accounts_types_landing gbat ON ((gbat.id = gba.type_id)))
     LEFT JOIN silver.grid_billing_accounts_service_classes_landing gbasc ON ((gbasc.id = gba.service_class_id)));


--
-- Name: VIEW dim_grid_billing_account_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_grid_billing_account_staging IS 'Grid billing-account dimension enriched with account type and service class.';


--
-- Name: dim_date_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_date_staging AS
 WITH calendar AS (
         SELECT (gs.gs)::date AS calendar_date
           FROM generate_series(('2024-01-01'::date)::timestamp with time zone, ('2030-12-31'::date)::timestamp with time zone, '1 day'::interval) gs(gs)
        )
 SELECT (to_char((calendar_date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS date_key,
    calendar_date,
    (EXTRACT(year FROM calendar_date))::integer AS calendar_year,
    (EXTRACT(quarter FROM calendar_date))::integer AS calendar_quarter,
    (EXTRACT(month FROM calendar_date))::integer AS month_number,
    (to_char((calendar_date)::timestamp with time zone, 'Month'::text) COLLATE "C") AS month_name,
    (to_char((calendar_date)::timestamp with time zone, 'Mon'::text) COLLATE "C") AS month_short_name,
    (EXTRACT(week FROM calendar_date))::integer AS week_of_year,
    (EXTRACT(isodow FROM calendar_date))::integer AS iso_day_of_week,
    (to_char((calendar_date)::timestamp with time zone, 'Day'::text) COLLATE "C") AS day_name,
    (to_char((calendar_date)::timestamp with time zone, 'Dy'::text) COLLATE "C") AS day_short_name,
    (EXTRACT(day FROM calendar_date))::integer AS day_of_month,
    (EXTRACT(doy FROM calendar_date))::integer AS day_of_year,
    (EXTRACT(isodow FROM calendar_date) = ANY (ARRAY[(6)::numeric, (7)::numeric])) AS is_weekend,
    (date_trunc('month'::text, (calendar_date)::timestamp with time zone))::date AS month_start_date,
    ((date_trunc('month'::text, (calendar_date)::timestamp with time zone) + '1 mon -1 days'::interval))::date AS month_end_date,
    (date_trunc('quarter'::text, (calendar_date)::timestamp with time zone))::date AS quarter_start_date,
    (date_trunc('year'::text, (calendar_date)::timestamp with time zone))::date AS year_start_date
   FROM calendar;


--
-- Name: VIEW dim_date_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_date_staging IS 'Role-playing date dimension for telemetry dates and billing-period dates.';


--
-- Name: energy_bills_tracking_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_bills_tracking_landing AS
 SELECT id,
    facility_id,
    grid_billing_account_id,
    start_period,
    end_period,
    beginning_reading,
    ending_reading,
    consumption_reading,
    cost,
    ((comparing_with_last_bill)::text COLLATE "C") AS comparing_with_last_bill,
    system_beginning_reading,
    system_endng_reading,
    system_consumption_reading,
    system_estimated_cost,
    system_reading_time,
    ((comparing_with_grid_bill)::text COLLATE "C") AS comparing_with_grid_bill,
    created_by,
    created_on,
    invoice_number
   FROM bronze.energy_bills_tracking;


--
-- Name: VIEW energy_bills_tracking_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_bills_tracking_landing IS 'Landing view for bronze.energy_bills_tracking. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: fact_energy_bill_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.fact_energy_bill_staging AS
 SELECT bill.id AS energy_bill_key,
    bill.facility_id AS facility_key,
    account.zone_key,
    bill.grid_billing_account_id AS grid_billing_account_key,
    (to_char((bill.start_period AT TIME ZONE 'UTC'::text), 'YYYYMMDD'::text))::integer AS start_date_key,
    (to_char((bill.end_period AT TIME ZONE 'UTC'::text), 'YYYYMMDD'::text))::integer AS end_date_key,
    bill.start_period,
    bill.end_period,
    ((bill.end_period)::date - (bill.start_period)::date) AS calculated_billing_days,
    ((bill.invoice_number)::text COLLATE "C") AS invoice_number,
    bill.beginning_reading,
    bill.ending_reading,
    bill.consumption_reading AS billed_consumption_kwh,
    bill.cost AS billed_cost,
    bill.system_beginning_reading,
    bill.system_endng_reading AS system_ending_reading,
    bill.system_consumption_reading AS system_consumption_kwh,
    bill.system_estimated_cost,
    (bill.system_consumption_reading - bill.consumption_reading) AS consumption_variance_kwh,
    (bill.system_estimated_cost - bill.cost) AS cost_variance,
    (((bill.system_consumption_reading - bill.consumption_reading) / NULLIF(bill.consumption_reading, (0)::numeric)) * (100)::numeric) AS consumption_variance_percent,
    bill.comparing_with_last_bill,
    bill.comparing_with_grid_bill,
        CASE
            WHEN (bill.system_reading_time IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((bill.system_reading_time)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS system_reading_timestamp_utc,
    bill.created_on AS source_created_at
   FROM (silver.energy_bills_tracking_landing bill
     LEFT JOIN silver.dim_grid_billing_account_staging account ON ((account.grid_billing_account_key = bill.grid_billing_account_id)));


--
-- Name: VIEW fact_energy_bill_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.fact_energy_bill_staging IS 'Energy billing fact containing billed versus system-estimated consumption and cost measures.';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: fact_energy_consumption_validated; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.fact_energy_consumption_validated (
    energy_meter_key uuid,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    meter_label text COLLATE pg_catalog."C",
    reading_timestamp_utc timestamp without time zone,
    reading_timestamp_saudi timestamp without time zone,
    reading_date_saudi date,
    active_energy_cumulative_kwh double precision,
    status_kwh text,
    raw_previous_kwh double precision,
    raw_next_kwh double precision,
    consumption_cleaning_status text,
    previous_valid_timestamp timestamp without time zone,
    previous_valid_kwh double precision,
    validated_kwh_consumption double precision,
    gap_minutes numeric,
    interval_quality text
);


--
-- Name: fact_energy_readings_snapshot; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.fact_energy_readings_snapshot (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    reading_timestamp_utc timestamp without time zone NOT NULL,
    active_energy_cumulative_kwh double precision,
    reactive_energy_cumulative_kvarh double precision,
    apparent_energy_cumulative_kvah double precision,
    voltage_neutral_1_v double precision,
    voltage_neutral_2_v double precision,
    voltage_neutral_3_v double precision,
    voltage_neutral_average_v double precision,
    voltage_line_1_v double precision,
    voltage_line_2_v double precision,
    voltage_line_3_v double precision,
    voltage_line_average_v double precision,
    current_phase_1_a double precision,
    current_phase_2_a double precision,
    current_phase_3_a double precision,
    frequency_hz double precision,
    power_factor_phase_1 double precision,
    power_factor_phase_2 double precision,
    power_factor_phase_3 double precision,
    power_factor_average double precision,
    active_power_phase_1_kw double precision,
    active_power_phase_2_kw double precision,
    active_power_phase_3_kw double precision,
    active_power_total_kw double precision,
    apparent_power_phase_1_kva double precision,
    apparent_power_phase_2_kva double precision,
    apparent_power_phase_3_kva double precision,
    apparent_power_total_kva double precision,
    reactive_power_phase_1_kvar double precision,
    reactive_power_phase_2_kvar double precision,
    reactive_power_phase_3_kvar double precision,
    reactive_power_total_kvar double precision,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_pfa text,
    status_kwh text,
    overall_status text
);


--
-- Name: addresses_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.addresses_landing AS
 SELECT id,
    ((short_address)::text COLLATE "C") AS short_address,
    building_number,
    ((street_name)::text COLLATE "C") AS street_name,
    ((district_name)::text COLLATE "C") AS district_name,
    ((city_name)::text COLLATE "C") AS city_name,
    zip_code,
    additional_number,
    unit_number,
    created_on,
    created_by,
    ((title)::text COLLATE "C") AS title
   FROM bronze.addresses;


--
-- Name: VIEW addresses_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.addresses_landing IS 'Landing view for bronze.addresses. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: facilities_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.facilities_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    unit_id,
    facility_type_id,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    address_id,
    created_on,
    created_by
   FROM bronze.facilities;


--
-- Name: VIEW facilities_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.facilities_landing IS 'Landing view for bronze.facilities. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: facilities_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.facilities_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    created_on,
    created_by
   FROM bronze.facilities_types;


--
-- Name: VIEW facilities_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.facilities_types_landing IS 'Landing view for bronze.facilities_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_facility_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_facility_staging AS
 SELECT f.id AS facility_key,
    f.name AS facility_name,
    f.facility_type_id AS facility_type_key,
    ft.name AS facility_type_name,
    f.latitude,
    f.longitude,
    f.x_coordinate,
    f.y_coordinate,
    f.address_id AS address_key,
    a.title AS address_title,
    a.short_address,
    a.building_number,
    a.street_name,
    a.district_name,
    a.city_name,
    a.zip_code,
    a.additional_number,
    a.unit_number,
    f.created_on AS source_created_at
   FROM ((silver.facilities_landing f
     LEFT JOIN silver.facilities_types_landing ft ON ((ft.id = f.facility_type_id)))
     LEFT JOIN silver.addresses_landing a ON ((a.id = f.address_id)));


--
-- Name: VIEW dim_facility_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_facility_staging IS 'Facility dimension enriched with facility type and address attributes.';


--
-- Name: device_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    gateway_id,
    ((label)::text COLLATE "C") AS label,
    (user_conf)::jsonb AS user_conf,
    ((description)::text COLLATE "C") AS description,
    type_id,
    unit_id,
    created_on,
    created_by,
    facility_id,
    online,
    client_id,
    assembly_date,
    serial_number,
    label_id,
    properties
   FROM bronze.device;


--
-- Name: VIEW device_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_landing IS 'Landing view for bronze.device. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_meters_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meters_landing AS
 SELECT id,
    facility_id,
    grid_billing_account_id,
    device_id,
    phase,
    parent_id,
    maximum_kwh,
    type_id,
    unit_id,
    active,
    created_by,
    created_on,
    ((meter_sn)::text COLLATE "C") AS meter_sn,
    ((meter_label)::text COLLATE "C") AS meter_label
   FROM bronze.energy_meters;


--
-- Name: VIEW energy_meters_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_meters_landing IS 'Landing view for bronze.energy_meters. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.units_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    is_building,
    level,
    parent_id,
    latitude,
    longitude,
    x_coordinate,
    y_coordinate,
    type_id,
    active,
    has_children,
    icon_id,
    ((html_hex_color)::text COLLATE "C") AS html_hex_color,
    (description COLLATE "C") AS description,
    created_on,
    created_by,
    facility_id
   FROM bronze.units;


--
-- Name: VIEW units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.units_landing IS 'Landing view for bronze.units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_meter_mapping_audit_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meter_mapping_audit_staging AS
 WITH source_mapping AS (
         SELECT em.id AS source_energy_meter_id,
            em.device_id,
            em.facility_id,
            em.unit_id AS zone_key,
            u.name AS zone_name,
            d.name AS source_device_name,
            em.meter_label AS source_meter_label,
            em.active AS is_meter_active,
            em.created_on AS meter_source_created_at,
            count(*) OVER (PARTITION BY em.device_id) AS source_meter_records_for_device,
            count(*) OVER (PARTITION BY COALESCE(NULLIF(lower(btrim(em.meter_label)), ''::text), (em.id)::text)) AS source_records_for_meter_label
           FROM ((silver.energy_meters_landing em
             JOIN silver.device_landing d ON ((d.id = em.device_id)))
             LEFT JOIN silver.units_landing u ON ((u.id = em.unit_id)))
        ), business_rules AS (
         SELECT sm.source_energy_meter_id,
            sm.device_id,
            sm.facility_id,
            sm.zone_key,
            sm.zone_name,
            sm.source_device_name,
            sm.source_meter_label,
            sm.is_meter_active,
            sm.meter_source_created_at,
            sm.source_meter_records_for_device,
            sm.source_records_for_meter_label,
            (
                CASE
                    WHEN ((sm.zone_name = 'Zone 03'::text) AND (sm.source_device_name = 'ZN.3-PB_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'ZN.3-PB.1_child__1_ch3pm'::text
                    ELSE sm.source_device_name
                END COLLATE "C") AS canonical_device_name,
            (sm.source_meter_label COLLATE "C") AS canonical_meter_label,
            (
                CASE
                    WHEN ((sm.zone_name = 'Zone 03'::text) AND (sm.source_device_name = 'ZN.3-PB_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'ZONE03_TEAM_CONFIRMED_DEVICE_NAME_CORRECTION'::text
                    WHEN ((sm.zone_name = 'Zone 13'::text) AND (sm.source_device_name = 'ZN.13-PB.1_child__2_ch3pm'::text) AND (sm.source_meter_label = 'ZN.13-PB.2_child__1_ch3pm'::text)) THEN 'ZONE13_TEAM_CONFIRMED_ONE_PANEL_TWO_METERS'::text
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = 'ZN.20-PB.1_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)) THEN 'ZONE20_TEAM_CONFIRMED_DUPLICATE_TO_EXCLUDE'::text
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = sm.source_meter_label)) THEN 'ZONE20_TEAM_CONFIRMED_CANONICAL_MAPPING'::text
                    ELSE 'GENERAL_MAPPING_RULE'::text
                END COLLATE "C") AS business_rule_code,
                CASE
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = 'ZN.20-PB.1_child__1_ch3pm'::text) AND (sm.source_meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)) THEN 100
                    WHEN ((sm.zone_name = 'Zone 20'::text) AND (sm.source_device_name = sm.source_meter_label)) THEN 0
                    WHEN (lower(btrim(COALESCE(sm.source_meter_label, ''::text))) = lower(btrim(COALESCE(sm.source_device_name, ''::text)))) THEN 10
                    ELSE 20
                END AS business_priority
           FROM source_mapping sm
        ), ranked AS (
         SELECT br.source_energy_meter_id,
            br.device_id,
            br.facility_id,
            br.zone_key,
            br.zone_name,
            br.source_device_name,
            br.source_meter_label,
            br.is_meter_active,
            br.meter_source_created_at,
            br.source_meter_records_for_device,
            br.source_records_for_meter_label,
            br.canonical_device_name,
            br.canonical_meter_label,
            br.business_rule_code,
            br.business_priority,
            row_number() OVER (PARTITION BY br.device_id ORDER BY br.business_priority, br.is_meter_active DESC, br.meter_source_created_at, br.source_energy_meter_id) AS canonical_mapping_rank
           FROM business_rules br
        )
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
    (
        CASE
            WHEN (business_rule_code = 'ZONE20_TEAM_CONFIRMED_DUPLICATE_TO_EXCLUDE'::text) THEN 'EXCLUDE'::text
            WHEN (canonical_mapping_rank = 1) THEN 'KEEP'::text
            ELSE 'EXCLUDE'::text
        END COLLATE "C") AS mapping_decision,
    (
        CASE
            WHEN (business_rule_code = 'ZONE03_TEAM_CONFIRMED_DEVICE_NAME_CORRECTION'::text) THEN 'TEAM_CONFIRMED_NAME_CORRECTION'::text
            WHEN (business_rule_code = 'ZONE13_TEAM_CONFIRMED_ONE_PANEL_TWO_METERS'::text) THEN 'TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS'::text
            WHEN ((zone_name = 'Zone 20'::text) AND (canonical_mapping_rank = 1)) THEN 'TEAM_CONFIRMED_DUPLICATE_MAPPING_RESOLVED'::text
            WHEN (canonical_mapping_rank <> 1) THEN 'EXCLUDED_NON_CANONICAL_MAPPING'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1) AND (lower(btrim(COALESCE(source_meter_label, ''::text))) = lower(btrim(COALESCE(source_device_name, ''::text))))) THEN 'VALID'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1)) THEN 'REVIEW_NAME_MISMATCH'::text
            WHEN (lower(btrim(COALESCE(source_meter_label, ''::text))) = lower(btrim(COALESCE(source_device_name, ''::text)))) THEN 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH'::text
            ELSE 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED'::text
        END COLLATE "C") AS mapping_status,
    is_meter_active,
    meter_source_created_at
   FROM ranked;


--
-- Name: devices_categories_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.devices_categories_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((code)::text COLLATE "C") AS code,
    created_on
   FROM bronze.devices_categories;


--
-- Name: VIEW devices_categories_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.devices_categories_landing IS 'Landing view for bronze.devices_categories. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: devices_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.devices_types_landing AS
 SELECT id,
    category_id,
    ((name)::text COLLATE "C") AS name,
    (config_preset)::jsonb AS config_preset,
    created_on,
    created_by,
    code,
    (description COLLATE "C") AS description,
    ((icon)::text COLLATE "C") AS icon,
    properties
   FROM bronze.devices_types;


--
-- Name: VIEW devices_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.devices_types_landing IS 'Landing view for bronze.devices_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_meters_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meters_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.energy_meters_types;


--
-- Name: VIEW energy_meters_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_meters_types_landing IS 'Landing view for bronze.energy_meters_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_energy_meter_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_energy_meter_staging AS
 WITH ranked_mapping AS (
         SELECT d.id AS energy_meter_key,
            em.id AS source_energy_meter_id,
            em.facility_id AS facility_key,
            em.unit_id AS zone_key,
            em.grid_billing_account_id AS grid_billing_account_key,
            em.parent_id AS parent_energy_meter_source_id,
            em.meter_label AS source_meter_label,
            d.name AS source_device_name,
            u.name AS zone_name,
            em.meter_sn AS meter_serial_number,
            em.phase AS phase_count,
            em.maximum_kwh,
            em.type_id AS energy_meter_type_key,
            emt.name AS energy_meter_type_name,
            em.active AS is_meter_active,
            em.created_on AS meter_source_created_at,
            d.label AS device_label,
            d.serial_number AS device_serial_number,
            d.type_id AS device_type_key,
            dt.name AS device_type_name,
            dt.category_id AS device_category_key,
            dc.name AS device_category_name,
            d.gateway_id,
            d.active AS is_device_active,
            d.online AS is_device_online,
            d.assembly_date,
            d.properties AS device_properties,
            count(*) OVER (PARTITION BY em.device_id) AS source_meter_records_for_device,
            count(*) OVER (PARTITION BY COALESCE(NULLIF(lower(btrim(em.meter_label)), ''::text), (em.id)::text)) AS source_records_for_meter_label,
            (lower(btrim(COALESCE(em.meter_label, ''::text))) = lower(btrim(COALESCE(d.name, ''::text)))) AS source_meter_label_matches_device_name,
            (
                CASE
                    WHEN ((u.name = 'Zone 03'::text) AND (d.name = 'ZN.3-PB_child__1_ch3pm'::text) AND (em.meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'ZN.3-PB.1_child__1_ch3pm'::text
                    ELSE d.name
                END COLLATE "C") AS canonical_device_name,
            (em.meter_label COLLATE "C") AS canonical_meter_label,
            row_number() OVER (PARTITION BY em.device_id ORDER BY
                CASE
                    WHEN ((u.name = 'Zone 20'::text) AND (d.name = em.meter_label)) THEN 0
                    WHEN (lower(btrim(COALESCE(em.meter_label, ''::text))) = lower(btrim(COALESCE(d.name, ''::text)))) THEN 10
                    ELSE 20
                END, em.active DESC, em.created_on, em.id) AS canonical_mapping_rank
           FROM (((((silver.energy_meters_landing em
             JOIN silver.device_landing d ON ((d.id = em.device_id)))
             LEFT JOIN silver.units_landing u ON ((u.id = em.unit_id)))
             LEFT JOIN silver.energy_meters_types_landing emt ON ((emt.id = em.type_id)))
             LEFT JOIN silver.devices_types_landing dt ON ((dt.id = d.type_id)))
             LEFT JOIN silver.devices_categories_landing dc ON ((dc.id = dt.category_id)))
          WHERE (NOT ((em.device_id = '9574e049-9fb7-46db-9f8c-b3da0666aea0'::uuid) AND (em.meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)))
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    parent_energy_meter_source_id,
    canonical_meter_label AS meter_label,
    meter_serial_number,
    phase_count,
    maximum_kwh,
    energy_meter_type_key,
    energy_meter_type_name,
    is_meter_active,
    canonical_device_name AS device_name,
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
    (lower(btrim(COALESCE(canonical_meter_label, ''::text))) = lower(btrim(COALESCE(canonical_device_name, ''::text)))) AS meter_label_matches_device_name,
    (
        CASE
            WHEN ((zone_name = 'Zone 03'::text) AND (source_device_name = 'ZN.3-PB_child__1_ch3pm'::text) AND (source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text)) THEN 'TEAM_CONFIRMED_NAME_CORRECTION'::text
            WHEN ((zone_name = 'Zone 13'::text) AND (source_device_name = 'ZN.13-PB.1_child__2_ch3pm'::text) AND (source_meter_label = 'ZN.13-PB.2_child__1_ch3pm'::text)) THEN 'TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1) AND source_meter_label_matches_device_name) THEN 'VALID'::text
            WHEN ((source_meter_records_for_device = 1) AND (source_records_for_meter_label = 1)) THEN 'REVIEW_NAME_MISMATCH'::text
            WHEN source_meter_label_matches_device_name THEN 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH'::text
            ELSE 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED'::text
        END COLLATE "C") AS mapping_status,
    meter_source_created_at
   FROM ranked_mapping
  WHERE (canonical_mapping_rank = 1);


--
-- Name: VIEW dim_energy_meter_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_energy_meter_staging IS 'Canonical energy-meter/device dimension. One row per reporting device; duplicate source mappings remain flagged.';


--
-- Name: data_quality_summary; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.data_quality_summary (
    energy_meter_key uuid NOT NULL,
    meter_label text,
    total_readings integer,
    overall_acceptable_count integer,
    overall_review_required_count integer,
    overall_anomaly_count integer,
    overall_problematic_count integer,
    overall_critical_count integer,
    overall_invalid_count integer,
    computed_at timestamp without time zone DEFAULT now()
);


--
-- Name: units_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.units_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    global_type,
    default_level,
    default_type_for_its_level,
    icon_id,
    created_on,
    created_by,
    facility_id
   FROM bronze.units_types;


--
-- Name: VIEW units_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.units_types_landing IS 'Landing view for bronze.units_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_zone_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.dim_zone_staging AS
 SELECT u.id AS zone_key,
    u.facility_id AS facility_key,
    u.parent_id AS parent_zone_key,
    parent_u.name AS parent_zone_name,
    u.name AS zone_name,
    u.type_id AS zone_type_key,
    ut.name AS zone_type_name,
    u.level AS hierarchy_level,
    u.is_building,
    u.active AS is_active,
    u.has_children,
    u.latitude,
    u.longitude,
    u.x_coordinate,
    u.y_coordinate,
    u.html_hex_color,
    u.description,
    u.created_on AS source_created_at
   FROM ((silver.units_landing u
     LEFT JOIN silver.units_landing parent_u ON ((parent_u.id = u.parent_id)))
     LEFT JOIN silver.units_types_landing ut ON ((ut.id = u.type_id)));


--
-- Name: VIEW dim_zone_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.dim_zone_staging IS 'Zone/unit dimension containing facility and parent-child hierarchy keys.';


--
-- Name: agg_energy_1d; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1d (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: agg_energy_1h; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1h (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: agg_energy_1month; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1month (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text,
    loaded_at timestamp without time zone DEFAULT now()
);


--
-- Name: agg_energy_1week; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_1week (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text,
    loaded_at timestamp without time zone DEFAULT now()
);


--
-- Name: agg_energy_30min; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_30min (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: agg_energy_3d; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_3d (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text,
    loaded_at timestamp without time zone DEFAULT now()
);


--
-- Name: agg_energy_4h; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.agg_energy_4h (
    energy_meter_key uuid NOT NULL,
    facility_key uuid,
    zone_key uuid,
    grid_billing_account_key uuid,
    bucket_start_utc timestamp without time zone NOT NULL,
    kwh_consumption double precision,
    kvarh_consumption double precision,
    kvah_consumption double precision,
    avg_vn1 double precision,
    min_vn1 double precision,
    max_vn1 double precision,
    avg_vn2 double precision,
    min_vn2 double precision,
    max_vn2 double precision,
    avg_vn3 double precision,
    min_vn3 double precision,
    max_vn3 double precision,
    avg_v1 double precision,
    min_v1 double precision,
    max_v1 double precision,
    avg_v2 double precision,
    min_v2 double precision,
    max_v2 double precision,
    avg_v3 double precision,
    min_v3 double precision,
    max_v3 double precision,
    avg_amp1 double precision,
    max_amp1 double precision,
    avg_amp2 double precision,
    max_amp2 double precision,
    avg_amp3 double precision,
    max_amp3 double precision,
    avg_frequency_hz double precision,
    min_frequency_hz double precision,
    max_frequency_hz double precision,
    avg_pf1 double precision,
    min_pf1 double precision,
    avg_pf2 double precision,
    min_pf2 double precision,
    avg_pf3 double precision,
    min_pf3 double precision,
    avg_kw1 double precision,
    max_kw1 double precision,
    avg_kw2 double precision,
    max_kw2 double precision,
    avg_kw3 double precision,
    max_kw3 double precision,
    avg_tkw double precision,
    max_tkw double precision,
    avg_kva1 double precision,
    max_kva1 double precision,
    avg_kva2 double precision,
    max_kva2 double precision,
    avg_kva3 double precision,
    max_kva3 double precision,
    avg_tkva double precision,
    max_tkva double precision,
    avg_kvar1 double precision,
    max_kvar1 double precision,
    avg_kvar2 double precision,
    max_kvar2 double precision,
    avg_kvar3 double precision,
    max_kvar3 double precision,
    avg_tkvar double precision,
    max_tkvar double precision,
    reading_count integer,
    loaded_at timestamp without time zone DEFAULT now(),
    status_vn1 text,
    status_vn2 text,
    status_vn3 text,
    status_v1 text,
    status_v2 text,
    status_v3 text,
    status_amp1 text,
    status_amp2 text,
    status_amp3 text,
    status_hz text,
    status_pf1 text,
    status_pf2 text,
    status_pf3 text,
    status_kw1 text,
    status_kw2 text,
    status_kw3 text,
    status_tkw text,
    status_kva1 text,
    status_kva2 text,
    status_kva3 text,
    status_tkva text,
    status_kvar1 text,
    status_kvar2 text,
    status_kvar3 text,
    status_tkvar text,
    overall_status text
);


--
-- Name: alarm_acknowledgement_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_acknowledgement_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title
   FROM bronze.alarm_acknowledgement_types;


--
-- Name: VIEW alarm_acknowledgement_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_acknowledgement_types_landing IS 'Landing view for bronze.alarm_acknowledgement_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_acknowledgements_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_acknowledgements_landing AS
 SELECT id,
    alarm_configuration_id,
    device_id,
    acknowledged_until,
    "timestamp",
    acknowledged_by
   FROM bronze.alarm_acknowledgements;


--
-- Name: VIEW alarm_acknowledgements_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_acknowledgements_landing IS 'Landing view for bronze.alarm_acknowledgements. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_configurations_history_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_configurations_history_landing AS
 SELECT id,
    (payload)::jsonb AS payload,
    alarm_configuration_id,
    created_by,
    updated_by,
    updated_at
   FROM bronze.alarm_configurations_history;


--
-- Name: VIEW alarm_configurations_history_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_configurations_history_landing IS 'Landing view for bronze.alarm_configurations_history. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_configurations_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_configurations_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description,
    (details)::jsonb AS details,
    severity_id,
    alarm_type_id,
    created_on,
    created_by,
    active
   FROM bronze.alarm_configurations;


--
-- Name: VIEW alarm_configurations_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_configurations_landing IS 'Landing view for bronze.alarm_configurations. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_contact_groups_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_contact_groups_landing AS
 SELECT alarm_configuration_id,
    contact_label_id,
    contact_after,
    level
   FROM bronze.alarm_contact_groups;


--
-- Name: VIEW alarm_contact_groups_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_contact_groups_landing IS 'Landing view for bronze.alarm_contact_groups. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_contact_methods_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_contact_methods_landing AS
 SELECT contact_after,
    notification_interval,
    contact_method_id,
    alarm_configuration_id
   FROM bronze.alarm_contact_methods;


--
-- Name: VIEW alarm_contact_methods_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_contact_methods_landing IS 'Landing view for bronze.alarm_contact_methods. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_contacts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_contacts_landing AS
 SELECT alarm_configuration_id,
    level,
    contact_after,
    contact_id
   FROM bronze.alarm_contacts;


--
-- Name: VIEW alarm_contacts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_contacts_landing IS 'Landing view for bronze.alarm_contacts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_device_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_device_landing AS
 SELECT device_id,
    alarm_level_id,
    alarm_configuration_id,
    active
   FROM bronze.alarm_device;


--
-- Name: VIEW alarm_device_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_device_landing IS 'Landing view for bronze.alarm_device. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_device_mapping_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_device_mapping_landing AS
 SELECT alarm_configuration_id,
    device_type_id,
    device_category_id,
    alarm_level_id,
    unit_id
   FROM bronze.alarm_device_mapping;


--
-- Name: VIEW alarm_device_mapping_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_device_mapping_landing IS 'Landing view for bronze.alarm_device_mapping. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_levels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_levels_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description
   FROM bronze.alarm_levels;


--
-- Name: VIEW alarm_levels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_levels_landing IS 'Landing view for bronze.alarm_levels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_log_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_log_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title
   FROM bronze.alarm_log_types;


--
-- Name: VIEW alarm_log_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_log_types_landing IS 'Landing view for bronze.alarm_log_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_logs_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_logs_landing AS
 SELECT (details)::jsonb AS details,
    alarm_configuration_id,
    log_type_id,
    device_id,
    "timestamp"
   FROM bronze.alarm_logs;


--
-- Name: VIEW alarm_logs_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_logs_landing IS 'Landing view for bronze.alarm_logs. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_notifications_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_notifications_landing AS
 SELECT alarm_configuration_id,
    device_id,
    notification_id
   FROM bronze.alarm_notifications;


--
-- Name: VIEW alarm_notifications_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_notifications_landing IS 'Landing view for bronze.alarm_notifications. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_telemetry_keys_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_telemetry_keys_landing AS
 SELECT alarm_configuration_id,
    telemetry_key_id,
    (details)::jsonb AS details
   FROM bronze.alarm_telemetry_keys;


--
-- Name: VIEW alarm_telemetry_keys_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_telemetry_keys_landing IS 'Landing view for bronze.alarm_telemetry_keys. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarm_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarm_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description,
    created_on,
    active
   FROM bronze.alarm_types;


--
-- Name: VIEW alarm_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarm_types_landing IS 'Landing view for bronze.alarm_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarms_severities_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarms_severities_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    ((icon)::text COLLATE "C") AS icon,
    ((hex_color)::text COLLATE "C") AS hex_color,
    (default_configs)::jsonb AS default_configs,
    created_on,
    created_by
   FROM bronze.alarms_severities;


--
-- Name: VIEW alarms_severities_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarms_severities_landing IS 'Landing view for bronze.alarms_severities. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: alarms_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.alarms_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.alarms_types;


--
-- Name: VIEW alarms_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.alarms_types_landing IS 'Landing view for bronze.alarms_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: appliance_category_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.appliance_category_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((icon)::text COLLATE "C") AS icon,
    created_on
   FROM bronze.appliance_category;


--
-- Name: VIEW appliance_category_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.appliance_category_landing IS 'Landing view for bronze.appliance_category. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: appliances_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.appliances_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    category_id,
    unit_id,
    meter_id,
    facility_id,
    created_on,
    created_by
   FROM bronze.appliances;


--
-- Name: VIEW appliances_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.appliances_landing IS 'Landing view for bronze.appliances. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: attempted_logins_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.attempted_logins_landing AS
 SELECT id,
    user_id,
    ((ip_address)::text COLLATE "C") AS ip_address,
    is_successful,
    ((details)::text COLLATE "C") AS details,
    created_on
   FROM bronze.attempted_logins;


--
-- Name: VIEW attempted_logins_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.attempted_logins_landing IS 'Landing view for bronze.attempted_logins. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: banned_jtis_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.banned_jtis_landing AS
 SELECT id,
    refresh_token_jti,
    user_id,
    created_on
   FROM bronze.banned_jtis;


--
-- Name: VIEW banned_jtis_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.banned_jtis_landing IS 'Landing view for bronze.banned_jtis. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: budget_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.budget_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    created_on
   FROM bronze.budget_types;


--
-- Name: VIEW budget_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.budget_types_landing IS 'Landing view for bronze.budget_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: budgets_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.budgets_landing AS
 SELECT id,
    value,
    type_id,
    facility_id,
    created_by,
    created_on
   FROM bronze.budgets;


--
-- Name: VIEW budgets_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.budgets_landing IS 'Landing view for bronze.budgets. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: clients_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.clients_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((code)::text COLLATE "C") AS code,
    facility_id,
    created_on
   FROM bronze.clients;


--
-- Name: VIEW clients_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.clients_landing IS 'Landing view for bronze.clients. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: consumption_categories_grid_billing_accounts_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.consumption_categories_grid_billing_accounts_types_landing AS
 SELECT consumption_category_id,
    grid_billing_account_type_id,
    fee_per_kwh,
    created_by,
    created_on
   FROM bronze.consumption_categories_grid_billing_accounts_types;


--
-- Name: VIEW consumption_categories_grid_billing_accounts_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.consumption_categories_grid_billing_accounts_types_landing IS 'Landing view for bronze.consumption_categories_grid_billing_accounts_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: consumption_categories_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.consumption_categories_landing AS
 SELECT id,
    facility_id,
    ((name)::text COLLATE "C") AS name,
    maximum_kwh,
    minimum_kwh,
    active,
    created_by,
    created_on
   FROM bronze.consumption_categories;


--
-- Name: VIEW consumption_categories_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.consumption_categories_landing IS 'Landing view for bronze.consumption_categories. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contact_labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contact_labels_landing AS
 SELECT contact_id,
    label_id
   FROM bronze.contact_labels;


--
-- Name: VIEW contact_labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contact_labels_landing IS 'Landing view for bronze.contact_labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contact_method_mapping_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contact_method_mapping_landing AS
 SELECT contact_id,
    contact_method_id
   FROM bronze.contact_method_mapping;


--
-- Name: VIEW contact_method_mapping_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contact_method_mapping_landing IS 'Landing view for bronze.contact_method_mapping. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contact_methods_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contact_methods_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((description)::text COLLATE "C") AS description,
    created_on
   FROM bronze.contact_methods;


--
-- Name: VIEW contact_methods_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contact_methods_landing IS 'Landing view for bronze.contact_methods. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: contacts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.contacts_landing AS
 SELECT id,
    ((full_name)::text COLLATE "C") AS full_name,
    ((description)::text COLLATE "C") AS description,
    (preferences)::jsonb AS preferences,
    user_id,
    ((email)::text COLLATE "C") AS email,
    ((phone_number)::text COLLATE "C") AS phone_number,
    created_on,
    created_by
   FROM bronze.contacts;


--
-- Name: VIEW contacts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.contacts_landing IS 'Landing view for bronze.contacts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: deleted_schedules_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.deleted_schedules_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    start_datetime,
    end_datetime,
    schedule_duration,
    triggers,
    active,
    created_on,
    created_by,
    deleted_by,
    deleted_at,
    deleted_schedule_units,
    deleted_schedule_controllers
   FROM bronze.deleted_schedules;


--
-- Name: VIEW deleted_schedules_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.deleted_schedules_landing IS 'Landing view for bronze.deleted_schedules. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_control_labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_control_labels_landing AS
 SELECT device_control_id,
    label_id,
    created_by,
    created_on
   FROM bronze.device_control_labels;


--
-- Name: VIEW device_control_labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_control_labels_landing IS 'Landing view for bronze.device_control_labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_control_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_control_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name
   FROM bronze.device_control_types;


--
-- Name: VIEW device_control_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_control_types_landing IS 'Landing view for bronze.device_control_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_controls_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_controls_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    device_id,
    unit_id,
    ((icon)::text COLLATE "C") AS icon,
    ((icon_color)::text COLLATE "C") AS icon_color,
    config,
    created_by,
    ((telemetry_key)::text COLLATE "C") AS telemetry_key,
    (description COLLATE "C") AS description
   FROM bronze.device_controls;


--
-- Name: VIEW device_controls_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_controls_landing IS 'Landing view for bronze.device_controls. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_controls_unit_pinned_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_controls_unit_pinned_landing AS
 SELECT id,
    user_id,
    unit_id,
    pinned,
    visible
   FROM bronze.device_controls_unit_pinned;


--
-- Name: VIEW device_controls_unit_pinned_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_controls_unit_pinned_landing IS 'Landing view for bronze.device_controls_unit_pinned. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_credentials_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_credentials_landing AS
 SELECT ((cred_id)::text COLLATE "C") AS cred_id,
    device_id,
    ((cred_val)::text COLLATE "C") AS cred_val,
    ((cred_type)::text COLLATE "C") AS cred_type,
    ((extra_credentials)::text COLLATE "C") AS extra_credentials,
    created_on,
    ((username)::text COLLATE "C") AS username,
    ((uudid)::text COLLATE "C") AS uudid
   FROM bronze.device_credentials;


--
-- Name: VIEW device_credentials_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_credentials_landing IS 'Landing view for bronze.device_credentials. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_sensors_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_sensors_landing AS
 SELECT device_id,
    sensor_id,
    ((telemetry_key)::text COLLATE "C") AS telemetry_key,
    telemetry_key_id,
    control_id,
    ((category_name)::text COLLATE "C") AS category_name,
    created_on,
    created_by
   FROM bronze.device_sensors;


--
-- Name: VIEW device_sensors_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_sensors_landing IS 'Landing view for bronze.device_sensors. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: device_time_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.device_time_landing AS
 SELECT device_id,
    "timestamp",
    online,
        CASE
            WHEN (value IS NULL) THEN NULL::double precision
            ELSE (round((value)::numeric, 9))::double precision
        END AS value,
    ((telemetry_key_name)::text COLLATE "C") AS telemetry_key_name,
    on_time,
    off_time,
    run_time
   FROM bronze.device_time;


--
-- Name: VIEW device_time_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.device_time_landing IS 'Landing view for bronze.device_time. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: dim_meter_cb_rating; Type: TABLE; Schema: silver; Owner: -
--

CREATE TABLE silver.dim_meter_cb_rating (
    energy_meter_key uuid NOT NULL,
    cb_max_rating_a double precision NOT NULL,
    updated_at timestamp without time zone DEFAULT now()
);


--
-- Name: dq_device_cadence_staging; Type: MATERIALIZED VIEW; Schema: silver; Owner: -
--

CREATE MATERIALIZED VIEW silver.dq_device_cadence_staging AS
 WITH tkw_readings AS (
         SELECT t.device_id,
            t."timestamp",
            lag(t."timestamp") OVER (PARTITION BY t.device_id ORDER BY t."timestamp") AS previous_timestamp
           FROM ((bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON (((td.id = t.key_id) AND ((td.key)::text = 'TkW'::text))))
             JOIN silver.dim_energy_meter_staging m ON ((m.energy_meter_key = t.device_id)))
        ), reading_coverage AS (
         SELECT t.device_id,
            count(*) AS total_tkw_reading_count,
            min(t."timestamp") AS first_timestamp_ms,
            max(t."timestamp") AS last_timestamp_ms,
            (count(DISTINCT ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date))::integer AS days_with_tkw_data
           FROM tkw_readings t
          GROUP BY t.device_id
        ), all_gaps AS (
         SELECT tkw_readings.device_id,
            tkw_readings."timestamp",
            tkw_readings.previous_timestamp,
            (((tkw_readings."timestamp" - tkw_readings.previous_timestamp))::numeric / 1000.0) AS gap_seconds
           FROM tkw_readings
          WHERE (tkw_readings.previous_timestamp IS NOT NULL)
        ), cadence_candidates AS (
         SELECT all_gaps.device_id,
            all_gaps."timestamp",
            all_gaps.previous_timestamp,
            all_gaps.gap_seconds
           FROM all_gaps
          WHERE ((all_gaps.gap_seconds >= (30)::numeric) AND (all_gaps.gap_seconds <= (1800)::numeric))
        ), cadence_statistics AS (
         SELECT cadence_candidates.device_id,
            count(*) AS baseline_interval_count,
            percentile_cont((0.10)::double precision) WITHIN GROUP (ORDER BY ((cadence_candidates.gap_seconds)::double precision)) AS p10_gap_seconds,
            percentile_cont((0.50)::double precision) WITHIN GROUP (ORDER BY ((cadence_candidates.gap_seconds)::double precision)) AS observed_gap_seconds,
            percentile_cont((0.90)::double precision) WITHIN GROUP (ORDER BY ((cadence_candidates.gap_seconds)::double precision)) AS p90_gap_seconds,
            avg(cadence_candidates.gap_seconds) AS average_candidate_gap_seconds,
            stddev_samp(cadence_candidates.gap_seconds) AS candidate_gap_stddev_seconds
           FROM cadence_candidates
          GROUP BY cadence_candidates.device_id
        ), gap_totals AS (
         SELECT all_gaps.device_id,
            count(*) AS all_interval_count,
            count(*) FILTER (WHERE (all_gaps.gap_seconds > (1800)::numeric)) AS gap_over_30_minutes_count,
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
            COALESCE(gt.gap_over_30_minutes_count, (0)::bigint) AS gap_over_30_minutes_count,
            gt.maximum_observed_gap_seconds
           FROM ((((silver.dim_energy_meter_staging m
             JOIN silver.dim_zone_staging z ON ((z.zone_key = m.zone_key)))
             LEFT JOIN reading_coverage rc ON ((rc.device_id = m.energy_meter_key)))
             LEFT JOIN cadence_statistics cs ON ((cs.device_id = m.energy_meter_key)))
             LEFT JOIN gap_totals gt ON ((gt.device_id = m.energy_meter_key)))
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
            WHEN (first_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((first_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS first_reading_utc,
        CASE
            WHEN (last_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((last_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS last_reading_utc,
        CASE
            WHEN (first_timestamp_ms IS NULL) THEN NULL::date
            ELSE ((to_timestamp((((first_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date
        END AS first_reading_date,
        CASE
            WHEN (last_timestamp_ms IS NULL) THEN NULL::date
            ELSE ((to_timestamp((((last_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date
        END AS last_reading_date,
    baseline_interval_count,
    all_interval_count,
    round((p10_gap_seconds)::numeric, 3) AS p10_gap_seconds,
    300.000 AS nominal_gap_seconds,
    5.000 AS nominal_gap_minutes,
    288 AS nominal_expected_daily_reading_count,
    round((observed_gap_seconds)::numeric, 3) AS observed_gap_seconds,
    round(((observed_gap_seconds / (60.0)::double precision))::numeric, 3) AS observed_gap_minutes,
        CASE
            WHEN (observed_gap_seconds IS NULL) THEN NULL::integer
            ELSE (round(((86400.0)::double precision / observed_gap_seconds)))::integer
        END AS observed_expected_daily_reading_count,
    round((observed_gap_seconds)::numeric, 3) AS expected_gap_seconds,
    round(((observed_gap_seconds / (60.0)::double precision))::numeric, 3) AS expected_gap_minutes,
        CASE
            WHEN (observed_gap_seconds IS NULL) THEN NULL::integer
            ELSE (round(((86400.0)::double precision / observed_gap_seconds)))::integer
        END AS expected_daily_reading_count,
    round((p90_gap_seconds)::numeric, 3) AS p90_gap_seconds,
    round(((p90_gap_seconds - p10_gap_seconds))::numeric, 3) AS cadence_spread_seconds,
    round(average_candidate_gap_seconds, 3) AS average_candidate_gap_seconds,
    round(candidate_gap_stddev_seconds, 3) AS candidate_gap_stddev_seconds,
    round(((observed_gap_seconds - (300.0)::double precision))::numeric, 3) AS variance_from_nominal_seconds,
    round(((((observed_gap_seconds - (300.0)::double precision) / (300.0)::double precision))::numeric * (100)::numeric), 3) AS variance_from_nominal_percent,
    gap_over_30_minutes_count,
    round(maximum_observed_gap_seconds, 3) AS maximum_observed_gap_seconds,
    (
        CASE
            WHEN ((observed_gap_seconds IS NULL) OR (baseline_interval_count < 100)) THEN 'INSUFFICIENT_BASELINE'::text
            WHEN ((p90_gap_seconds - p10_gap_seconds) > (60)::double precision) THEN 'UNSTABLE_CADENCE_REVIEW'::text
            WHEN (abs((observed_gap_seconds - (300)::double precision)) <= (15)::double precision) THEN 'STANDARD_APPROXIMATELY_5_MINUTES'::text
            ELSE 'NON_STANDARD_STABLE_CADENCE'::text
        END COLLATE "C") AS cadence_status,
    (
        CASE
            WHEN ((observed_gap_seconds IS NULL) OR (baseline_interval_count < 100)) THEN 'INSUFFICIENT_BASELINE'::text
            WHEN ((p90_gap_seconds - p10_gap_seconds) > (60)::double precision) THEN 'UNSTABLE_CADENCE_REVIEW'::text
            WHEN (abs((observed_gap_seconds - (300)::double precision)) <= (15)::double precision) THEN 'MEETS_NOMINAL_APPROX_5_MINUTE_CADENCE'::text
            ELSE 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text
        END COLLATE "C") AS nominal_cadence_status,
        CASE
            WHEN ((observed_gap_seconds IS NULL) OR (baseline_interval_count < 100)) THEN false
            WHEN ((p90_gap_seconds - p10_gap_seconds) <= (60)::double precision) THEN true
            ELSE false
        END AS cadence_baseline_is_reliable
   FROM cadence_base
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW dq_device_cadence_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON MATERIALIZED VIEW silver.dq_device_cadence_staging IS 'One row per canonical meter. Stores both the nominal 300-second/288-reading target and each device''s observed historical cadence. Source telemetry is unchanged.';


--
-- Name: COLUMN dq_device_cadence_staging.nominal_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_device_cadence_staging.nominal_expected_daily_reading_count IS 'Official nominal full-day target: 288 readings at five-minute cadence.';


--
-- Name: COLUMN dq_device_cadence_staging.observed_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_device_cadence_staging.observed_expected_daily_reading_count IS 'Device-specific expected count calculated from the historical median TkW timestamp gap.';


--
-- Name: COLUMN dq_device_cadence_staging.expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_device_cadence_staging.expected_daily_reading_count IS 'Backward-compatible alias for observed_expected_daily_reading_count.';


--
-- Name: dq_meter_daily_completeness_staging; Type: MATERIALIZED VIEW; Schema: silver; Owner: -
--

CREATE MATERIALIZED VIEW silver.dq_meter_daily_completeness_staging AS
 WITH tkw_readings AS (
         SELECT t.device_id,
            t."timestamp",
            ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date AS reading_date,
            lag(t."timestamp") OVER (PARTITION BY t.device_id, (((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date) ORDER BY t."timestamp") AS previous_timestamp_same_day
           FROM ((bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON (((td.id = t.key_id) AND ((td.key)::text = 'TkW'::text))))
             JOIN silver.dq_device_cadence_staging b ON (((b.energy_meter_key = t.device_id) AND b.cadence_baseline_is_reliable)))
        ), daily_observed AS (
         SELECT r.device_id,
            r.reading_date,
            (count(DISTINCT r."timestamp"))::integer AS actual_reading_count,
            min(r."timestamp") AS first_timestamp_ms,
            max(r."timestamp") AS last_timestamp_ms,
            max((((r."timestamp" - r.previous_timestamp_same_day))::numeric / 1000.0)) FILTER (WHERE (r.previous_timestamp_same_day IS NOT NULL)) AS maximum_within_day_gap_seconds
           FROM tkw_readings r
          GROUP BY r.device_id, r.reading_date
        ), daily_large_gaps AS (
         SELECT r.device_id,
            r.reading_date,
            (count(*) FILTER (WHERE ((r.previous_timestamp_same_day IS NOT NULL) AND ((((r."timestamp" - r.previous_timestamp_same_day))::numeric / 1000.0) > (b.observed_gap_seconds * 1.5)))))::integer AS large_gap_count
           FROM (tkw_readings r
             JOIN silver.dq_device_cadence_staging b ON ((b.energy_meter_key = r.device_id)))
          GROUP BY r.device_id, r.reading_date
        ), device_calendar AS (
         SELECT b.energy_meter_key,
            (gs.reading_date)::date AS reading_date
           FROM (silver.dq_device_cadence_staging b
             CROSS JOIN LATERAL generate_series((b.first_reading_date)::timestamp without time zone, (b.last_reading_date)::timestamp without time zone, '1 day'::interval) gs(reading_date))
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
            GREATEST((b.nominal_expected_daily_reading_count - COALESCE(o.actual_reading_count, 0)), 0) AS nominal_missing_reading_count,
            GREATEST((b.observed_expected_daily_reading_count - COALESCE(o.actual_reading_count, 0)), 0) AS observed_missing_reading_count,
            GREATEST((COALESCE(o.actual_reading_count, 0) - b.nominal_expected_daily_reading_count), 0) AS nominal_extra_reading_count,
            GREATEST((COALESCE(o.actual_reading_count, 0) - b.observed_expected_daily_reading_count), 0) AS observed_extra_reading_count,
            COALESCE(lg.large_gap_count, 0) AS large_gap_count,
            o.maximum_within_day_gap_seconds,
            o.first_timestamp_ms,
            o.last_timestamp_ms,
            (((COALESCE(o.actual_reading_count, 0))::numeric / (NULLIF(b.nominal_expected_daily_reading_count, 0))::numeric) * (100)::numeric) AS nominal_raw_completeness_percent,
            (((COALESCE(o.actual_reading_count, 0))::numeric / (NULLIF(b.observed_expected_daily_reading_count, 0))::numeric) * (100)::numeric) AS observed_raw_completeness_percent
           FROM (((device_calendar c
             JOIN silver.dq_device_cadence_staging b ON ((b.energy_meter_key = c.energy_meter_key)))
             LEFT JOIN daily_observed o ON (((o.device_id = c.energy_meter_key) AND (o.reading_date = c.reading_date))))
             LEFT JOIN daily_large_gaps lg ON (((lg.device_id = c.energy_meter_key) AND (lg.reading_date = c.reading_date))))
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
            (
                CASE
                    WHEN (q.actual_reading_count = 0) THEN 'CRITICAL_NO_DATA'::text
                    WHEN (q.actual_reading_count >= q.observed_expected_daily_reading_count) THEN 'COMPLETE_TO_OBSERVED_BASELINE'::text
                    WHEN ((q.observed_missing_reading_count <= 1) AND (q.large_gap_count = 0)) THEN 'COMPLETE_WITH_DAY_BOUNDARY_VARIATION'::text
                    WHEN (q.observed_raw_completeness_percent >= (95)::numeric) THEN 'WARNING_MINOR_MISSING_INTERVALS'::text
                    WHEN (q.observed_raw_completeness_percent >= (80)::numeric) THEN 'LOW_COMPLETENESS_REVIEW'::text
                    ELSE 'CRITICAL_INCOMPLETE_DAY'::text
                END COLLATE "C") AS observed_daily_quality_status,
            (
                CASE
                    WHEN (q.actual_reading_count = 0) THEN 'CRITICAL_NO_DATA'::text
                    WHEN ((q.nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) AND (q.observed_raw_completeness_percent >= (99)::numeric) AND (q.large_gap_count = 0)) THEN 'BELOW_288_DUE_TO_STABLE_NONSTANDARD_CADENCE'::text
                    WHEN (q.nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) THEN 'NONSTANDARD_CADENCE_WITH_DATA_GAPS'::text
                    WHEN ((q.actual_reading_count >= q.nominal_expected_daily_reading_count) AND (q.large_gap_count = 0)) THEN 'MEETS_NOMINAL_288_COUNT'::text
                    WHEN ((q.actual_reading_count = (q.nominal_expected_daily_reading_count - 1)) AND (q.large_gap_count = 0)) THEN 'ONE_READING_BELOW_NOMINAL_BOUNDARY_VARIATION'::text
                    WHEN (q.nominal_raw_completeness_percent >= (95)::numeric) THEN 'BELOW_NOMINAL_COUNT_MINOR'::text
                    WHEN (q.nominal_raw_completeness_percent >= (80)::numeric) THEN 'BELOW_NOMINAL_COUNT_REVIEW'::text
                    ELSE 'CRITICAL_BELOW_NOMINAL_COUNT'::text
                END COLLATE "C") AS nominal_reporting_status
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
    round(LEAST(nominal_raw_completeness_percent, (100)::numeric), 2) AS nominal_completeness_percent,
    round(observed_raw_completeness_percent, 2) AS observed_raw_completeness_percent,
    round(LEAST(observed_raw_completeness_percent, (100)::numeric), 2) AS observed_completeness_percent,
    round(observed_raw_completeness_percent, 2) AS raw_completeness_percent,
    round(LEAST(observed_raw_completeness_percent, (100)::numeric), 2) AS completeness_percent,
    large_gap_count,
    round(maximum_within_day_gap_seconds, 3) AS maximum_within_day_gap_seconds,
        CASE
            WHEN (first_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((first_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS first_reading_utc,
        CASE
            WHEN (last_timestamp_ms IS NULL) THEN NULL::timestamp without time zone
            ELSE (to_timestamp((((last_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text)
        END AS last_reading_utc,
    cadence_status,
    nominal_cadence_status,
    observed_daily_quality_status,
    observed_daily_quality_status AS daily_quality_status,
    nominal_reporting_status,
    (
        CASE
            WHEN ((actual_reading_count = 0) OR (observed_raw_completeness_percent < (80)::numeric)) THEN 'CRITICAL'::text
            WHEN (observed_raw_completeness_percent < (95)::numeric) THEN 'ERROR'::text
            WHEN ((observed_raw_completeness_percent < (99)::numeric) OR (large_gap_count > 0)) THEN 'WARNING'::text
            ELSE 'INFO'::text
        END COLLATE "C") AS severity,
    (
        CASE
            WHEN ((actual_reading_count = 0) OR (observed_raw_completeness_percent < (80)::numeric)) THEN 'CRITICAL'::text
            WHEN (observed_raw_completeness_percent < (95)::numeric) THEN 'ERROR'::text
            WHEN (nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) THEN 'WARNING'::text
            WHEN (nominal_raw_completeness_percent < (95)::numeric) THEN 'ERROR'::text
            WHEN ((nominal_raw_completeness_percent < (99)::numeric) OR (large_gap_count > 0)) THEN 'WARNING'::text
            ELSE 'INFO'::text
        END COLLATE "C") AS nominal_reporting_severity,
        CASE
            WHEN ((actual_reading_count = 0) OR (observed_raw_completeness_percent < (80)::numeric)) THEN false
            ELSE true
        END AS usable_for_daily_dashboard,
        CASE
            WHEN ((observed_raw_completeness_percent >= (99)::numeric) AND (large_gap_count = 0)) THEN true
            ELSE false
        END AS usable_for_ml_training,
        CASE
            WHEN (nominal_cadence_status = 'DOES_NOT_MEET_NOMINAL_5_MINUTE_CADENCE'::text) THEN true
            ELSE false
        END AS requires_cadence_normalization_for_ml,
        CASE
            WHEN (actual_reading_count >= nominal_expected_daily_reading_count) THEN true
            ELSE false
        END AS nominal_daily_count_met
   FROM classified
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW dq_meter_daily_completeness_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON MATERIALIZED VIEW silver.dq_meter_daily_completeness_staging IS 'One row per canonical meter per UTC day. Separates nominal 288-reading compliance from completeness relative to each meter''s observed cadence. Source telemetry is unchanged.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.nominal_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.nominal_expected_daily_reading_count IS 'Official target of 288 readings for a complete five-minute UTC day.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.observed_expected_daily_reading_count; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.observed_expected_daily_reading_count IS 'Expected daily count calculated from each device''s observed historical median cadence.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.daily_quality_status; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.daily_quality_status IS 'Backward-compatible observed-cadence data-quality status.';


--
-- Name: COLUMN dq_meter_daily_completeness_staging.nominal_reporting_status; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON COLUMN silver.dq_meter_daily_completeness_staging.nominal_reporting_status IS 'Separate status showing compliance with the nominal five-minute/288-reading expectation.';


--
-- Name: dq_missing_intervals_staging; Type: MATERIALIZED VIEW; Schema: silver; Owner: -
--

CREATE MATERIALIZED VIEW silver.dq_missing_intervals_staging AS
 WITH ordered_readings AS (
         SELECT t.device_id,
            t."timestamp",
            lag(t."timestamp") OVER (PARTITION BY t.device_id ORDER BY t."timestamp") AS previous_timestamp
           FROM ((bronze.telemetries t
             JOIN bronze.telemetries_dictionaries td ON (((td.id = t.key_id) AND ((td.key)::text = 'TkW'::text))))
             JOIN silver.dq_device_cadence_staging b_1 ON (((b_1.energy_meter_key = t.device_id) AND b_1.cadence_baseline_is_reliable)))
        ), detected_gaps AS (
         SELECT r.device_id,
            r.previous_timestamp,
            r."timestamp",
            (((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) AS actual_gap_seconds,
            b_1.nominal_gap_seconds,
            b_1.observed_gap_seconds,
            GREATEST(((round(((((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) / b_1.observed_gap_seconds)))::integer - 1), 1) AS estimated_missing_readings_observed_cadence,
            GREATEST(((round(((((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) / b_1.nominal_gap_seconds)))::integer - 1), 1) AS estimated_missing_readings_nominal_5min
           FROM (ordered_readings r
             JOIN silver.dq_device_cadence_staging b_1 ON ((b_1.energy_meter_key = r.device_id)))
          WHERE ((r.previous_timestamp IS NOT NULL) AND ((((r."timestamp" - r.previous_timestamp))::numeric / 1000.0) > (b_1.observed_gap_seconds * 1.5)))
        )
 SELECT b.energy_meter_key,
    b.source_energy_meter_id,
    b.facility_key,
    b.zone_key,
    b.zone_name,
    b.device_name,
    b.meter_label,
    b.gateway_id,
    (to_timestamp((((g.previous_timestamp)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS previous_reading_utc,
    (to_timestamp((((g."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS next_reading_utc,
    ((to_timestamp((((g.previous_timestamp)::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date AS gap_start_date,
    ((to_timestamp((((g."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text))::date AS gap_end_date,
    round(g.nominal_gap_seconds, 3) AS nominal_gap_seconds,
    round(g.observed_gap_seconds, 3) AS observed_gap_seconds,
    round(g.observed_gap_seconds, 3) AS expected_gap_seconds,
    round(g.actual_gap_seconds, 3) AS actual_gap_seconds,
    round((g.actual_gap_seconds / 60.0), 3) AS actual_gap_minutes,
    g.estimated_missing_readings_observed_cadence,
    g.estimated_missing_readings_nominal_5min,
    g.estimated_missing_readings_observed_cadence AS estimated_missing_readings,
    (
        CASE
            WHEN (g.estimated_missing_readings_observed_cadence >= 144) THEN 'CRITICAL'::text
            WHEN (g.estimated_missing_readings_observed_cadence >= 12) THEN 'ERROR'::text
            ELSE 'WARNING'::text
        END COLLATE "C") AS severity,
    (
        CASE
            WHEN (g.estimated_missing_readings_observed_cadence >= 144) THEN 'EXTENDED_DEVICE_OR_GATEWAY_OUTAGE'::text
            WHEN (g.estimated_missing_readings_observed_cadence >= 12) THEN 'LONG_MISSING_TELEMETRY_PERIOD'::text
            ELSE 'MISSING_TELEMETRY_INTERVAL'::text
        END COLLATE "C") AS issue_code
   FROM (detected_gaps g
     JOIN silver.dq_device_cadence_staging b ON ((b.energy_meter_key = g.device_id)))
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW dq_missing_intervals_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON MATERIALIZED VIEW silver.dq_missing_intervals_staging IS 'One row per detected TkW gap. Gap detection uses observed device cadence; nominal five-minute comparison is also retained. No missing values are inserted.';


--
-- Name: energy_meter_phase_map_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_meter_phase_map_landing AS
 SELECT parent_device,
    phase_parent,
    child_device,
    phase_child
   FROM bronze.energy_meter_phase_map;


--
-- Name: VIEW energy_meter_phase_map_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_meter_phase_map_landing IS 'Landing view for bronze.energy_meter_phase_map. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: energy_saving_recommendations_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.energy_saving_recommendations_landing AS
 SELECT id,
    facility_id,
    ((title)::text COLLATE "C") AS title,
    ((top_right_text)::text COLLATE "C") AS top_right_text,
    (body_text COLLATE "C") AS body_text,
    ((bottom_right_text)::text COLLATE "C") AS bottom_right_text,
    ((color)::text COLLATE "C") AS color,
    ((icon_class)::text COLLATE "C") AS icon_class,
    created_on
   FROM bronze.energy_saving_recommendations;


--
-- Name: VIEW energy_saving_recommendations_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.energy_saving_recommendations_landing IS 'Landing view for bronze.energy_saving_recommendations. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_dictionaries_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_dictionaries_landing AS
 SELECT id,
    ((key)::text COLLATE "C") AS key,
    created_on
   FROM bronze.telemetries_dictionaries;


--
-- Name: VIEW telemetries_dictionaries_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_dictionaries_landing IS 'Landing view for bronze.telemetries_dictionaries. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_landing AS
 SELECT t.device_id,
    t.key_id,
    t."timestamp",
    t.bool,
        CASE
            WHEN (t.dbl IS NULL) THEN NULL::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['V1'::character varying, 'V2'::character varying, 'V3'::character varying, 'Vn1'::character varying, 'Vn2'::character varying, 'Vn3'::character varying, 'Va'::character varying, 'Vna'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['Amp1'::character varying, 'Amp2'::character varying, 'Amp3'::character varying, 'Ampa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = 'Hz'::text) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['PF1'::character varying, 'PF2'::character varying, 'PF3'::character varying, 'PFa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kW1'::character varying, 'kW2'::character varying, 'kW3'::character varying, 'TkW'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVAr1'::character varying, 'kVAr2'::character varying, 'kVAr3'::character varying, 'TkVAr'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kWh'::character varying, 'kVArh'::character varying, 'kVAh'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVA1'::character varying, 'kVA2'::character varying, 'kVA3'::character varying, 'TkVA'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            ELSE (round((t.dbl)::numeric, 9))::double precision
        END AS dbl,
    (t."json")::jsonb AS "json",
    t.long,
    ((t.str)::text COLLATE "C") AS str,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::date AS reading_date_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::time without time zone AS reading_time_saudi,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text))::integer AS saudi_date_key,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text))::integer AS saudi_time_key
   FROM (bronze.telemetries t
     LEFT JOIN bronze.telemetries_dictionaries td ON ((td.id = t.key_id)));


--
-- Name: VIEW telemetries_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_landing IS 'Landing view for bronze.telemetries. Preserves source rows and identifiers while applying measurement-key-specific floating-point presentation precision. Bronze remains exact.';


--
-- Name: fact_energy_readings_staging; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.fact_energy_readings_staging AS
 WITH electrical_source AS (
         SELECT meter.energy_meter_key,
            meter.source_energy_meter_id,
            meter.facility_key,
            meter.zone_key,
            meter.grid_billing_account_key,
            t."timestamp" AS source_timestamp_ms,
            (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
            td.key AS telemetry_key,
            COALESCE(t.dbl, (t.long)::double precision) AS numeric_reading_value
           FROM ((silver.telemetries_landing t
             JOIN silver.dim_energy_meter_staging meter ON ((meter.energy_meter_key = t.device_id)))
             JOIN silver.telemetries_dictionaries_landing td ON ((td.id = t.key_id)))
          WHERE (td.key = ANY (ARRAY['V1'::text, 'V2'::text, 'V3'::text, 'Va'::text, 'Vn1'::text, 'Vn2'::text, 'Vn3'::text, 'Vna'::text, 'Amp1'::text, 'Amp2'::text, 'Amp3'::text, 'Ampa'::text, 'Hz'::text, 'PF1'::text, 'PF2'::text, 'PF3'::text, 'PFa'::text, 'kW1'::text, 'kW2'::text, 'kW3'::text, 'TkW'::text, 'kVA1'::text, 'kVA2'::text, 'kVA3'::text, 'TkVA'::text, 'kVAr1'::text, 'kVAr2'::text, 'kVAr3'::text, 'TkVAr'::text, 'kWh'::text, 'kVAh'::text, 'kVArh'::text]))
        ), pivoted AS (
         SELECT electrical_source.energy_meter_key,
            electrical_source.source_energy_meter_id,
            electrical_source.facility_key,
            electrical_source.zone_key,
            electrical_source.grid_billing_account_key,
            (to_char(((electrical_source.reading_timestamp_utc)::date)::timestamp with time zone, 'YYYYMMDD'::text))::integer AS date_key,
            (to_char(electrical_source.reading_timestamp_utc, 'HH24MISS'::text))::integer AS time_key,
            electrical_source.source_timestamp_ms,
            electrical_source.reading_timestamp_utc,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'V1'::text)) AS voltage_line_1_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'V2'::text)) AS voltage_line_2_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'V3'::text)) AS voltage_line_3_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Va'::text)) AS voltage_line_average_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vn1'::text)) AS voltage_neutral_1_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vn2'::text)) AS voltage_neutral_2_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vn3'::text)) AS voltage_neutral_3_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Vna'::text)) AS voltage_neutral_average_v,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Amp1'::text)) AS current_phase_1_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Amp2'::text)) AS current_phase_2_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Amp3'::text)) AS current_phase_3_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Ampa'::text)) AS current_average_a,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'Hz'::text)) AS frequency_hz,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PF1'::text)) AS power_factor_phase_1,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PF2'::text)) AS power_factor_phase_2,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PF3'::text)) AS power_factor_phase_3,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'PFa'::text)) AS power_factor_average,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kW1'::text)) AS active_power_phase_1_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kW2'::text)) AS active_power_phase_2_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kW3'::text)) AS active_power_phase_3_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'TkW'::text)) AS active_power_total_kw,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVA1'::text)) AS apparent_power_phase_1_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVA2'::text)) AS apparent_power_phase_2_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVA3'::text)) AS apparent_power_phase_3_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'TkVA'::text)) AS apparent_power_total_kva,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAr1'::text)) AS reactive_power_phase_1_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAr2'::text)) AS reactive_power_phase_2_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAr3'::text)) AS reactive_power_phase_3_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'TkVAr'::text)) AS reactive_power_total_kvar,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kWh'::text)) AS active_energy_cumulative_kwh,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVAh'::text)) AS apparent_energy_cumulative_kvah,
            max(electrical_source.numeric_reading_value) FILTER (WHERE (electrical_source.telemetry_key = 'kVArh'::text)) AS reactive_energy_cumulative_kvarh,
            (count(*))::integer AS source_measurement_row_count,
            (count(DISTINCT electrical_source.telemetry_key))::integer AS populated_measurement_count,
            ((count(*) - count(DISTINCT electrical_source.telemetry_key)))::integer AS duplicate_measurement_row_count,
            (to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
            ((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::date AS reading_date_saudi,
            ((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::time without time zone AS reading_time_saudi,
            (to_char((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text))::integer AS saudi_date_key,
            (to_char((to_timestamp((((electrical_source.source_timestamp_ms)::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text))::integer AS saudi_time_key
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
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3)) THEN (round(((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS calculated_current_average_a,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3)) THEN (round(((GREATEST(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) - LEAST(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a)))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS current_phase_spread_a,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) = 3) AND (abs((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision)) > (0.1)::double precision)) THEN (round(((((100.0)::double precision * GREATEST(abs((p.current_phase_1_a - (((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))), abs((p.current_phase_2_a - (((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))), abs((p.current_phase_3_a - (((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))))) / abs((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision))))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS current_imbalance_pct,
    (
        CASE
            WHEN (m.phase_count IS NULL) THEN 'PHASE_COUNT_UNKNOWN'::text
            WHEN (m.phase_count <> 3) THEN 'NOT_APPLICABLE_NON_THREE_PHASE'::text
            WHEN (num_nonnulls(p.current_phase_1_a, p.current_phase_2_a, p.current_phase_3_a) < 3) THEN 'INSUFFICIENT_PHASE_DATA'::text
            WHEN (abs((((p.current_phase_1_a + p.current_phase_2_a) + p.current_phase_3_a) / (3.0)::double precision)) <= (0.1)::double precision) THEN 'LOW_LOAD_NOT_EVALUATED'::text
            ELSE 'EVALUATED'::text
        END COLLATE "C") AS current_imbalance_evaluation_status,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3)) THEN (round(((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS calculated_voltage_average_v,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3)) THEN (round(((GREATEST(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) - LEAST(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v)))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS voltage_phase_spread_v,
        CASE
            WHEN ((m.phase_count = 3) AND (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) = 3) AND (abs((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision)) > (1.0)::double precision)) THEN (round(((((100.0)::double precision * GREATEST(abs((p.voltage_line_1_v - (((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))), abs((p.voltage_line_2_v - (((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))), abs((p.voltage_line_3_v - (((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))))) / abs((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision))))::numeric, 2))::double precision
            ELSE NULL::double precision
        END AS voltage_imbalance_pct,
    (
        CASE
            WHEN (m.phase_count IS NULL) THEN 'PHASE_COUNT_UNKNOWN'::text
            WHEN (m.phase_count <> 3) THEN 'NOT_APPLICABLE_NON_THREE_PHASE'::text
            WHEN (num_nonnulls(p.voltage_line_1_v, p.voltage_line_2_v, p.voltage_line_3_v) < 3) THEN 'INSUFFICIENT_PHASE_DATA'::text
            WHEN (abs((((p.voltage_line_1_v + p.voltage_line_2_v) + p.voltage_line_3_v) / (3.0)::double precision)) <= (1.0)::double precision) THEN 'LOW_VOLTAGE_NOT_EVALUATED'::text
            ELSE 'EVALUATED'::text
        END COLLATE "C") AS voltage_imbalance_evaluation_status
   FROM (pivoted p
     LEFT JOIN silver.dim_energy_meter_staging m ON ((m.energy_meter_key = p.energy_meter_key)));


--
-- Name: VIEW fact_energy_readings_staging; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.fact_energy_readings_staging IS 'Main project fact. One energy meter per telemetry timestamp with electrical measures pivoted into business-readable columns.';


--
-- Name: fact_energy_readings_flagged; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.fact_energy_readings_flagged AS
 WITH base AS (
         SELECT f.energy_meter_key,
            f.source_energy_meter_id,
            f.facility_key,
            f.zone_key,
            f.grid_billing_account_key,
            f.date_key,
            f.time_key,
            f.source_timestamp_ms,
            f.reading_timestamp_utc,
            f.reading_timestamp_saudi,
            f.reading_date_saudi,
            f.voltage_line_1_v,
            f.voltage_line_2_v,
            f.voltage_line_3_v,
            f.voltage_line_average_v,
            f.voltage_neutral_1_v,
            f.voltage_neutral_2_v,
            f.voltage_neutral_3_v,
            f.voltage_neutral_average_v,
            f.current_phase_1_a,
            f.current_phase_2_a,
            f.current_phase_3_a,
            f.active_power_phase_1_kw,
            f.active_power_phase_2_kw,
            f.active_power_phase_3_kw,
            f.frequency_hz,
            f.power_factor_phase_1,
            f.power_factor_phase_2,
            f.power_factor_phase_3,
            f.power_factor_average,
            f.active_energy_cumulative_kwh,
            cb.cb_max_rating_a,
            lag(f.active_energy_cumulative_kwh) OVER w AS prev_kwh
           FROM (silver.fact_energy_readings_staging f
             LEFT JOIN silver.dim_meter_cb_rating cb ON ((cb.energy_meter_key = f.energy_meter_key)))
          WINDOW w AS (PARTITION BY f.energy_meter_key ORDER BY f.reading_timestamp_utc)
        ), statuses AS (
         SELECT b.energy_meter_key,
            b.source_energy_meter_id,
            b.facility_key,
            b.zone_key,
            b.grid_billing_account_key,
            b.date_key,
            b.time_key,
            b.source_timestamp_ms,
            b.reading_timestamp_utc,
            b.reading_timestamp_saudi,
            b.reading_date_saudi,
            silver.classify_voltage_neutral_v2(b.voltage_neutral_1_v) AS status_vn1,
            silver.classify_voltage_neutral_v2(b.voltage_neutral_2_v) AS status_vn2,
            silver.classify_voltage_neutral_v2(b.voltage_neutral_3_v) AS status_vn3,
            silver.classify_voltage_line_v2(b.voltage_line_1_v) AS status_v1,
            silver.classify_voltage_line_v2(b.voltage_line_2_v) AS status_v2,
            silver.classify_voltage_line_v2(b.voltage_line_3_v) AS status_v3,
            silver.classify_current_v2(b.current_phase_1_a, b.cb_max_rating_a, b.active_power_phase_1_kw) AS status_amp1,
            silver.classify_current_v2(b.current_phase_2_a, b.cb_max_rating_a, b.active_power_phase_2_kw) AS status_amp2,
            silver.classify_current_v2(b.current_phase_3_a, b.cb_max_rating_a, b.active_power_phase_3_kw) AS status_amp3,
            silver.classify_frequency_v2(b.frequency_hz) AS status_hz,
            silver.classify_power_factor_v2(b.power_factor_phase_1) AS status_pf1,
            silver.classify_power_factor_v2(b.power_factor_phase_2) AS status_pf2,
            silver.classify_power_factor_v2(b.power_factor_phase_3) AS status_pf3,
            silver.classify_power_factor_v2(b.power_factor_average) AS status_pfa,
            silver.classify_accumulated_energy_v2(b.active_energy_cumulative_kwh, b.prev_kwh) AS status_kwh
           FROM base b
        )
 SELECT energy_meter_key,
    source_energy_meter_id,
    facility_key,
    zone_key,
    grid_billing_account_key,
    date_key,
    time_key,
    source_timestamp_ms,
    reading_timestamp_utc,
    reading_timestamp_saudi,
    reading_date_saudi,
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
    silver.worst_status(VARIADIC ARRAY[status_vn1, status_vn2, status_vn3, status_v1, status_v2, status_v3, status_hz, status_pf1, status_pf2, status_pf3, status_pfa, status_kwh]) AS overall_status
   FROM statuses;


--
-- Name: firmwares_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.firmwares_landing AS
 SELECT id,
    ((filename)::text COLLATE "C") AS filename,
    ((client_id)::text COLLATE "C") AS client_id,
    ((version)::text COLLATE "C") AS version,
    created_by,
    created_on
   FROM bronze.firmwares;


--
-- Name: VIEW firmwares_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.firmwares_landing IS 'Landing view for bronze.firmwares. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: floor_plan_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.floor_plan_landing AS
 SELECT id,
    unit_id,
    ((name)::text COLLATE "C") AS name,
    image_proprties,
    created_by,
    created_on
   FROM bronze.floor_plan;


--
-- Name: VIEW floor_plan_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.floor_plan_landing IS 'Landing view for bronze.floor_plan. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: forget_password_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.forget_password_landing AS
 SELECT id,
    user_id,
    active,
    created_on,
    expires_on,
    ((token)::text COLLATE "C") AS token
   FROM bronze.forget_password;


--
-- Name: VIEW forget_password_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.forget_password_landing IS 'Landing view for bronze.forget_password. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: icons_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.icons_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((css_class)::text COLLATE "C") AS css_class,
    active,
    created_on
   FROM bronze.icons;


--
-- Name: VIEW icons_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.icons_landing IS 'Landing view for bronze.icons. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: label_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.label_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    created_on,
    created_by
   FROM bronze.label_types;


--
-- Name: VIEW label_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.label_types_landing IS 'Landing view for bronze.label_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.labels_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((icon)::text COLLATE "C") AS icon,
    (description COLLATE "C") AS description,
    ((hex_color)::text COLLATE "C") AS hex_color,
    active,
    label_type_id,
    created_on,
    created_by
   FROM bronze.labels;


--
-- Name: VIEW labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.labels_landing IS 'Landing view for bronze.labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: migratehistory_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.migratehistory_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    migrated_at
   FROM bronze.migratehistory;


--
-- Name: VIEW migratehistory_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.migratehistory_landing IS 'Landing view for bronze.migratehistory. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: modules_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.modules_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title,
    ((html_class)::text COLLATE "C") AS html_class,
    ((color)::text COLLATE "C") AS color,
    has_children,
    level,
    parent_id,
    priority,
    ((route_to)::text COLLATE "C") AS route_to,
    created_on
   FROM bronze.modules;


--
-- Name: VIEW modules_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.modules_landing IS 'Landing view for bronze.modules. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: mqtt_service_accounts_allowed_topics_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.mqtt_service_accounts_allowed_topics_landing AS
 SELECT id,
    mqtt_topic_id,
    access,
    active,
    mqtt_service_account_id,
    created_on,
    created_by
   FROM bronze.mqtt_service_accounts_allowed_topics;


--
-- Name: VIEW mqtt_service_accounts_allowed_topics_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.mqtt_service_accounts_allowed_topics_landing IS 'Landing view for bronze.mqtt_service_accounts_allowed_topics. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: mqtt_service_accounts_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.mqtt_service_accounts_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ((username)::text COLLATE "C") AS username,
    ((password)::text COLLATE "C") AS password,
    (description COLLATE "C") AS description,
    active,
    facility_id,
    created_on,
    created_by
   FROM bronze.mqtt_service_accounts;


--
-- Name: VIEW mqtt_service_accounts_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.mqtt_service_accounts_landing IS 'Landing view for bronze.mqtt_service_accounts. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: mqtt_topics_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.mqtt_topics_landing AS
 SELECT id,
    ((topic)::text COLLATE "C") AS topic,
    ((regex)::text COLLATE "C") AS regex,
    active,
    created_on,
    facility_id
   FROM bronze.mqtt_topics;


--
-- Name: VIEW mqtt_topics_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.mqtt_topics_landing IS 'Landing view for bronze.mqtt_topics. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: multi_factor_authentication_factors_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.multi_factor_authentication_factors_landing AS
 SELECT id,
    ((token)::text COLLATE "C") AS token,
    (additional_config)::jsonb AS additional_config,
    type_id,
    active
   FROM bronze.multi_factor_authentication_factors;


--
-- Name: VIEW multi_factor_authentication_factors_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.multi_factor_authentication_factors_landing IS 'Landing view for bronze.multi_factor_authentication_factors. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: multi_factor_authentication_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.multi_factor_authentication_types_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on
   FROM bronze.multi_factor_authentication_types;


--
-- Name: VIEW multi_factor_authentication_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.multi_factor_authentication_types_landing IS 'Landing view for bronze.multi_factor_authentication_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: notification_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.notification_types_landing AS
 SELECT id,
    ((title)::text COLLATE "C") AS title
   FROM bronze.notification_types;


--
-- Name: VIEW notification_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.notification_types_landing IS 'Landing view for bronze.notification_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: notifications_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.notifications_landing AS
 SELECT id,
    notification_group_id,
    contact_id,
    contact_method_id,
    notification_type_id,
    successfully_sent,
    read,
    read_ts,
    "timestamp",
    (details)::jsonb AS details
   FROM bronze.notifications;


--
-- Name: VIEW notifications_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.notifications_landing IS 'Landing view for bronze.notifications. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: overlay_controllers_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.overlay_controllers_landing AS
 SELECT overlay_id,
    controller_id
   FROM bronze.overlay_controllers;


--
-- Name: VIEW overlay_controllers_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.overlay_controllers_landing IS 'Landing view for bronze.overlay_controllers. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: overlays_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.overlays_landing AS
 SELECT id,
    unit_id,
    floor_plan_id,
    ((name)::text COLLATE "C") AS name,
    shape_config,
    created_by,
    created_on
   FROM bronze.overlays;


--
-- Name: VIEW overlays_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.overlays_landing IS 'Landing view for bronze.overlays. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: permissions_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.permissions_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    read,
    "create",
    update,
    delete,
    control,
    billing,
    is_core,
    created_by,
    created_on
   FROM bronze.permissions;


--
-- Name: VIEW permissions_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.permissions_landing IS 'Landing view for bronze.permissions. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: role_module_permission_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.role_module_permission_landing AS
 SELECT role_id,
    module_id,
    permission_id,
    created_on,
    created_by
   FROM bronze.role_module_permission;


--
-- Name: VIEW role_module_permission_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.role_module_permission_landing IS 'Landing view for bronze.role_module_permission. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: role_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.role_units_landing AS
 SELECT role_id,
    unit_id,
    unit_level,
    created_on,
    created_by
   FROM bronze.role_units;


--
-- Name: VIEW role_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.role_units_landing IS 'Landing view for bronze.role_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: roles_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.roles_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    global_role,
    ((icon)::text COLLATE "C") AS icon,
    ((icon_color)::text COLLATE "C") AS icon_color,
    active,
    created_on,
    created_by,
    facility_id
   FROM bronze.roles;


--
-- Name: VIEW roles_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.roles_landing IS 'Landing view for bronze.roles. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_controllers_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_controllers_landing AS
 SELECT id,
    schedule_id,
    controller_id,
    execution_sequence,
    ((controller_action)::text COLLATE "C") AS controller_action,
    created_on,
    created_by
   FROM bronze.schedule_controllers;


--
-- Name: VIEW schedule_controllers_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_controllers_landing IS 'Landing view for bronze.schedule_controllers. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_jobs_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_jobs_landing AS
 SELECT ((job_id)::text COLLATE "C") AS job_id,
    schedule_id,
    created_on
   FROM bronze.schedule_jobs;


--
-- Name: VIEW schedule_jobs_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_jobs_landing IS 'Landing view for bronze.schedule_jobs. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_labels_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_labels_landing AS
 SELECT id,
    schedule_id,
    label_id,
    created_on,
    created_by
   FROM bronze.schedule_labels;


--
-- Name: VIEW schedule_labels_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_labels_landing IS 'Landing view for bronze.schedule_labels. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedule_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedule_units_landing AS
 SELECT id,
    schedule_id,
    unit_id,
    created_on,
    created_by
   FROM bronze.schedule_units;


--
-- Name: VIEW schedule_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedule_units_landing IS 'Landing view for bronze.schedule_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: schedules_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.schedules_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    (description COLLATE "C") AS description,
    start_datetime,
    end_datetime,
    schedule_duration,
    triggers,
    active,
    created_on,
    created_by,
    ((schedule_type)::text COLLATE "C") AS schedule_type
   FROM bronze.schedules;


--
-- Name: VIEW schedules_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.schedules_landing IS 'Landing view for bronze.schedules. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: tariff_categories_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.tariff_categories_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    maximum_amp,
    minimum_amp,
    fee,
    active,
    facility_id,
    created_on,
    created_by
   FROM bronze.tariff_categories;


--
-- Name: VIEW tariff_categories_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.tariff_categories_landing IS 'Landing view for bronze.tariff_categories. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_latest_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_latest_landing AS
 SELECT t.device_id,
    t.key_id,
    t."timestamp",
    t.bool,
        CASE
            WHEN (t.dbl IS NULL) THEN NULL::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['V1'::character varying, 'V2'::character varying, 'V3'::character varying, 'Vn1'::character varying, 'Vn2'::character varying, 'Vn3'::character varying, 'Va'::character varying, 'Vna'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['Amp1'::character varying, 'Amp2'::character varying, 'Amp3'::character varying, 'Ampa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = 'Hz'::text) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['PF1'::character varying, 'PF2'::character varying, 'PF3'::character varying, 'PFa'::character varying])::text[])) THEN (round((t.dbl)::numeric, 2))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kW1'::character varying, 'kW2'::character varying, 'kW3'::character varying, 'TkW'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVAr1'::character varying, 'kVAr2'::character varying, 'kVAr3'::character varying, 'TkVAr'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kWh'::character varying, 'kVArh'::character varying, 'kVAh'::character varying])::text[])) THEN (round((t.dbl)::numeric, 1))::double precision
            WHEN ((td.key)::text = ANY ((ARRAY['kVA1'::character varying, 'kVA2'::character varying, 'kVA3'::character varying, 'TkVA'::character varying])::text[])) THEN (round((t.dbl)::numeric, 3))::double precision
            ELSE (round((t.dbl)::numeric, 9))::double precision
        END AS dbl,
    (t."json")::jsonb AS "json",
    t.long,
    ((t.str)::text COLLATE "C") AS str,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'UTC'::text) AS reading_timestamp_utc,
    (to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text) AS reading_timestamp_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::date AS reading_date_saudi,
    ((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text))::time without time zone AS reading_time_saudi,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'YYYYMMDD'::text))::integer AS saudi_date_key,
    (to_char((to_timestamp((((t."timestamp")::numeric / 1000.0))::double precision) AT TIME ZONE 'Asia/Riyadh'::text), 'HH24MISS'::text))::integer AS saudi_time_key
   FROM (bronze.telemetries_latest t
     LEFT JOIN bronze.telemetries_dictionaries td ON ((td.id = t.key_id)));


--
-- Name: VIEW telemetries_latest_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_latest_landing IS 'Landing view for bronze.telemetries_latest. Preserves source rows and identifiers while applying the same measurement-specific presentation precision as historical telemetry. Bronze remains exact.';


--
-- Name: telemetries_notif_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_notif_landing AS
 SELECT id,
    device_id,
    key_id,
    "timestamp",
    bool,
        CASE
            WHEN (dbl IS NULL) THEN NULL::double precision
            ELSE (round((dbl)::numeric, 9))::double precision
        END AS dbl,
    ("json")::jsonb AS "json",
    long,
    ((str)::text COLLATE "C") AS str,
    ((msg)::text COLLATE "C") AS msg
   FROM bronze.telemetries_notif;


--
-- Name: VIEW telemetries_notif_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_notif_landing IS 'Landing view for bronze.telemetries_notif. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: telemetries_notif_users_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.telemetries_notif_users_landing AS
 SELECT notif_id,
    user_id,
    read,
    read_ts
   FROM bronze.telemetries_notif_users;


--
-- Name: VIEW telemetries_notif_users_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.telemetries_notif_users_landing IS 'Landing view for bronze.telemetries_notif_users. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_batch_items_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_batch_items_landing AS
 SELECT id,
    batch_id,
    status_id,
    (original_filename COLLATE "C") AS original_filename,
    created_at,
    (details)::jsonb AS details
   FROM bronze.upload_batch_items;


--
-- Name: VIEW upload_batch_items_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_batch_items_landing IS 'Landing view for bronze.upload_batch_items. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_batches_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_batches_landing AS
 SELECT id,
    type_id,
    created_by,
    created_at,
    user_notified,
    notified_at,
    (details)::jsonb AS details
   FROM bronze.upload_batches;


--
-- Name: VIEW upload_batches_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_batches_landing IS 'Landing view for bronze.upload_batches. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_batches_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_batches_types_landing AS
 SELECT id,
    (name COLLATE "C") AS name
   FROM bronze.upload_batches_types;


--
-- Name: VIEW upload_batches_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_batches_types_landing IS 'Landing view for bronze.upload_batches_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: upload_status_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.upload_status_landing AS
 SELECT id,
    (name COLLATE "C") AS name
   FROM bronze.upload_status;


--
-- Name: VIEW upload_status_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.upload_status_landing IS 'Landing view for bronze.upload_status. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: users_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.users_landing AS
 SELECT id,
    ((email)::text COLLATE "C") AS email,
    ((first_name)::text COLLATE "C") AS first_name,
    ((last_name)::text COLLATE "C") AS last_name,
    ((password)::text COLLATE "C") AS password,
    role_id,
    active,
    mfa_factor_id,
    created_on,
    facility_id,
    mqtt_account_id,
    ((avatar)::text COLLATE "C") AS avatar,
    (preferences)::jsonb AS preferences,
    address_id,
    force_mfa
   FROM bronze.users;


--
-- Name: VIEW users_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.users_landing IS 'Landing view for bronze.users. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_bill_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_bill_landing AS
 SELECT id,
    water_grid_account_id,
    ((water_grid_invoice_number)::text COLLATE "C") AS water_grid_invoice_number,
    grid_period_begin,
    grid_period_end,
        CASE
            WHEN (grid_begin_reading IS NULL) THEN NULL::real
            ELSE (round((grid_begin_reading)::numeric, 6))::real
        END AS grid_begin_reading,
        CASE
            WHEN (grid_end_reading IS NULL) THEN NULL::real
            ELSE (round((grid_end_reading)::numeric, 6))::real
        END AS grid_end_reading,
        CASE
            WHEN (grid_consumption IS NULL) THEN NULL::real
            ELSE (round((grid_consumption)::numeric, 6))::real
        END AS grid_consumption,
        CASE
            WHEN (grid_cost IS NULL) THEN NULL::real
            ELSE (round((grid_cost)::numeric, 6))::real
        END AS grid_cost,
        CASE
            WHEN (system_begin_reading IS NULL) THEN NULL::real
            ELSE (round((system_begin_reading)::numeric, 6))::real
        END AS system_begin_reading,
        CASE
            WHEN (system_end_reading IS NULL) THEN NULL::real
            ELSE (round((system_end_reading)::numeric, 6))::real
        END AS system_end_reading,
        CASE
            WHEN (system_consumption IS NULL) THEN NULL::real
            ELSE (round((system_consumption)::numeric, 6))::real
        END AS system_consumption,
        CASE
            WHEN (system_cost IS NULL) THEN NULL::real
            ELSE (round((system_cost)::numeric, 6))::real
        END AS system_cost,
    (cost_details)::jsonb AS cost_details,
        CASE
            WHEN (consumption_different IS NULL) THEN NULL::real
            ELSE (round((consumption_different)::numeric, 6))::real
        END AS consumption_different,
    created_on,
    created_by
   FROM bronze.water_bill;


--
-- Name: VIEW water_bill_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_bill_landing IS 'Landing view for bronze.water_bill. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_bill_water_meter_consume_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_bill_water_meter_consume_landing AS
 SELECT water_bill_id,
    water_meter_id,
        CASE
            WHEN (water_meter_consume IS NULL) THEN NULL::real
            ELSE (round((water_meter_consume)::numeric, 6))::real
        END AS water_meter_consume,
    created_on,
    created_by
   FROM bronze.water_bill_water_meter_consume;


--
-- Name: VIEW water_bill_water_meter_consume_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_bill_water_meter_consume_landing IS 'Landing view for bronze.water_bill_water_meter_consume. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_global_types_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_global_types_landing AS
 SELECT water_grid_account_id,
    global_type_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_global_types;


--
-- Name: VIEW water_grid_account_global_types_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_global_types_landing IS 'Landing view for bronze.water_grid_account_global_types. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    account_number,
    ((meter_serial_number)::text COLLATE "C") AS meter_serial_number,
    water_grid_provider_id,
    service_type_id,
    service_class_id,
    start_period,
    end_period,
    account_cycle_days,
    is_new_tariff,
    grid_account_units_count,
    created_by,
    created_on
   FROM bronze.water_grid_account;


--
-- Name: VIEW water_grid_account_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_landing IS 'Landing view for bronze.water_grid_account. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_class_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_class_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    minimal_meter_diameter,
    maximum_meter_diameter,
    fee,
    active,
    water_grid_provider_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_class;


--
-- Name: VIEW water_grid_account_service_class_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_class_landing IS 'Landing view for bronze.water_grid_account_service_class. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_global_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_global_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    ratio_bill,
    water_grid_provider_id,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_global;


--
-- Name: VIEW water_grid_account_service_global_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_global_landing IS 'Landing view for bronze.water_grid_account_service_global. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_sub_type_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_sub_type_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    first,
    second,
    third,
    fourth,
    above,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_sub_type;


--
-- Name: VIEW water_grid_account_service_sub_type_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_sub_type_landing IS 'Landing view for bronze.water_grid_account_service_sub_type. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_service_type_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_service_type_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    c_base,
    s1,
    s2,
    s3,
    s4,
    s5,
    water_grid_provider_id,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_account_service_type;


--
-- Name: VIEW water_grid_account_service_type_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_service_type_landing IS 'Landing view for bronze.water_grid_account_service_type. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_account_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_account_units_landing AS
 SELECT water_grid_account_id,
    unit_id,
    created_on,
    created_by
   FROM bronze.water_grid_account_units;


--
-- Name: VIEW water_grid_account_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_account_units_landing IS 'Landing view for bronze.water_grid_account_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_provider_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_provider_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    active,
    created_on,
    created_by
   FROM bronze.water_grid_provider;


--
-- Name: VIEW water_grid_provider_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_provider_landing IS 'Landing view for bronze.water_grid_provider. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_grid_water_meters_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_grid_water_meters_landing AS
 SELECT water_grid_account_id,
    water_meter_id,
    created_on,
    created_by,
    grid_account_main_meter
   FROM bronze.water_grid_water_meters;


--
-- Name: VIEW water_grid_water_meters_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_grid_water_meters_landing IS 'Landing view for bronze.water_grid_water_meters. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_meter_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_meter_units_landing AS
 SELECT water_meter_id,
    unit_id,
    created_on,
    created_by,
    unit_main_meter
   FROM bronze.water_meter_units;


--
-- Name: VIEW water_meter_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_meter_units_landing IS 'Landing view for bronze.water_meter_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    capacity,
    width,
    body_height,
    inside_water_height,
    length,
    diameter,
    thickness,
    max_temperature,
    min_temperature,
    max_pressure,
    min_pressure,
    water_source_id,
    type_id,
    location_id,
    active,
    created_by,
    created_on,
    label_id
   FROM bronze.water_tank;


--
-- Name: VIEW water_tank_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_landing IS 'Landing view for bronze.water_tank. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_type_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_type_landing AS
 SELECT id,
    ((name)::text COLLATE "C") AS name,
    created_by,
    created_on
   FROM bronze.water_tank_type;


--
-- Name: VIEW water_tank_type_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_type_landing IS 'Landing view for bronze.water_tank_type. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_units_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_units_landing AS
 SELECT water_tank_id,
    unit_id,
    created_on,
    created_by
   FROM bronze.water_tank_units;


--
-- Name: VIEW water_tank_units_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_units_landing IS 'Landing view for bronze.water_tank_units. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: water_tank_water_sensors_landing; Type: VIEW; Schema: silver; Owner: -
--

CREATE VIEW silver.water_tank_water_sensors_landing AS
 SELECT water_tank_id,
    water_sensor_id,
    ((telemetry_key)::text COLLATE "C") AS telemetry_key,
    telemetry_key_id,
    control_id,
    ((category_name)::text COLLATE "C") AS category_name,
    created_on,
    created_by
   FROM bronze.water_tank_water_sensors;


--
-- Name: VIEW water_tank_water_sensors_landing; Type: COMMENT; Schema: silver; Owner: -
--

COMMENT ON VIEW silver.water_tank_water_sensors_landing IS 'Landing view for bronze.water_tank_water_sensors. Text uses COLLATE "C"; json is exposed as jsonb; float values are normalized to remove binary display artifacts while preserving their original PostgreSQL floating type.';


--
-- Name: agg_energy_1d agg_energy_1d_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1d
    ADD CONSTRAINT agg_energy_1d_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_1h agg_energy_1h_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1h
    ADD CONSTRAINT agg_energy_1h_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_1month agg_energy_1month_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1month
    ADD CONSTRAINT agg_energy_1month_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_1week agg_energy_1week_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_1week
    ADD CONSTRAINT agg_energy_1week_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_30min agg_energy_30min_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_30min
    ADD CONSTRAINT agg_energy_30min_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_3d agg_energy_3d_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_3d
    ADD CONSTRAINT agg_energy_3d_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: agg_energy_4h agg_energy_4h_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.agg_energy_4h
    ADD CONSTRAINT agg_energy_4h_pkey PRIMARY KEY (energy_meter_key, bucket_start_utc);


--
-- Name: data_quality_summary data_quality_summary_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.data_quality_summary
    ADD CONSTRAINT data_quality_summary_pkey PRIMARY KEY (energy_meter_key);


--
-- Name: dim_meter_cb_rating dim_meter_cb_rating_pkey; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.dim_meter_cb_rating
    ADD CONSTRAINT dim_meter_cb_rating_pkey PRIMARY KEY (energy_meter_key);


--
-- Name: fact_energy_readings_snapshot pk_energy_readings_snapshot; Type: CONSTRAINT; Schema: silver; Owner: -
--

ALTER TABLE ONLY silver.fact_energy_readings_snapshot
    ADD CONSTRAINT pk_energy_readings_snapshot PRIMARY KEY (energy_meter_key, reading_timestamp_utc);


--
-- Name: idx_consumption_date; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX idx_consumption_date ON silver.fact_energy_consumption_validated USING btree (reading_date_saudi);


--
-- Name: idx_consumption_meter_label; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX idx_consumption_meter_label ON silver.fact_energy_consumption_validated USING btree (meter_label);


--
-- Name: idx_consumption_meter_time; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX idx_consumption_meter_time ON silver.fact_energy_consumption_validated USING btree (energy_meter_key, reading_timestamp_utc);


--
-- Name: ix_dq_daily_completeness_status; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_daily_completeness_status ON silver.dq_meter_daily_completeness_staging USING btree (daily_quality_status, severity);


--
-- Name: ix_dq_daily_completeness_zone_date; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_daily_completeness_zone_date ON silver.dq_meter_daily_completeness_staging USING btree (zone_key, reading_date);


--
-- Name: ix_dq_daily_nominal_reporting_status; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_daily_nominal_reporting_status ON silver.dq_meter_daily_completeness_staging USING btree (nominal_reporting_status, nominal_reporting_severity);


--
-- Name: ix_dq_device_cadence_status; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_device_cadence_status ON silver.dq_device_cadence_staging USING btree (cadence_status, nominal_cadence_status);


--
-- Name: ix_dq_device_cadence_zone; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_device_cadence_zone ON silver.dq_device_cadence_staging USING btree (zone_key, device_name);


--
-- Name: ix_dq_missing_intervals_meter_time; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_missing_intervals_meter_time ON silver.dq_missing_intervals_staging USING btree (energy_meter_key, previous_reading_utc);


--
-- Name: ix_dq_missing_intervals_severity; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_missing_intervals_severity ON silver.dq_missing_intervals_staging USING btree (severity);


--
-- Name: ix_dq_missing_intervals_zone_time; Type: INDEX; Schema: silver; Owner: -
--

CREATE INDEX ix_dq_missing_intervals_zone_time ON silver.dq_missing_intervals_staging USING btree (zone_key, previous_reading_utc);


--
-- Name: ux_dq_daily_completeness_meter_date; Type: INDEX; Schema: silver; Owner: -
--

CREATE UNIQUE INDEX ux_dq_daily_completeness_meter_date ON silver.dq_meter_daily_completeness_staging USING btree (energy_meter_key, reading_date);


--
-- Name: ux_dq_device_cadence_energy_meter; Type: INDEX; Schema: silver; Owner: -
--

CREATE UNIQUE INDEX ux_dq_device_cadence_energy_meter ON silver.dq_device_cadence_staging USING btree (energy_meter_key);


--
-- PostgreSQL database dump complete
--

\unrestrict kY0iHc7dxObRUcNlpTsZiwdDwHKwEIc4xdzZCeVLd7kRsEY5c4KaXq3wJnZDg1g

