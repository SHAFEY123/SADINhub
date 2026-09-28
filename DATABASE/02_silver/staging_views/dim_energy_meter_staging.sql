-- View silver.dim_energy_meter_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.dim_energy_meter_staging AS
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
            count(*) OVER (PARTITION BY (COALESCE(NULLIF(lower(btrim(em.meter_label)), ''::text), em.id::text))) AS source_records_for_meter_label,
            lower(btrim(COALESCE(em.meter_label, ''::text))) = lower(btrim(COALESCE(d.name, ''::text))) AS source_meter_label_matches_device_name,
                CASE
                    WHEN u.name = 'Zone 03'::text AND d.name = 'ZN.3-PB_child__1_ch3pm'::text AND em.meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text THEN 'ZN.3-PB.1_child__1_ch3pm'::text
                    ELSE d.name
                END COLLATE "C" AS canonical_device_name,
            em.meter_label COLLATE "C" AS canonical_meter_label,
            row_number() OVER (PARTITION BY em.device_id ORDER BY (
                CASE
                    WHEN u.name = 'Zone 20'::text AND d.name = em.meter_label THEN 0
                    WHEN lower(btrim(COALESCE(em.meter_label, ''::text))) = lower(btrim(COALESCE(d.name, ''::text))) THEN 10
                    ELSE 20
                END), em.active DESC, em.created_on, em.id) AS canonical_mapping_rank
           FROM silver.energy_meters_landing em
             JOIN silver.device_landing d ON d.id = em.device_id
             LEFT JOIN silver.units_landing u ON u.id = em.unit_id
             LEFT JOIN silver.energy_meters_types_landing emt ON emt.id = em.type_id
             LEFT JOIN silver.devices_types_landing dt ON dt.id = d.type_id
             LEFT JOIN silver.devices_categories_landing dc ON dc.id = dt.category_id
          WHERE NOT (em.device_id = '9574e049-9fb7-46db-9f8c-b3da0666aea0'::uuid AND em.meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text)
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
    lower(btrim(COALESCE(canonical_meter_label, ''::text))) = lower(btrim(COALESCE(canonical_device_name, ''::text))) AS meter_label_matches_device_name,
        CASE
            WHEN zone_name = 'Zone 03'::text AND source_device_name = 'ZN.3-PB_child__1_ch3pm'::text AND source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text THEN 'TEAM_CONFIRMED_NAME_CORRECTION'::text
            WHEN zone_name = 'Zone 13'::text AND source_device_name = 'ZN.13-PB.1_child__2_ch3pm'::text AND source_meter_label = 'ZN.13-PB.2_child__1_ch3pm'::text THEN 'TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS'::text
            WHEN source_meter_records_for_device = 1 AND source_records_for_meter_label = 1 AND source_meter_label_matches_device_name THEN 'VALID'::text
            WHEN source_meter_records_for_device = 1 AND source_records_for_meter_label = 1 THEN 'REVIEW_NAME_MISMATCH'::text
            WHEN source_meter_label_matches_device_name THEN 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH'::text
            ELSE 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED'::text
        END COLLATE "C" AS mapping_status,
    meter_source_created_at
   FROM ranked_mapping
  WHERE canonical_mapping_rank = 1;
