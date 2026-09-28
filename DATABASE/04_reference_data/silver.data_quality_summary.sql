-- Rows of silver.data_quality_summary
-- Exported because this table holds configuration or reference rows
-- that the pipeline depends on and that no view can rebuild.

--
-- PostgreSQL database dump
--

\restrict u1fd20nJdhii7jxJFkPMXbJEV5fWsWx5E7Jb0Z5r3xw3DoXjqNSPIKU3wIhWdPk

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
-- Data for Name: data_quality_summary; Type: TABLE DATA; Schema: silver; Owner: -
--

INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('041c997e-06a6-435f-9b3a-d89ab096e73d', 'ZN.6-PB_child__1_ch3pm', 155343, 24050, 36915, 13073, 81194, 0, 111, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('17a6f296-1089-4d21-8ef2-ac4dc0d094a0', 'ZN.3-PB.2_child__1_ch3pm', 151363, 48647, 8309, 2779, 84577, 0, 7051, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('1dd29db4-18c2-4290-828d-c64bdc78bd78', 'ZN.16-PB_child__1_ch3pm', 150749, 4263, 12, 707, 1991, 143754, 22, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('3274ab6e-4e67-4815-aa10-557898e12f62', 'ZN.10-PB.2_child__1_ch3pm', 136640, 14090, 3040, 2726, 101916, 2773, 12095, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('3a2297a7-69ac-449f-935c-9864c2396d20', 'ZN.2-PB_child__1_ch3pm', 159028, 17327, 48351, 6895, 82700, 0, 3755, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('3ae02828-eaa3-42c9-bac2-8c5f806367aa', 'ZN.7-PB_child__1_ch3pm', 152340, 59227, 31121, 30006, 31855, 0, 131, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('47eae1ba-cfaa-4c75-856d-c7671c375361', 'ZN.14-PB_child__1_ch3pm', 152579, 30973, 27766, 20301, 70142, 0, 3397, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('568d87fc-00d3-47ee-82c2-1e08a39a1daa', 'ZN.4-PB.2_child__1_ch3pm', 159223, 52477, 7701, 8406, 85555, 0, 5084, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('592d518b-1c99-418b-be4f-8de72de93d12', 'ZN.4-PB.1_child__1_ch3pm', 154573, 17, 131600, 7109, 15781, 0, 66, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('69e4e951-b4e3-470e-9d22-01a4af817998', 'ZN.10-PB.1_child__1_ch3pm', 163912, 1366, 0, 2, 43729, 115176, 3639, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('6c521adb-a597-47e0-bd56-c08364f53606', 'ZN.1-PB.2_child__1_ch3pm', 156685, 50903, 7259, 30191, 61177, 0, 7155, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('7192533d-b7a9-40c3-b735-9944d1f70d21', 'ZN.15-PB.1_child__1_ch3pm', 151296, 1406, 39871, 25986, 83999, 0, 34, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('77fc1449-478c-4aa9-bfa5-f9748a1bc80a', 'ZN.17-PB_child__1_ch3pm', 96471, 37242, 1569, 16692, 35497, 4468, 1003, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('7b7f5aa6-c13d-4a5d-829f-ec44752bfd90', 'ZN.8-PB.1_child__1_ch3pm', 158065, 38026, 32576, 17410, 64958, 4715, 380, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('8454f6c3-bb0d-435c-a5fa-346993a024d9', 'ZN.21-PB_child__1_ch3pm', 100071, 5442, 18395, 7967, 68266, 0, 1, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('861245e2-9dfa-4b01-adad-34f9eaf7f202', 'ZN.9-PB_child__1_ch3pm', 105331, 24479, 29968, 9785, 41090, 0, 9, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('8f9385f3-c636-4c7f-9488-b3baa6244479', 'ZN.18-PB_child__1_ch3pm', 161895, 75, 45710, 60206, 55790, 0, 114, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('9574e049-9fb7-46db-9f8c-b3da0666aea0', 'ZN.20-PB.1_child__1_ch3pm', 158735, 48462, 2902, 16435, 86834, 0, 4102, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('9fc6d98a-5c79-48df-abd5-c0a21e61f40c', 'ZN.13-PB.2_child__1_ch3pm', 129536, 41134, 462, 6482, 79971, 0, 1487, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('a0396787-f0f9-4037-a5cd-232c3b6e0000', 'ZN.20-PB.2_child__1_ch3pm', 104075, 21672, 7198, 31324, 43872, 0, 9, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('a0396787-f0f9-4037-a5cd-232c3b6edde3', 'ZN.1-PB.1_child__1_ch3pm', 160303, 0, 24786, 8713, 126787, 0, 17, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2', 'ZN.13-PB.1_child__1_ch3pm', 145533, 1188, 17308, 2592, 121270, 3035, 140, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('ceacbc77-476f-4dbb-996a-b5f0ba116e74', 'ZN.19-PB.2_child__1_ch3pm', 147216, 49508, 2414, 33280, 60615, 0, 1399, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('d16b8f2c-955f-497e-899c-0c2fc72a6ac9', 'ZN.19-PB.1_child__1_ch3pm', 119968, 4982, 71491, 8396, 35079, 0, 20, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('d63b364c-5680-431f-9166-395674542257', 'ZN.11-PB.1_child__1_ch3pm', 163362, 1016, 2291, 1319, 157388, 0, 1348, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('d6fae5a6-3f2a-4d4b-a4e3-d7fa3f6e0472', 'ZN.3-PB.1_child__1_ch3pm', 155501, 2496, 17738, 16668, 118590, 0, 9, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('dce95f37-66a8-4b01-8b78-5f49b73d9eb5', 'ZN.5-PB_child__1_ch3pm', 158859, 5, 2380, 319, 1255, 143615, 11285, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('de175eaf-4365-461f-be04-9417f36594fa', 'ZN.15-PB.2_child__1_ch3pm', 163947, 38725, 75, 18896, 96782, 3293, 6176, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('ec476a1b-999d-4998-82e6-e9630c717706', 'ZN.11-PB.2_child__1_ch3pm', 150712, 9594, 16, 227, 77780, 60047, 3048, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('f55c6b8e-0323-4b78-a571-219a6940ae26', 'ZN.8-PB.2_child__1_ch3pm', 158627, 838, 468, 3112, 796, 132567, 20846, '2026-08-04 15:18:15.485527');
INSERT INTO silver.data_quality_summary (energy_meter_key, meter_label, total_readings, overall_acceptable_count, overall_review_required_count, overall_anomaly_count, overall_problematic_count, overall_critical_count, overall_invalid_count, computed_at) VALUES ('f7715eeb-8c09-4a89-8d2c-74926eb78785', 'ZN.12-PB_child__1_ch3pm', 153980, 1016, 218, 57, 70537, 79357, 2795, '2026-08-04 15:18:15.485527');


--
-- PostgreSQL database dump complete
--

\unrestrict u1fd20nJdhii7jxJFkPMXbJEV5fWsWx5E7Jb0Z5r3xw3DoXjqNSPIKU3wIhWdPk

