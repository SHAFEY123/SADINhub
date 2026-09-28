-- View silver.energy_meter_mapping_audit_staging
-- Recovered from PostgreSQL 18.4 catalog on 2026-09-08 09:52 UTC
-- Database sadinhub, schema silver
-- Source of truth: pg_get_viewdef() - this is the definition the server holds


CREATE OR REPLACE VIEW silver.energy_meter_mapping_audit_staging AS
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
            count(*) OVER (PARTITION BY (COALESCE(NULLIF(lower(btrim(em.meter_label)), ''::text), em.id::text))) AS source_records_for_meter_label
           FROM silver.energy_meters_landing em
             JOIN silver.device_landing d ON d.id = em.device_id
             LEFT JOIN silver.units_landing u ON u.id = em.unit_id
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
                CASE
                    WHEN sm.zone_name = 'Zone 03'::text AND sm.source_device_name = 'ZN.3-PB_child__1_ch3pm'::text AND sm.source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text THEN 'ZN.3-PB.1_child__1_ch3pm'::text
                    ELSE sm.source_device_name
                END COLLATE "C" AS canonical_device_name,
            sm.source_meter_label COLLATE "C" AS canonical_meter_label,
                CASE
                    WHEN sm.zone_name = 'Zone 03'::text AND sm.source_device_name = 'ZN.3-PB_child__1_ch3pm'::text AND sm.source_meter_label = 'ZN.3-PB.1_child__1_ch3pm'::text THEN 'ZONE03_TEAM_CONFIRMED_DEVICE_NAME_CORRECTION'::text
                    WHEN sm.zone_name = 'Zone 13'::text AND sm.source_device_name = 'ZN.13-PB.1_child__2_ch3pm'::text AND sm.source_meter_label = 'ZN.13-PB.2_child__1_ch3pm'::text THEN 'ZONE13_TEAM_CONFIRMED_ONE_PANEL_TWO_METERS'::text
                    WHEN sm.zone_name = 'Zone 20'::text AND sm.source_device_name = 'ZN.20-PB.1_child__1_ch3pm'::text AND sm.source_meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text THEN 'ZONE20_TEAM_CONFIRMED_DUPLICATE_TO_EXCLUDE'::text
                    WHEN sm.zone_name = 'Zone 20'::text AND sm.source_device_name = sm.source_meter_label THEN 'ZONE20_TEAM_CONFIRMED_CANONICAL_MAPPING'::text
                    ELSE 'GENERAL_MAPPING_RULE'::text
                END COLLATE "C" AS business_rule_code,
                CASE
                    WHEN sm.zone_name = 'Zone 20'::text AND sm.source_device_name = 'ZN.20-PB.1_child__1_ch3pm'::text AND sm.source_meter_label = 'ZN.20-PB.2_child__1_ch3pm'::text THEN 100
                    WHEN sm.zone_name = 'Zone 20'::text AND sm.source_device_name = sm.source_meter_label THEN 0
                    WHEN lower(btrim(COALESCE(sm.source_meter_label, ''::text))) = lower(btrim(COALESCE(sm.source_device_name, ''::text))) THEN 10
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
        CASE
            WHEN business_rule_code = 'ZONE20_TEAM_CONFIRMED_DUPLICATE_TO_EXCLUDE'::text THEN 'EXCLUDE'::text
            WHEN canonical_mapping_rank = 1 THEN 'KEEP'::text
            ELSE 'EXCLUDE'::text
        END COLLATE "C" AS mapping_decision,
        CASE
            WHEN business_rule_code = 'ZONE03_TEAM_CONFIRMED_DEVICE_NAME_CORRECTION'::text THEN 'TEAM_CONFIRMED_NAME_CORRECTION'::text
            WHEN business_rule_code = 'ZONE13_TEAM_CONFIRMED_ONE_PANEL_TWO_METERS'::text THEN 'TEAM_CONFIRMED_EXCEPTION_ONE_PANEL_TWO_METERS'::text
            WHEN zone_name = 'Zone 20'::text AND canonical_mapping_rank = 1 THEN 'TEAM_CONFIRMED_DUPLICATE_MAPPING_RESOLVED'::text
            WHEN canonical_mapping_rank <> 1 THEN 'EXCLUDED_NON_CANONICAL_MAPPING'::text
            WHEN source_meter_records_for_device = 1 AND source_records_for_meter_label = 1 AND lower(btrim(COALESCE(source_meter_label, ''::text))) = lower(btrim(COALESCE(source_device_name, ''::text))) THEN 'VALID'::text
            WHEN source_meter_records_for_device = 1 AND source_records_for_meter_label = 1 THEN 'REVIEW_NAME_MISMATCH'::text
            WHEN lower(btrim(COALESCE(source_meter_label, ''::text))) = lower(btrim(COALESCE(source_device_name, ''::text))) THEN 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_NAME_MATCH'::text
            ELSE 'REVIEW_DUPLICATE_SOURCE_MAPPING_CANONICAL_SELECTED'::text
        END COLLATE "C" AS mapping_status,
    is_meter_active,
    meter_source_created_at
   FROM ranked;
