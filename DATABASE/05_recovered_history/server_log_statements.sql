-- Statements recovered from the PostgreSQL server logs.
-- STATEMENT records commonly accompany errors or cancellations.
-- Their presence does not prove a successful execution, database
-- attribution, or agreement with the current pipeline. Review only.
-- 203 distinct statements recovered.

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	    em.meter_label,
	    em.meter_sn,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    to_timestamp(t.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS reading_time_utc,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'V1') AS v1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V2') AS v2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V3') AS v3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Hz') AS frequency_hz,
	    MAX(t.dbl) FILTER (WHERE td.key = 'PFa') AS power_factor,
	    MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
	    MAX(t.dbl) FILTER (WHERE td.key = 'kWh') AS cumulative_kwh
	
	FROM public.telemetries t
	
	JOIN public.telemetries_dictionaries td
	    ON td.id = t.key_id
	
	JOIN public.device d
	    ON d.id = t.device_id
	
	JOIN public.energy_meters em
	    ON em.device_id = d.id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN public.facilities f
	    ON f.id = em.facility_id
	
	WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm' or 'ZN.1-PB.2_child__1_ch3pm'
	
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz', 'PFa', 'TkW', 'kWh'
	  )
	
	  AND t.timestamp >= (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00') * 1000
	  )::bigint
	
	  AND t.timestamp < (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00') * 1000
	  )::bigint
	
	GROUP BY
	    f.name,
	    u.name,
	    em.meter_label,
	    em.meter_sn,
	    d.name,
	    d.serial_number,
	    t.timestamp
	
	ORDER BY t.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	    em.meter_label,
	    em.meter_sn,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    to_timestamp(t.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS reading_time_utc,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'V1') AS v1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V2') AS v2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V3') AS v3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Hz') AS frequency_hz,
	    MAX(t.dbl) FILTER (WHERE td.key = 'PFa') AS power_factor,
	    MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
	    MAX(t.dbl) FILTER (WHERE td.key = 'kWh') AS cumulative_kwh
	
	FROM public.telemetries t
	
	JOIN public.telemetries_dictionaries td
	    ON td.id = t.key_id
	
	JOIN public.device d
	    ON d.id = t.device_id
	
	JOIN public.energy_meters em
	    ON em.device_id = d.id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN public.facilities f
	    ON f.id = em.facility_id
	
	WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm' or 'ZN.1-PB.2_child__1_ch3pm',
	
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz', 'PFa', 'TkW', 'kWh'
	  )
	
	  AND t.timestamp >= (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00') * 1000
	  )::bigint
	
	  AND t.timestamp < (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00') * 1000
	  )::bigint
	
	GROUP BY
	    f.name,
	    u.name,
	    em.meter_label,
	    em.meter_sn,
	    d.name,
	    d.serial_number,
	    t.timestamp
	
	ORDER BY t.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	    em.meter_label,
	    em.meter_sn,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    to_timestamp(t.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS reading_time_utc,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'V1') AS v1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V2') AS v2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V3') AS v3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Hz') AS frequency_hz,
	    MAX(t.dbl) FILTER (WHERE td.key = 'PFa') AS power_factor,
	    MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
	    MAX(t.dbl) FILTER (WHERE td.key = 'kWh') AS cumulative_kwh
	
	FROM public.telemetries t
	
	JOIN public.telemetries_dictionaries td
	    ON td.id = t.key_id
	
	JOIN public.device d
	    ON d.id = t.device_id
	
	JOIN public.energy_meters em
	    ON em.device_id = d.id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN public.facilities f
	    ON f.id = em.facility_id
	
	WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm' and 'ZN.1-PB.2_child__1_ch3pm',
	
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz', 'PFa', 'TkW', 'kWh'
	  )
	
	  AND t.timestamp >= (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00') * 1000
	  )::bigint
	
	  AND t.timestamp < (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00') * 1000
	  )::bigint
	
	GROUP BY
	    f.name,
	    u.name,
	    em.meter_label,
	    em.meter_sn,
	    d.name,
	    d.serial_number,
	    t.timestamp
	
	ORDER BY t.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
ALTER DATABASE ssbms RENAME TO bronze;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT pg_terminate_backend(pid)
	FROM pg_stat_activity
	WHERE datname = 'ssbms'
	  AND pid <> pg_backend_pid();
	 
	 ALTER DATABASE ssbms RENAME TO bronze;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT pg_terminate_backend(pid)
	FROM pg_stat_activity
	WHERE datname = 'bronze'
	  AND pid <> pg_backend_pid();
	
	ALTER DATABASE bronze RENAME TO Sadinhub;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    em.meter_label,
	    d.name AS device_name,
	    u.name AS unit_name,
	
	    to_timestamp(history.first_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS first_reading_utc,
	
	    to_timestamp(history.last_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS last_reading_utc
	
	FROM public.energy_meters em
	
	JOIN public.device d
	    ON d.id = em.device_id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	JOIN LATERAL (
	    SELECT
	        MIN(t.timestamp) AS first_timestamp,
	        MAX(t.timestamp) AS last_timestamp
	    FROM public.telemetries t
	    WHERE t.device_id = em.device_id
	      AND t.key_id = (
	          SELECT id
	          FROM public.telemetries_dictionaries
	          WHERE key = 'TkW'
	      )
	) history
	    ON history.first_timestamp IS NOT NULL
	
	ORDER BY
	    u.name,
	    em.meter_label;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    em.meter_label,
	    d.name AS device_name,
	    u.name AS unit_name,
	
	    to_timestamp(history.first_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS first_reading_utc,
	
	    to_timestamp(history.last_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS last_reading_utc
	
	FROM bronzew.energy_meters em
	
	JOIN public.device d
	    ON d.id = em.device_id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	JOIN LATERAL (
	    SELECT
	        MIN(t.timestamp) AS first_timestamp,
	        MAX(t.timestamp) AS last_timestamp
	    FROM public.telemetries t
	    WHERE t.device_id = em.device_id
	      AND t.key_id = (
	          SELECT id
	          FROM public.telemetries_dictionaries
	          WHERE key = 'TkW'
	      )
	) history
	    ON history.first_timestamp IS NOT NULL
	
	ORDER BY
	    u.name,
	    em.meter_label;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    em.meter_label,
	    d.name AS device_name,
	    u.name AS unit_name,
	
	    to_timestamp(history.first_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS first_reading_utc,
	
	    to_timestamp(history.last_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS last_reading_utc
	
	FROM bronze.energy_meters em
	
	JOIN public.device d
	    ON d.id = em.device_id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	JOIN LATERAL (
	    SELECT
	        MIN(t.timestamp) AS first_timestamp,
	        MAX(t.timestamp) AS last_timestamp
	    FROM public.telemetries t
	    WHERE t.device_id = em.device_id
	      AND t.key_id = (
	          SELECT id
	          FROM public.telemetries_dictionaries
	          WHERE key = 'TkW'
	      )
	) history
	    ON history.first_timestamp IS NOT NULL
	
	ORDER BY
	    u.name,
	    em.meter_label;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	
	    em.id AS energy_meter_id,
	    em.meter_label,
	    em.meter_sn,
	    em.phase,
	
	    d.id AS device_id,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    COUNT(*) OVER (
	        PARTITION BY em.device_id
	    ) AS meter_records_using_same_device,
	
	    COUNT(*) OVER (
	        PARTITION BY em.meter_label
	    ) AS records_using_same_meter_label
	
	FROM public.energy_meters em
	
	JOIN public.device d
	    ON d.id = em.device_id
	
	LEFT JOIN public.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN public.facilities f
	    ON f.id = em.facility_id
	
	ORDER BY
	    u.name,
	    em.meter_label,
	    d.name;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	
	    em.id AS energy_meter_id,
	    em.meter_label,
	    em.meter_sn,
	    em.phase,
	
	    d.id AS device_id,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    COUNT(*) OVER (
	        PARTITION BY em.device_id
	    ) AS meter_records_using_same_device,
	
	    COUNT(*) OVER (
	        PARTITION BY em.meter_label
	    ) AS records_using_same_meter_label
	
	FROM bronze.energy_meters em
	
	JOIN bronze.device d
	    ON d.id = em.device_id
	
	LEFT JOIN bronze.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN brone.facilities f
	    ON f.id = em.facility_id
	
	ORDER BY
	    u.name,
	    em.meter_label,
	    d.name;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    fact.*,
	    meter.meter_label,
	    zone.zone_name,
	    facility.facility_name
	FROM silver.fact_energy_readings_staging AS fact
	JOIN silver.dim_energy_meter_staging AS meter
	    ON meter.energy_meter_key = fact.energy_meter_key
	LEFT JOIN silver.dim_zone_staging AS zone
	    ON zone.zone_key = fact.zone_key
	LEFT JOIN silver.dim_facility_staging AS facility
	    ON facility.facility_key = fact.facility_key
	WHERE meter.meter_label = 'ZN.1-PB.1_child__1_ch3pm'
	  AND fact.date_key = 20250301
	ORDER BY fact.reading_timestamp_utc
	LIMIT 50;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from silver.dim_energy_meter_staging where zonekey = "deddc68f-e9a8-4157-9da1-5eb3e76746d6"

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from silver.dim_energy_meter_staging where zone_key = "deddc68f-e9a8-4157-9da1-5eb3e76746d6"

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from silver.dim_energy_meter_staging  where zone_key = deddc68f-e9a8-4157-9da1-5eb3e76746d6

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from silver.dim_energy_meter_staging  where zone_key ="deddc68f-e9a8-4157-9da1-5eb3e76746d6"

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from silver.dim_energy_meter_staging where = "deddc68f-e9a8-4157-9da1-5eb3e76746d6"

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from silver.dim_energy_meter_staging where zone_key ="deddc68f-e9a8-4157-9da1-5eb3e76746d6"

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
select * from dim_zone_staging where zone_key = 'deddc68f-e9a8-4157-9da1-5eb3e76746d6'

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	    em.meter_label,
	    em.meter_sn,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    to_timestamp(t.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS reading_time_utc,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'V1') AS v1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V2') AS v2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V3') AS v3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Hz') AS frequency_hz,
	    MAX(t.dbl) FILTER (WHERE td.key = 'PFa') AS power_factor,
	    MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
	    MAX(t.dbl) FILTER (WHERE td.key = 'kWh') AS cumulative_kwh
	
	FROM bronze.telemetries t
	
	JOIN bronze.telemetries_dictionaries td
	    ON td.id = t.kbronze
	JOIN bronze.device d
	    ON d.id = t.device_id
	
	JOIN bronze.energy_meters em
	    ON em.device_id = d.id
	
	LEFT JOIN bronze.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN bronze.facilities f
	    ON f.id = em.facility_id
	
	WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm' 
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz', 'PFa', 'TkW', 'kWh'
	  )
	
	  AND t.timestamp >= (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00') * 1000
	  )::bigint
	
	  AND t.timestamp < (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00') * 1000
	  )::bigint
	
	GROUP BY
	    f.name,
	    u.name,
	    em.meter_label,
	    em.meter_sn,
	    d.name,
	    d.serial_number,
	    t.timestamp
	
	ORDER BY t.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    f.name AS facility_name,
	    u.name AS zone_name,
	    em.meter_label,
	    em.meter_sn,
	    d.name AS device_name,
	    d.serial_number AS device_serial_number,
	
	    to_timestamp(t.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS reading_time_utc,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'V1') AS v1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V2') AS v2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'V3') AS v3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
	    MAX(t.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
	
	    MAX(t.dbl) FILTER (WHERE td.key = 'Hz') AS frequency_hz,
	    MAX(t.dbl) FILTER (WHERE td.key = 'PFa') AS power_factor,
	    MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
	    MAX(t.dbl) FILTER (WHERE td.key = 'kWh') AS cumulative_kwh
	
	FROM bronze.telemetries t
	
	JOIN bronze.telemetries_dictionaries td
	    ON td.id = t.bronze
	JOIN bronze.device d
	    ON d.id = t.device_id
	
	JOIN bronze.energy_meters em
	    ON em.device_id = d.id
	
	LEFT JOIN bronze.units u
	    ON u.id = em.unit_id
	
	LEFT JOIN bronze.facilities f
	    ON f.id = em.facility_id
	
	WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm' 
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz', 'PFa', 'TkW', 'kWh'
	  )
	
	  AND t.timestamp >= (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00') * 1000
	  )::bigint
	
	  AND t.timestamp < (
	      EXTRACT(EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00') * 1000
	  )::bigint
	
	GROUP BY
	    f.name,
	    u.name,
	    em.meter_label,
	    em.meter_sn,
	    d.name,
	    d.serial_number,
	    t.timestamp
	
	ORDER BY t.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
WITH five_minute_data AS (
	    SELECT
	        to_timestamp(t.timestamp / 1000.0)
	            AT TIME ZONE 'UTC' AS reading_time_utc,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V1'
	        ) AS v1,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V2'
	        ) AS v2,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V3'
	        ) AS v3,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PFa'
	        ) AS power_factor,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'TkW'
	        ) AS total_kw,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'kWh'
	        ) AS cumulative_kwh
	
	    FROM bronze.telemetries t
	
	    JOIN bronze.telemetries_dictionaries td
	        ON td.id = t.key_id
	
	    JOIN bronze.device d
	        ON d.id = t.device_id
	
	    WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm','ZN.20-PB.2_child__1_ch3pm'
	
	      AND td.key IN (
	          'V1', 'V2', 'V3',
	          'PFa', 'TkW', 'kWh'
	      )
	
	      AND t.timestamp >= (
	          EXTRACT(
	              EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00'
	          ) * 1000
	      )::bigint
	
	      AND t.timestamp < (
	          EXTRACT(
	              EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00'
	          ) * 1000
	      )::bigint
	
	    GROUP BY t.timestamp
	)
	
	SELECT
	    DATE_TRUNC('hour', reading_time_utc) AS hour_utc,
	
	    ROUND(AVG(total_kw)::numeric, 3)
	        AS average_kw,
	
	    ROUND(MAX(total_kw)::numeric, 3)
	        AS peak_kw,
	
	    ROUND(AVG(power_factor)::numeric, 3)
	        AS average_power_factor,
	
	    ROUND(MIN(v1)::numeric, 2)
	        AS minimum_v1,
	
	    ROUND(MAX(v1)::numeric, 2)
	        AS maximum_v1,
	
	    ROUND(
	        (
	            MAX(cumulative_kwh)
	            - MIN(cumulative_kwh)
	        )::numeric,
	        3
	    ) AS estimated_energy_used_kwh
	
	FROM five_minute_data
	
	GROUP BY DATE_TRUNC('hour', reading_time_utc)
	
	ORDER BY hour_utc;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
WITH five_minute_data AS (
	    SELECT
	        to_timestamp(t.timestamp / 1000.0)
	            AT TIME ZONE 'UTC' AS reading_time_utc,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V1'
	        ) AS v1,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V2'
	        ) AS v2,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V3'
	        ) AS v3,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PFa'
	        ) AS power_factor,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'TkW'
	        ) AS total_kw,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'kWh'
	        ) AS cumulative_kwh
	
	    FROM bronze.telemetries t
	
	    JOIN bronze.telemetries_dictionaries td
	        ON td.id = t.key_id
	
	    JOIN bronze.device d
	        ON d.id = t.device_id
	
	    WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm','ZN.20-PB.2_child__1_ch3pm',
	
	      AND td.key IN (
	          'V1', 'V2', 'V3',
	          'PFa', 'TkW', 'kWh'
	      )
	
	      AND t.timestamp >= (
	          EXTRACT(
	              EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00'
	          ) * 1000
	      )::bigint
	
	      AND t.timestamp < (
	          EXTRACT(
	              EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00'
	          ) * 1000
	      )::bigint
	
	    GROUP BY t.timestamp
	)
	
	SELECT
	    DATE_TRUNC('hour', reading_time_utc) AS hour_utc,
	
	    ROUND(AVG(total_kw)::numeric, 3)
	        AS average_kw,
	
	    ROUND(MAX(total_kw)::numeric, 3)
	        AS peak_kw,
	
	    ROUND(AVG(power_factor)::numeric, 3)
	        AS average_power_factor,
	
	    ROUND(MIN(v1)::numeric, 2)
	        AS minimum_v1,
	
	    ROUND(MAX(v1)::numeric, 2)
	        AS maximum_v1,
	
	    ROUND(
	        (
	            MAX(cumulative_kwh)
	            - MIN(cumulative_kwh)
	        )::numeric,
	        3
	    ) AS estimated_energy_used_kwh
	
	FROM five_minute_data
	
	GROUP BY DATE_TRUNC('hour', reading_time_utc)
	
	ORDER BY hour_utc;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
WITH five_minute_data AS (
	    SELECT
	        to_timestamp(t.timestamp / 1000.0)
	            AT TIME ZONE 'UTC' AS reading_time_utc,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V1'
	        ) AS v1,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V2'
	        ) AS v2,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'V3'
	        ) AS v3,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PFa'
	        ) AS power_factor,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'TkW'
	        ) AS total_kw,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'kWh'
	        ) AS cumulative_kwh
	
	    FROM bronze.telemetries t
	
	    JOIN bronze.telemetries_dictionaries td
	        ON td.id = t.key_id
	
	    JOIN bronze.device d
	        ON d.id = t.device_id
	
	    WHERE d.name = 'ZN.1-PB.1_child__1_ch3pm' and 'ZN.20-PB.2_child__1_ch3pm',
	
	      AND td.key IN (
	          'V1', 'V2', 'V3',
	          'PFa', 'TkW', 'kWh'
	      )
	
	      AND t.timestamp >= (
	          EXTRACT(
	              EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00'
	          ) * 1000
	      )::bigint
	
	      AND t.timestamp < (
	          EXTRACT(
	              EPOCH FROM TIMESTAMPTZ '2025-03-02 00:00:00+00'
	          ) * 1000
	      )::bigint
	
	    GROUP BY t.timestamp
	)
	
	SELECT
	    DATE_TRUNC('hour', reading_time_utc) AS hour_utc,
	
	    ROUND(AVG(total_kw)::numeric, 3)
	        AS average_kw,
	
	    ROUND(MAX(total_kw)::numeric, 3)
	        AS peak_kw,
	
	    ROUND(AVG(power_factor)::numeric, 3)
	        AS average_power_factor,
	
	    ROUND(MIN(v1)::numeric, 2)
	        AS minimum_v1,
	
	    ROUND(MAX(v1)::numeric, 2)
	        AS maximum_v1,
	
	    ROUND(
	        (
	            MAX(cumulative_kwh)
	            - MIN(cumulative_kwh)
	        )::numeric,
	        3
	    ) AS estimated_energy_used_kwh
	
	FROM five_minute_data
	
	GROUP BY DATE_TRUNC('hour', reading_time_utc)
	
	ORDER BY hour_utc;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    em.meter_label,
	    d.name AS device_name,
	    u.name AS unit_name,
		d.id as device_id
	
	    to_timestamp(history.first_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS first_reading_utc,
	
	    to_timestamp(history.last_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS last_reading_utc
	
	FROM bronze.energy_meters em
	
	JOIN bronze.device d
	    ON d.id = em.device_id
	
	LEFT JOIN bronze.units u
	    ON u.id = em.unit_id
	
	JOIN LATERAL (
	    SELECT
	        MIN(t.timestamp) AS first_timestamp,
	        MAX(t.timestamp) AS last_timestamp
	    FROM bronze.telemetries t
	    WHERE t.device_id = em.device_id
	      AND t.key_id = (
	          SELECT id
	          FROM bronze.telemetries_dictionaries
	          WHERE key = 'TkW'
	      )
	) history
	    ON history.first_timestamp IS NOT NULL
	ORDER BY
	    u.name,
	    em.meter_label;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    em.meter_label,
	    d.name AS device_name,
	    u.name AS unit_name,
		d.id as device_id,
		m.id as meter_id,
	
	    to_timestamp(history.first_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS first_reading_utc,
	
	    to_timestamp(history.last_timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS last_reading_utc
	
	FROM bronze.energy_meters em
	
	JOIN bronze.device d
	    ON d.id = em.device_id
	
	LEFT JOIN bronze.units u
	    ON u.id = em.unit_id
	
	JOIN LATERAL (
	    SELECT
	        MIN(t.timestamp) AS first_timestamp,
	        MAX(t.timestamp) AS last_timestamp
	    FROM bronze.telemetries t
	    WHERE t.device_id = em.device_id
	      AND t.key_id = (
	          SELECT id
	          FROM bronze.telemetries_dictionaries
	          WHERE key = 'TkW'
	      )
	) history
	    ON history.first_timestamp IS NOT NULL
	ORDER BY
	    u.name,
	    em.meter_label;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    z.zone_name,
	    m.device_name,
	    m.meter_label AS meter_name
	
	FROM bronze.dim_energy_meter_staging AS m
	
	JOIN bronze.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	ORDER BY
	    z.zone_name,
	    m.device_name;

-- ==========================================================================
-- from postgresql-2026-07-23_103051.log
-- ==========================================================================
SELECT
	    z.zone_name,
	    m.device_name,
	    m.meter_label AS meter_name
	
	FROM bronze.dim_energy_meter AS m
	
	JOIN bronze.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	ORDER BY
	    z.zone_name,
	    m.device_name;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(
	                EPOCH FROM TIMESTAMPTZ '2025-03-01 00:00:00+00'
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM TIMESTAMPTZ '2025-03-08 00:00:00+00'
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	readings AS (
	    SELECT
	        t.device_id,
	        t.timestamp,
	
	        (
	            TO_TIMESTAMP(t.timestamp / 1000.0)
	            AT TIME ZONE 'UTC'
	        )::date AS reading_date,
	
	        LAG(t.timestamp) OVER (
	            PARTITION BY t.device_id
	            ORDER BY t.timestamp
	        ) AS previous_timestamp
	
	    FROM bronze.telemetries AS t
	
	    JOIN params AS p
	        ON t.timestamp >= p.start_ms
	       AND t.timestamp < p.end_ms
	
	    JOIN bronze.telemetries_dictionaries AS td
	        ON td.id = t.key_id
	       AND td.key = 'TkW'
	),
	
	gaps AS (
	    SELECT
	        device_id,
	        reading_date,
	        timestamp,
	        previous_timestamp,
	
	        (
	            timestamp - previous_timestamp
	        ) / 1000.0 AS gap_seconds
	
	    FROM readings
	
	    WHERE previous_timestamp IS NOT NULL
	),
	
	device_baseline AS (
	    SELECT
	        device_id,
	
	        PERCENTILE_CONT(0.5)
	        WITHIN GROUP (
	            ORDER BY gap_seconds
	        ) AS expected_gap_seconds
	
	    FROM gaps
	
	    GROUP BY device_id
	),
	
	daily_counts AS (
	    SELECT
	        device_id,
	        reading_date,
	        COUNT(DISTINCT timestamp) AS actual_reading_count,
	        MIN(timestamp) AS first_timestamp_ms,
	        MAX(timestamp) AS last_timestamp_ms
	
	    FROM readings
	
	    GROUP BY
	        device_id,
	        reading_date
	),
	
	daily_gap_quality AS (
	    SELECT
	        g.device_id,
	        g.reading_date,
	
	        COUNT(*) FILTER (
	            WHERE g.gap_seconds >
	                  b.expected_gap_seconds * 1.5
	        ) AS large_gap_count,
	
	        COALESCE(
	            SUM(
	                GREATEST(
	                    ROUND(
	                        g.gap_seconds
	                        / b.expected_gap_seconds
	                    )::integer - 1,
	                    0
	                )
	            ) FILTER (
	                WHERE g.gap_seconds >
	                      b.expected_gap_seconds * 1.5
	            ),
	            0
	        ) AS estimated_missing_readings,
	
	        MAX(g.gap_seconds) AS maximum_gap_seconds
	
	    FROM gaps AS g
	
	    JOIN device_baseline AS b
	        ON b.device_id = g.device_id
	
	    GROUP BY
	        g.device_id,
	        g.reading_date
	)
	
	SELECT
	    z.zone_name,
	    m.device_name,
	    m.meter_label,
	
	    dc.reading_date,
	
	    ROUND(
	        b.expected_gap_seconds::numeric,
	        3
	    ) AS expected_gap_seconds,
	
	    ROUND(
	        (
	            b.expected_gap_seconds / 60
	        )::numeric,
	        3
	    ) AS expected_gap_minutes,
	
	    ROUND(
	        86400.0 / b.expected_gap_seconds
	    )::integer AS expected_reading_count,
	
	    dc.actual_reading_count,
	
	    ROUND(
	        (
	            dc.actual_reading_count::numeric
	            /
	            ROUND(
	                86400.0 / b.expected_gap_seconds
	            )
	        ) * 100,
	        2
	    ) AS cadence_adjusted_completeness_percent,
	
	    COALESCE(dg.large_gap_count, 0)
	        AS large_gap_count,
	
	    COALESCE(dg.estimated_missing_readings, 0)
	        AS estimated_missing_readings,
	
	    ROUND(
	        dg.maximum_gap_seconds::numeric,
	        3
	    ) AS maximum_gap_seconds,
	
	    TO_TIMESTAMP(dc.first_timestamp_ms / 1000.0)
	        AT TIME ZONE 'UTC'
	        AS first_reading_utc,
	
	    TO_TIMESTAMP(dc.last_timestamp_ms / 1000.0)
	        AT TIME ZONE 'UTC'
	        AS last_reading_utc,
	
	    CASE
	        WHEN COALESCE(dg.large_gap_count, 0) > 0
	            THEN 'MISSING_INTERVALS_DETECTED'
	
	        WHEN dc.actual_reading_count >=
	             ROUND(
	                 86400.0 / b.expected_gap_seconds
	             )
	            THEN 'COMPLETE'
	
	        WHEN dc.actual_reading_count >=
	             ROUND(
	                 86400.0 / b.expected_gap_seconds
	             ) - 1
	            THEN 'COMPLETE_WITH_DAY_BOUNDARY_VARIATION'
	
	        ELSE 'LOW_COMPLETENESS_REVIEW'
	    END AS daily_quality_status,
	
	    CASE
	        WHEN ABS(
	            b.expected_gap_seconds - 300
	        ) <= 15
	            THEN 'STANDARD_APPROXIMATELY_5_MINUTES'
	
	        ELSE 'NON_STANDARD_STABLE_CADENCE'
	    END AS cadence_status
	
	FROM daily_counts AS dc
	
	JOIN device_baseline AS b
	    ON b.device_id = dc.device_id
	
	LEFT JOIN daily_gap_quality AS dg
	    ON dg.device_id = dc.device_id
	   AND dg.reading_date = dc.reading_date
	
	LEFT JOIN silver.dim_energy_meter_staging AS m
	    ON m.energy_meter_key = dc.device_id
	
	LEFT JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	ORDER BY
	    dc.reading_date,
	    z.zone_name,
	    m.device_name;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
SELECT
	    z.zone_name,
	    m.energy_meter_key,
	    m.source_energy_meter_id,
	    m.device_name,
	    m.device_label,
	    m.device_serial_number,
	    m.meter_label,
	    m.meter_serial_number,
	    m.gateway_id,
	    m.is_device_active,
	    m.is_device_online,
	    m.is_meter_active,
	    m.mapping_status,
	    b.first_reading_utc,
	    b.last_reading_utc,
	    b.total_tkw_reading_count,
	    b.expected_gap_seconds,
	    b.expected_daily_reading_count,
	    b.cadence_status,
	    b.cadence_baseline_is_reliable
	
	FROM silver.dim_energy_meter_staging AS m
	
	JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	LEFT JOIN silver.dq_device_cadence_staging AS b
	    ON b.energy_meter_key = m.energy_meter_key
	
	WHERE z.zone_name = 'Zone 17';

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH fact_sample AS (
	    SELECT *
	    FROM silver.fact_energy_readings_staging
	    WHERE date_key = 20250301
	)
	SELECT
	    'FACT_TO_ENERGY_METER' AS relationship_checked,
	    COUNT(*) AS issue_count
	FROM fact_sample AS fact
	LEFT JOIN silver.dim_energy_meter_staging AS m
	    ON m.energy_meter_key = fact.energy_meter_key
	WHERE m.energy_meter_key IS NULL
	
	UNION ALL
	
	SELECT
	    'FACT_TO_DATE',
	    COUNT(*)
	FROM fact_sample AS fact
	LEFT JOIN silver.dim_date_staging AS d
	    ON d.date_key = fact.date_key
	WHERE d.date_key IS NULL
	
	UNION ALL
	
	SELECT
	    'FACT_TO_ZONE',
	    COUNT(*)
	FROM fact_sample AS fact
	LEFT JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = fact.zone_key
	WHERE fact.zone_key IS NOT NULL
	  AND z.zone_key IS NULL
	
	UNION ALL
	
	SELECT
	    'FACT_TO_FACILITY',
	    COUNT(*)
	FROM fact_sample AS fact
	LEFT JOIN silver.dim_facility_staging AS f
	    ON f.facility_key = fact.facility_key
	WHERE fact.facility_key IS NOT NULL
	  AND f.facility_key IS NULL
	
	UNION ALL
	
	SELECT
	    'FACT_TO_BILLING_ACCOUNT',
	    COUNT(*)
	FROM fact_sample AS fact
	LEFT JOIN silver.dim_grid_billing_account_staging AS a
	    ON a.grid_billing_account_key = fact.grid_billing_account_key
	WHERE fact.grid_billing_account_key IS NOT NULL
	  AND a.grid_billing_account_key IS NULL;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
SELECT
	    energy_meter_key,
	    source_timestamp_ms,
	    COUNT(*) AS fact_row_count
	FROM silver.fact_energy_readings_staging
	WHERE date_key = 20250301
	GROUP BY
	    energy_meter_key,
	    source_timestamp_ms
	HAVING COUNT(*) > 1
	ORDER BY fact_row_count DESC
	LIMIT 100;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
SELECT
	    zone_name,
	    device_name,
	    meter_label,
	    reading_date,
	    expected_gap_seconds,
	    expected_daily_reading_count,
	    actual_reading_count,
	    actual_reading_count - expected_daily_reading_count
	        AS extra_reading_count,
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) * 100 AS raw_completeness_percent,
	    large_gap_count,
	    maximum_within_day_gap_seconds,
	    daily_quality_status,
	    severity
	FROM silver.dq_meter_daily_completeness_staging
	WHERE reading_date = selected_random_date
	  AND actual_reading_count >
	      expected_daily_reading_count + 2
	ORDER BY
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) DESC,
	    zone_name,
	    device_name;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
SELECT
	    zone_name,
	    device_name,
	    meter_label,
	    reading_date,
	    expected_gap_seconds,
	    expected_daily_reading_count,
	    actual_reading_count,
	    actual_reading_count - expected_daily_reading_count
	        AS extra_reading_count,
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) * 100 AS raw_completeness_percent,
	    large_gap_count,
	    maximum_within_day_gap_seconds,
	    daily_quality_status,
	    severity
	FROM silver.dq_meter_daily_completeness_staging
	WHERE reading_date = DATE 'selected_random_date'
	  AND actual_reading_count >
	      expected_daily_reading_count + 2
	ORDER BY
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) DESC,
	    zone_name,
	    device_name;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
SELECT
	    zone_name,
	    device_name,
	    meter_label,
	    reading_date,
	    expected_gap_seconds,
	    expected_daily_reading_count,
	    actual_reading_count,
	    actual_reading_count - expected_daily_reading_count
	        AS extra_reading_count,
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) * 100 AS raw_completeness_percent,
	    large_gap_count,
	    maximum_within_day_gap_seconds,
	    daily_quality_status,
	    severity
	FROM silver.dq_meter_daily_completeness_staging
	WHERE reading_date = DATE selected_random_date
	  AND actual_reading_count >
	      expected_daily_reading_count + 2
	ORDER BY
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) DESC,
	    zone_name,
	    device_name;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
SELECT
	    zone_name,
	    device_name,
	    meter_label,
	    reading_date,
	    expected_gap_seconds,
	    expected_daily_reading_count,
	    actual_reading_count,
	    actual_reading_count - expected_daily_reading_count
	        AS extra_reading_count,
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) * 100 AS raw_completeness_percent,
	    large_gap_count,
	    maximum_within_day_gap_seconds,
	    daily_quality_status,
	    severity
	FROM silver.dq_meter_daily_completeness_staging
	WHERE selected_random_date
	  AND actual_reading_count >
	      expected_daily_reading_count + 2
	ORDER BY
	    (
	        actual_reading_count::numeric
	        / NULLIF(expected_daily_reading_count, 0)
	    ) DESC,
	    zone_name,
	    device_name;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH random_meter_day AS (
	    SELECT
	        energy_meter_key,
	        zone_name,
	        device_name,
	        meter_label,
	        reading_date
	    FROM silver.dq_meter_daily_completeness_staging
	    WHERE actual_reading_count > 0
	    ORDER BY RANDOM()
	    LIMIT 1
	),
	bounds AS (
	    SELECT
	        r.*,
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    r.reading_date::timestamp AT TIME ZONE 'UTC'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    (r.reading_date + 1)::timestamp AT TIME ZONE 'UTC'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	    FROM random_meter_day AS r
	),
	random_packet AS (
	    SELECT DISTINCT s.timestamp
	    FROM silver.telemetries_landing AS s
	    CROSS JOIN bounds AS b
	    WHERE s.device_id = b.energy_meter_key
	      AND s.timestamp >= b.start_ms
	      AND s.timestamp < b.end_ms
	      AND s.dbl IS NOT NULL
	    ORDER BY RANDOM()
	    LIMIT 1
	)
	SELECT
	    b.reading_date AS selected_random_date,
	    b.zone_name,
	    b.device_name,
	    b.meter_label,
	    TO_TIMESTAMP(p.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS packet_timestamp_utc,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'V1') AS v1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'V2') AS v2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'V3') AS v3,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'Vn1') AS vn1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'Vn2') AS vn2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'Vn3') AS vn3,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'Amp1') AS amp1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'Amp2') AS amp2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'Amp3') AS amp3,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'Hz') AS hz,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'PF1') AS pf1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'PF2') AS pf2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'PF3') AS pf3,
	    MAX(s.dbl) FILTER (WHERE td.key = 'PFa') AS pfa,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'kW1') AS kw1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kW2') AS kw2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kW3') AS kw3,
	    MAX(s.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVAr1') AS kvar1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVAr2') AS kvar2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVAr3') AS kvar3,
	    MAX(s.dbl) FILTER (WHERE td.key = 'TkVAr') AS total_kvar,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVA1') AS kva1,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVA2') AS kva2,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVA3') AS kva3,
	    MAX(s.dbl) FILTER (WHERE td.key = 'TkVA') AS total_kva,
	
	    MAX(s.dbl) FILTER (WHERE td.key = 'kWh') AS kwh,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVAh') AS kvah,
	    MAX(s.dbl) FILTER (WHERE td.key = 'kVArh') AS kvarh
	
	FROM bounds AS b
	CROSS JOIN random_packet AS p
	JOIN silver.telemetries_landing AS s
	  ON s.device_id = b.energy_meter_key
	 AND s.timestamp = p.timestamp
	JOIN bronze.telemetries_dictionaries AS td
	  ON td.id = s.key_id
	GROUP BY
	    b.reading_date,
	    b.zone_name,
	    b.device_name,
	    b.meter_label,
	    p.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold            -- std devs
	),
	 
	-- ---------------------------------------------------------------------------
	-- 1. Base reading set for the window, with meter/zone context
	-- ---------------------------------------------------------------------------
	base_readings AS (
	    SELECT
	        f.energy_meter_key,
	        m.meter_name,
	        z.zone_name,
	        f.reading_timestamp_utc,
	        f.v1, f.v2, f.v3, f.va,
	        f.amp1, f.amp2, f.amp3, f.ampa,
	        f.hz,
	        f.pf1, f.pf2, f.pf3, f.pfa,
	        f.tkw, f.tkva, f.tkvar,
	        f.kwh, f.kvah, f.kvarh
	    FROM silver.fact_energy_readings_staging f
	    INNER JOIN silver.dim_energy_meter_staging m
	        ON m.energy_meter_key = f.energy_meter_key
	    INNER JOIN silver.dim_zone_staging z
	        ON z.zone_key = m.zone_key
	    CROSS JOIN params p
	    WHERE f.reading_timestamp_utc >= p.window_start
	      AND f.reading_timestamp_utc <  p.window_end
	      -- Uncomment to debug a single meter first, per the earlier slow-query lesson:
	      -- AND f.energy_meter_key = 123
	),

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold            -- std devs
	),
	 
	-- ---------------------------------------------------------------------------
	-- 1. Base reading set for the window, with meter/zone context
	-- ---------------------------------------------------------------------------
	base_readings AS (
	    SELECT
	        f.energy_meter_key,
	        m.meter_name,
	        z.zone_name,
	        f.reading_timestamp_utc,
	        f.v1, f.v2, f.v3, f.va,
	        f.amp1, f.amp2, f.amp3, f.ampa,
	        f.hz,
	        f.pf1, f.pf2, f.pf3, f.pfa,
	        f.tkw, f.tkva, f.tkvar,
	        f.kwh, f.kvah, f.kvarh
	    FROM silver.fact_energy_readings_staging f
	    INNER JOIN silver.dim_energy_meter_staging m
	        ON m.energy_meter_key = f.energy_meter_key
	    INNER JOIN silver.dim_zone_staging z
	        ON z.zone_key = m.zone_key
	    CROSS JOIN params p
	    WHERE f.reading_timestamp_utc >= p.window_start
	      AND f.reading_timestamp_utc <  p.window_end
	      -- Uncomment to debug a single meter first, per the earlier slow-query lesson:
	      -- AND f.energy_meter_key = 123
	)

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold            -- std devs
	),
	 
	-- ---------------------------------------------------------------------------
	-- 1. Base reading set for the window, with meter/zone context
	-- ---------------------------------------------------------------------------
	base_readings AS (
	    SELECT
	        f.energy_meter_key,
	        m.meter_name,
	        z.zone_name,
	        f.reading_timestamp_utc,
	        f.v1, f.v2, f.v3, f.va,
	        f.amp1, f.amp2, f.amp3, f.ampa,
	        f.hz,
	        f.pf1, f.pf2, f.pf3, f.pfa,
	        f.tkw, f.tkva, f.tkvar,
	        f.kwh, f.kvah, f.kvarh
	    FROM silver.fact_energy_readings_staging f
	    INNER JOIN silver.dim_energy_meter_staging m
	        ON m.energy_meter_key = f.energy_meter_key
	    INNER JOIN silver.dim_zone_staging z
	        ON z.zone_key = m.zone_key
	    CROSS JOIN params p
	    WHERE f.reading_timestamp_utc >= p.window_start
	      AND f.reading_timestamp_utc <  p.window_end

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold            -- std devs
	),

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold            -- std devs

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold     ;       -- std devs

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold     ,

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
-- =============================================================================
	-- measurement_value_consistency_audit.sql
	-- =============================================================================
	-- PURPOSE
	--   Read-only audit of measurement *values* (not cadence/completeness, which
	--   are already covered by the Silver DQ materialized views). Checks whether
	--   electrical readings in the energy fact are physically plausible and
	--   internally consistent, ahead of loading Gold.
	--
	-- SCOPE
	--   1. Hard physical-range violations (power factor, negative magnitudes,
	--      implausible frequency)
	--   2. Non-monotonic cumulative registers (kWh / kVAh / kVArh going backwards)
	--   3. Statistical spikes in active power (TkW) relative to each meter's own
	--      typical delta -- not a fixed threshold, since normal load size varies
	--      a lot by meter
	--   4. Phase imbalance / partial phase dropout across V1/V2/V3
	--
	-- THIS SCRIPT DOES NOT MODIFY DATA.
	--   No INSERT / UPDATE / DELETE / CREATE TABLE. Safe to run against Bronze,
	--   Silver, or a replica at any time -- same discipline as your other
	--   verify_*.sql / audit_*.sql scripts.
	--
	-- SCHEMA ASSUMPTIONS -- verify against create_silver_star_schema_staging_views.sql
	--   silver.fact_energy_readings_staging
	--       energy_meter_key       -- FK to dim_energy_meter_staging
	--       reading_timestamp_utc  -- converted from source epoch ms
	--       v1, v2, v3, va, amp1, amp2, amp3, ampa, hz,
	--       pf1, pf2, pf3, pfa, tkw, tkva, tkvar, kwh, kvah, kvarh
	--   silver.dim_energy_meter_staging
	--       energy_meter_key, meter_name, zone_key
	--   silver.dim_zone_staging
	--       zone_key, zone_name
	--   Column names here are lowercase/unquoted (Postgres default folding). If
	--   your view was created with quoted, case-preserving names (e.g. "V1",
	--   "TkW"), find/replace to match -- Postgres is case-sensitive for quoted
	--   identifiers. Also confirm reading_timestamp_utc's exact type (timestamp
	--   vs timestamptz) and adjust the literals in the params CTE if needed.
	--
	-- PERFORMANCE NOTE
	--   fact_energy_readings_staging is an ordinary (unmaterialized) view over a
	--   large source -- per the earlier slow-query finding, date_key is
	--   calculated rather than indexed. Start with a narrow window (default: one
	--   week) and, per that same lesson, uncomment the single-meter filter below
	--   before widening the date range. Once this logic is validated, consider
	--   materializing it as silver.dq_measurement_validity_staging, mirroring
	--   the existing dq_* pattern.
	-- =============================================================================
	
	
	-- ---------------------------------------------------------------------------
	-- 0. Parameters -- edit before running
	-- ---------------------------------------------------------------------------
	WITH params AS (
	    SELECT
	        '2025-03-01'::timestamptz AS window_start,               -- inclusive
	        '2025-03-08'::timestamptz AS window_end,                 -- exclusive
	        0.15                       AS phase_imbalance_ratio_threshold,  -- 15%
	        5.0                        AS spike_zscore_threshold            -- std devs
	),
	
	-- ---------------------------------------------------------------------------
	-- 1. Base reading set for the window, with meter/zone context
	-- ---------------------------------------------------------------------------
	base_readings AS (
	    SELECT
	        f.energy_meter_key,
	        m.meter_name,
	        z.zone_name,
	        f.reading_timestamp_utc,
	        f.v1, f.v2, f.v3, f.va,
	        f.amp1, f.amp2, f.amp3, f.ampa,
	        f.hz,
	        f.pf1, f.pf2, f.pf3, f.pfa,
	        f.tkw, f.tkva, f.tkvar,
	        f.kwh, f.kvah, f.kvarh
	    FROM silver.fact_energy_readings_staging f
	    INNER JOIN silver.dim_energy_meter_staging m
	        ON m.energy_meter_key = f.energy_meter_key
	    INNER JOIN silver.dim_zone_staging z
	        ON z.zone_key = m.zone_key
	    CROSS JOIN params p
	    WHERE f.reading_timestamp_utc >= p.window_start
	      AND f.reading_timestamp_utc <  p.window_end
	      -- Uncomment to debug a single meter first, per the earlier slow-query lesson:
	      -- AND f.energy_meter_key = 123
	),
	
	-- ---------------------------------------------------------------------------
	-- 2. Hard physical-range violations
	--    Power factor must fall within [-1, 1] regardless of system. Current,
	--    apparent power, and frequency are magnitude-type measurements and
	--    should never be negative.
	-- ---------------------------------------------------------------------------
	range_violations AS (
	    SELECT
	        b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
	        'PF_OUT_OF_RANGE' AS issue_type,
	        format('pf1=%s pf2=%s pf3=%s pfa=%s', b.pf1, b.pf2, b.pf3, b.pfa) AS detail
	    FROM base_readings b
	    WHERE b.pf1 NOT BETWEEN -1 AND 1
	       OR b.pf2 NOT BETWEEN -1 AND 1
	       OR b.pf3 NOT BETWEEN -1 AND 1
	       OR b.pfa NOT BETWEEN -1 AND 1
	
	    UNION ALL
	
	    SELECT
	        b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
	        'NEGATIVE_MAGNITUDE_VALUE',
	        format('amp1=%s amp2=%s amp3=%s tkva=%s', b.amp1, b.amp2, b.amp3, b.tkva)
	    FROM base_readings b
	    WHERE b.amp1 < 0 OR b.amp2 < 0 OR b.amp3 < 0 OR b.ampa < 0
	       OR b.tkva < 0
	
	    UNION ALL
	
	    SELECT
	        b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
	        'FREQUENCY_OUT_OF_BAND',
	        format('hz=%s', b.hz)
	    FROM base_readings b
	    -- Loose sanity band covering both 50Hz and 60Hz grids.
	    -- Tighten to your actual nominal frequency once confirmed with the team
	    -- (e.g. 59-61 for a 60Hz grid).
	    WHERE b.hz IS NOT NULL
	      AND b.hz NOT BETWEEN 45 AND 65
	),
	
	-- ---------------------------------------------------------------------------
	-- 3. Non-monotonic cumulative registers (kWh / kVAh / kVArh)
	--    These should only increase, except at a legitimate meter reset/rollover.
	--    A large drop close to zero looks like a rollover; a small drop looks
	--    like a data error and needs manual review. This mirrors the open
	--    "resets/rollovers" business rule already flagged as unconfirmed.
	-- ---------------------------------------------------------------------------
	register_deltas AS (
	    SELECT
	        b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
	        b.kwh,
	        LAG(b.kwh) OVER (
	            PARTITION BY b.energy_meter_key ORDER BY b.reading_timestamp_utc
	        ) AS prev_kwh
	    FROM base_readings b
	),
	register_violations AS (
	    SELECT
	        rd.energy_meter_key, rd.meter_name, rd.zone_name, rd.reading_timestamp_utc,
	        CASE
	            WHEN rd.kwh < rd.prev_kwh * 0.1 THEN 'LIKELY_ROLLOVER_OR_RESET'
	            ELSE 'KWH_DECREASE_ANOMALY'
	        END AS issue_type,
	        format('prev_kwh=%s new_kwh=%s', rd.prev_kwh, rd.kwh) AS detail
	    FROM register_deltas rd
	    WHERE rd.prev_kwh IS NOT NULL
	      AND rd.kwh < rd.prev_kwh
	),
	
	-- ---------------------------------------------------------------------------
	-- 4. Active-power (TkW) spikes relative to each meter's own typical delta
	--    Uses each meter's own delta distribution rather than a fixed threshold,
	--    since normal load levels vary a lot by meter.
	-- ---------------------------------------------------------------------------
	power_deltas AS (
	    SELECT
	        b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
	        b.tkw - LAG(b.tkw) OVER (
	            PARTITION BY b.energy_meter_key ORDER BY b.reading_timestamp_utc
	        ) AS delta_tkw
	    FROM base_readings b
	),
	power_delta_stats AS (
	    SELECT
	        energy_meter_key,
	        AVG(delta_tkw)         AS mean_delta,
	        STDDEV_SAMP(delta_tkw) AS stddev_delta
	    FROM power_deltas
	    WHERE delta_tkw IS NOT NULL
	    GROUP BY energy_meter_key
	    HAVING STDDEV_SAMP(delta_tkw) > 0   -- avoid divide-by-zero for flat meters
	),
	power_spikes AS (
	    SELECT
	        pd.energy_meter_key, pd.meter_name, pd.zone_name, pd.reading_timestamp_utc,
	        'TKW_SPIKE' AS issue_type,
	        format(
	            'delta=%s zscore=%s',
	            pd.delta_tkw,
	            -- Cast to numeric before ROUND -- ROUND(double precision, int)
	            -- doesn't exist in Postgres, per the earlier cadence-query fix.
	            ROUND(((pd.delta_tkw - s.mean_delta) / s.stddev_delta)::numeric, 2)
	        ) AS detail
	    FROM power_deltas pd
	    INNER JOIN power_delta_stats s
	        ON s.energy_meter_key = pd.energy_meter_key
	    CROSS JOIN params p
	    WHERE pd.delta_tkw IS NOT NULL
	      AND ABS((pd.delta_tkw - s.mean_delta) / s.stddev_delta) > p.spike_zscore_threshold
	),
	
	-- ---------------------------------------------------------------------------
	-- 5. Phase imbalance and partial phase dropout across V1/V2/V3
	--    A healthy 3-phase reading has similar voltage on all phases. A phase at
	--    near-zero while the others are normal suggests a partial-packet issue,
	--    the same pattern already diagnosed for Zone 17.
	-- ---------------------------------------------------------------------------
	phase_checks AS (
	    SELECT
	        b.energy_meter_key, b.meter_name, b.zone_name, b.reading_timestamp_utc,
	        GREATEST(b.v1, b.v2, b.v3) AS max_v,
	        LEAST(b.v1, b.v2, b.v3)    AS min_v
	    FROM base_readings b
	    WHERE b.v1 IS NOT NULL AND b.v2 IS NOT NULL AND b.v3 IS NOT NULL
	),
	phase_violations AS (
	    SELECT
	        pc.energy_meter_key, pc.meter_name, pc.zone_name, pc.reading_timestamp_utc,
	        CASE
	            WHEN pc.min_v < 5 AND pc.max_v > 50 THEN 'PARTIAL_PHASE_DROPOUT'
	            ELSE 'PHASE_IMBALANCE'
	        END AS issue_type,
	        format('min_v=%s max_v=%s', pc.min_v, pc.max_v) AS detail
	    FROM phase_checks pc
	    CROSS JOIN params p
	    WHERE (pc.min_v < 5 AND pc.max_v > 50)
	       OR (pc.min_v > 0 AND (pc.max_v - pc.min_v) / pc.min_v > p.phase_imbalance_ratio_threshold)
	),
	
	-- ---------------------------------------------------------------------------
	-- 6. Combine all issue types into one result set
	-- ---------------------------------------------------------------------------
	all_issues AS (
	    SELECT * FROM range_violations
	    UNION ALL
	    SELECT * FROM register_violations
	    UNION ALL
	    SELECT * FROM power_spikes
	    UNION ALL
	    SELECT * FROM phase_violations
	)
	
	-- =============================================================================
	-- SECTION A (default): detailed flagged rows -- run this first
	-- =============================================================================
	SELECT *
	FROM all_issues
	ORDER BY zone_name, meter_name, reading_timestamp_utc;
	
	-- =============================================================================
	-- SECTION B: prioritized rollup -- comment out Section A above and use this
	-- instead once you want counts per meter/issue type rather than raw rows.
	-- (Wrap the whole statement above, params through all_issues, as a subquery.)
	-- =============================================================================
	-- SELECT zone_name, meter_name, issue_type, COUNT(*) AS issue_count
	-- FROM ( <paste the WITH ... all_issues block and SELECT * FROM all_issues here> ) t
	-- GROUP BY zone_name, meter_name, issue_type
	-- ORDER BY issue_count DESC;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH random_day AS (
	    SELECT reading_date
	    FROM silver.dq_meter_daily_completeness_staging
	    WHERE actual_reading_count > 0
	    ORDER BY RANDOM()
	    LIMIT 1
	),
	bounds AS (
	    SELECT
	        reading_date,
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    reading_date::timestamp AT TIME ZONE 'UTC'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    (reading_date + 1)::timestamp AT TIME ZONE 'UTC'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	    FROM random_day
	)
	SELECT
	    x.reading_date AS selected_random_date,
	    z.zone_name,
	    m.device_name,
	    m.meter_label,
	    td.key AS measurement_key,
	    TO_TIMESTAMP(br.timestamp / 1000.0)
	        AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	
	    br.dbl AS bronze_exact_value,
	    sl.dbl AS silver_cleaned_value,
	    br.dbl - sl.dbl AS difference
	
	FROM bronze.telemetries AS br
	JOIN silver.telemetries_landing AS sl
	  ON sl.device_id = br.device_id
	 AND sl.key_id = br.key_id
	 AND sl.timestamp = br.timestamp
	JOIN bronze.telemetries_dictionaries AS td
	  ON td.id = br.key_id
	JOIN silver.dim_energy_meter_staging AS m
	  ON m.energy_meter_key = br.device_id
	LEFT JOIN silver.dim_zone_staging AS z
	  ON z.zone_key = m.zone_key
	CROSS JOIN bounds AS x
	WHERE br.timestamp >= x.start_ms
	  AND br.timestamp < x.end_ms
	  AND br.dbl IS NOT NULL
	  AND br.dbl IS DISTINCT FROM sl.dbl
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Vn1', 'Vn2', 'Vn3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz',
	      'PF1', 'PF2', 'PF3', 'PFa',
	      'kW1', 'kW2', 'kW3', 'TkW',
	      'kVAr1', 'kVAr2', 'kVAr3', 'TkVAr',
	      'kWh', 'kVArh', 'kVAh',
	      'kVA1', 'kVA2', 'kVA3', 'TkVA'
	  )
	ORDER BY RANDOM()
	LIMIT 100;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH random_meter_day AS MATERIALIZED (
	    SELECT
	        energy_meter_key,
	        zone_name,
	        device_name,
	        meter_label,
	        reading_date
	    FROM silver.dq_meter_daily_completeness_staging
	    WHERE actual_reading_count > 0
	    ORDER BY RANDOM()
	    LIMIT 1
	),
	bounds AS MATERIALIZED (
	    SELECT
	        r.*,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    r.reading_date::timestamp
	                    AT TIME ZONE 'UTC'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    (r.reading_date + 1)::timestamp
	                    AT TIME ZONE 'UTC'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	
	    FROM random_meter_day AS r
	),
	random_packet AS MATERIALIZED (
	    SELECT DISTINCT
	        s.timestamp
	
	    FROM silver.telemetries_landing AS s
	
	    CROSS JOIN bounds AS b
	
	    WHERE s.device_id = b.energy_meter_key
	      AND s.timestamp >= b.start_ms
	      AND s.timestamp < b.end_ms
	      AND s.dbl IS NOT NULL
	
	    ORDER BY RANDOM()
	
	    LIMIT 1
	)
	SELECT
	    b.reading_date AS selected_random_date,
	    b.zone_name,
	    b.device_name,
	    b.meter_label,
	
	    TO_TIMESTAMP(br.timestamp / 1000.0)
	        AT TIME ZONE 'UTC'
	        AS reading_timestamp_utc,
	
	    td.key AS measurement_key,
	
	    br.dbl AS bronze_exact_value,
	    sl.dbl AS silver_cleaned_value,
	
	    br.dbl - sl.dbl AS difference
	
	FROM bounds AS b
	
	CROSS JOIN random_packet AS rp
	
	JOIN bronze.telemetries AS br
	  ON br.device_id = b.energy_meter_key
	 AND br.timestamp = rp.timestamp
	
	JOIN silver.telemetries_landing AS sl
	  ON sl.device_id = br.device_id
	 AND sl.key_id = br.key_id
	 AND sl.timestamp = br.timestamp
	
	JOIN bronze.telemetries_dictionaries AS td
	  ON td.id = br.key_id
	
	WHERE br.dbl IS NOT NULL
	  AND td.key IN (
	      'V1', 'V2', 'V3',
	      'Vn1', 'Vn2', 'Vn3',
	      'Amp1', 'Amp2', 'Amp3',
	      'Hz',
	      'PF1', 'PF2', 'PF3', 'PFa',
	      'kW1', 'kW2', 'kW3', 'TkW',
	      'kVAr1', 'kVAr2', 'kVAr3', 'TkVAr',
	      'kWh', 'kVArh', 'kVAh',
	      'kVA1', 'kVA2', 'kVA3', 'TkVA'
	  )
	
	ORDER BY td.key;

-- ==========================================================================
-- from postgresql-2026-07-24_000000.log
-- ==========================================================================
WITH random_day AS (
	    SELECT reading_date
	    FROM silver.dq_meter_daily_completeness_staging
	    WHERE actual_reading_count > 0
	    ORDER BY RANDOM()
	    LIMIT 1
	),
	bounds AS (
	    SELECT
	        reading_date,
	        (EXTRACT(EPOCH FROM (reading_date::timestamp AT TIME ZONE 'UTC')) * 1000)::bigint AS start_ms,
	        (EXTRACT(EPOCH FROM ((reading_date + 1)::timestamp AT TIME ZONE 'UTC')) * 1000)::bigint AS end_ms
	    FROM random_day
	),
	target_keys AS (
	    SELECT id, key
	    FROM bronze.telemetries_dictionaries
	    WHERE key IN (
	        'V1', 'V2', 'V3', 'Vn1', 'Vn2', 'Vn3',
	        'Amp1', 'Amp2', 'Amp3', 'Hz',
	        'PF1', 'PF2', 'PF3', 'PFa',
	        'kW1', 'kW2', 'kW3', 'TkW',
	        'kVAr1', 'kVAr2', 'kVAr3', 'TkVAr',
	        'kWh', 'kVArh', 'kVAh',
	        'kVA1', 'kVA2', 'kVA3', 'TkVA'
	    )
	),
	mismatched_telemetries AS (
	    -- Pre-filter bronze rows first using timestamp index and target keys
	    SELECT 
	        br.device_id,
	        br.key_id,
	        br.timestamp,
	        br.dbl AS bronze_exact_value,
	        sl.dbl AS silver_cleaned_value,
	        x.reading_date
	    FROM bounds x
	    JOIN bronze.telemetries br 
	      ON br.timestamp >= x.start_ms 
	     AND br.timestamp < x.end_ms
	    JOIN target_keys tk 
	      ON tk.id = br.key_id
	    JOIN silver.telemetries_landing sl
	      ON sl.device_id = br.device_id
	     AND sl.key_id = br.key_id
	     AND sl.timestamp = br.timestamp
	    WHERE br.dbl IS NOT NULL
	      AND br.dbl IS DISTINCT FROM sl.dbl
	    -- Limit BEFORE joining dimension tables/sorting if you just need any sample
	    LIMIT 1000 
	)
	SELECT
	    m.reading_date AS selected_random_date,
	    z.zone_name,
	    d.device_name,
	    d.meter_label,
	    tk.key AS measurement_key,
	    TO_TIMESTAMP(m.timestamp / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	    m.bronze_exact_value,
	    m.silver_cleaned_value,
	    (m.bronze_exact_value - m.silver_cleaned_value) AS difference
	FROM mismatched_telemetries m
	JOIN target_keys tk ON tk.id = m.key_id
	JOIN silver.dim_energy_meter_staging d ON d.energy_meter_key = m.device_id
	LEFT JOIN silver.dim_zone_staging z ON z.zone_key = d.zone_key
	ORDER BY RANDOM()
	LIMIT 100;

-- ==========================================================================
-- from postgresql-2026-07-27_180903.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(EPOCH FROM (
	                DATE '2025-03-01'::timestamp AT TIME ZONE 'Asia/Riyadh'
	            )) * 1000
	        )::bigint AS start_ms,
	        (
	            EXTRACT(EPOCH FROM (
	                (DATE '2025-03-01' + 1)::timestamp
	                AT TIME ZONE 'Asia/Riyadh'
	            )) * 1000
	        )::bigint AS end_ms
	),
	packets AS (
	    SELECT
	        t.device_id,
	        t.timestamp,
	        MAX(t.dbl) FILTER (WHERE td.key = 'kW1') AS kw1,
	        MAX(t.dbl) FILTER (WHERE td.key = 'kW2') AS kw2,
	        MAX(t.dbl) FILTER (WHERE td.key = 'kW3') AS kw3,
	        MAX(t.dbl) FILTER (WHERE td.key = 'TkW') AS total_kw
	    FROM silver.telemetries AS t
	    JOIN params AS p
	      ON t.timestamp >= p.start_ms
	     AND t.timestamp < p.end_ms
	    JOIN silver.telemetries_dictionaries AS td
	      ON td.id = t.key_id
	    JOIN silver.dim_energy_meter_staging AS m
	      ON m.energy_meter_key = t.device_id
	    WHERE td.key IN ('kW1','kW2','kW3','TkW')
	    GROUP BY t.device_id, t.timestamp
	),
	calculated AS (
	    SELECT
	        p.*,
	        COALESCE(p.kw1, 0)
	        + COALESCE(p.kw2, 0)
	        + COALESCE(p.kw3, 0) AS phase_kw_sum
	    FROM packets AS p
	)
	SELECT
	    z.zone_name,
	    m.device_name,
	    m.meter_label,
	    TO_TIMESTAMP(c.timestamp / 1000.0) AT TIME ZONE 'UTC'
	        AS reading_timestamp_utc,
	    TO_TIMESTAMP(c.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh'
	        AS reading_timestamp_saudi,
	    c.kw1,
	    c.kw2,
	    c.kw3,
	    c.phase_kw_sum,
	    c.total_kw,
	    c.total_kw - c.phase_kw_sum AS signed_difference_kw,
	    ABS(c.total_kw - c.phase_kw_sum) AS absolute_difference_kw,
	    ROUND(
	        (
	            ABS(c.total_kw - c.phase_kw_sum)::numeric
	            / NULLIF(ABS(c.total_kw)::numeric, 0)
	        ) * 100,
	        3
	    ) AS difference_percent_of_total
	FROM calculated AS c
	JOIN silver.dim_energy_meter_staging AS m
	  ON m.energy_meter_key = c.device_id
	LEFT JOIN silver.dim_zone_staging AS z
	  ON z.zone_key = m.zone_key
	WHERE c.total_kw IS NOT NULL
	ORDER BY ABS(c.total_kw - c.phase_kw_sum) DESC
	LIMIT 500;

-- ==========================================================================
-- from postgresql-2026-07-27_180903.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(EPOCH FROM (
	                DATE '2025-03-01'::timestamp AT TIME ZONE 'Asia/Riyadh'
	            )) * 1000
	        )::bigint AS start_ms,
	        (
	            EXTRACT(EPOCH FROM (
	                (DATE '2025-03-01' + 1)::timestamp
	                AT TIME ZONE 'Asia/Riyadh'
	            )) * 1000
	        )::bigint AS end_ms
	),
	packet_quality AS (
	    SELECT
	        t.device_id,
	        t.timestamp,
	        COUNT(*) AS electrical_row_count,
	        COUNT(DISTINCT td.key) AS distinct_electrical_key_count,
	        COUNT(*) - COUNT(DISTINCT td.key) AS duplicate_key_rows,
	        COUNT(*) FILTER (
	            WHERE t.dbl IS NULL
	              AND t.long IS NULL
	              AND t.bool IS NULL
	              AND t.str IS NULL
	              AND t.json IS NULL
	        ) AS completely_null_rows,
	        COUNT(*) FILTER (
	            WHERE t.dbl IS NULL
	              AND (
	                  t.long IS NOT NULL
	                  OR t.bool IS NOT NULL
	                  OR t.str IS NOT NULL
	                  OR t.json IS NOT NULL
	              )
	        ) AS values_stored_outside_dbl
	    FROM bronze.telemetries AS t
	    JOIN params AS p
	      ON t.timestamp >= p.start_ms
	     AND t.timestamp < p.end_ms
	    JOIN bronze.telemetries_dictionaries AS td
	      ON td.id = t.key_id
	    JOIN silver.dim_energy_meter_staging AS m
	      ON m.energy_meter_key = t.device_id
	    WHERE td.key IN (
	        'V1','V2','V3','Va','Vn1','Vn2','Vn3','Vna',
	        'Amp1','Amp2','Amp3','Ampa','Hz',
	        'PF1','PF2','PF3','PFa',
	        'kW1','kW2','kW3','TkW',
	        'kVA1','kVA2','kVA3','TkVA',
	        'kVAr1','kVAr2','kVAr3','TkVAr',
	        'kWh','kVAh','kVArh'
	    )
	    GROUP BY t.device_id, t.timestamp
	)
	SELECT
	    z.zone_name,
	    m.device_name,
	    m.meter_label,
	    TO_TIMESTAMP(q.timestamp / 1000.0) AT TIME ZONE 'UTC'
	        AS packet_timestamp_utc,
	    TO_TIMESTAMP(q.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh'
	        AS packet_timestamp_saudi,
	    q.electrical_row_count,
	    q.distinct_electrical_key_count,
	    q.duplicate_key_rows,
	    q.completely_null_rows,
	    q.values_stored_outside_dbl
	FROM packet_quality AS q
	JOIN silver.dim_energy_meter_staging AS 
	  ON m.energy_meter_key = q.device_id
	LEFT JOIN silver.dim_zone_staging AS z
	  ON z.zone_key = m.zone_key
	WHERE q.duplicate_key_rows > 0
	   OR q.completely_null_rows > 0
	   OR q.values_stored_outside_dbl > 0
	ORDER BY z.zone_name, m.device_name, q.timestamp;

-- ==========================================================================
-- from postgresql-2026-07-27_180903.log
-- ==========================================================================
SELECT
	    td.key AS measurement_key,
	    COUNT(DISTINCT t.timestamp) AS reading_count
	FROM bronze.telemetries AS t
	JOIN bronze.telemetries_dictionaries AS td
	  ON td.id = t.key_id
	WHERE t.device_id = 'YOUR_DEVICE_ID'
	  AND t.timestamp >= (
	      EXTRACT(EPOCH FROM (
	          DATE '2025-03-01'::timestamp
	          AT TIME ZONE 'Asia/Riyadh'
	      )) * 1000
	  )::bigint
	  AND t.timestamp < (
	      EXTRACT(EPOCH FROM (
	          DATE '2025-03-02'::timestamp
	          AT TIME ZONE 'Asia/Riyadh'
	      )) * 1000
	  )::bigint
	GROUP BY td.key
	ORDER BY td.key;

-- ==========================================================================
-- from postgresql-2026-07-27_180903.log
-- ==========================================================================
SELECT *
	    id AS key_id,
	    key AS measurement_name
	FROM bronze.telemetries_dictionaries
	WHERE id IN (1,2,3,4,5,6,7,8,9,10,11,12)
	ORDER BY id;

-- ==========================================================================
-- from postgresql-2026-07-27_180903.log
-- ==========================================================================
SELECT *
	FROM silver.telemetries
	LIMIT 100;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    DATE '2025-03-01'::timestamp
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    (DATE '2025-03-01' + 1)::timestamp
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	timestamp_rows AS (
	    SELECT
	        'telemetries_landing'::text AS object_name,
	        t.timestamp AS source_timestamp_ms,
	        t.reading_timestamp_utc,
	        t.reading_timestamp_saudi,
	        t.reading_date_saudi,
	        t.reading_time_saudi,
	        t.saudi_date_key,
	        t.saudi_time_key
	
	    FROM silver.telemetries_landing AS t
	    CROSS JOIN params AS p
	
	    WHERE t.timestamp >= p.start_ms
	      AND t.timestamp < p.end_ms
	
	    UNION ALL
	
	    SELECT
	        'telemetries_latest_landing'::text,
	        t.timestamp,
	        t.reading_timestamp_utc,
	        t.reading_timestamp_saudi,
	        t.reading_date_saudi,
	        t.reading_time_saudi,
	        t.saudi_date_key,
	        t.saudi_time_key
	
	    FROM silver.telemetries_latest_landing AS t
	
	    UNION ALL
	
	    SELECT
	        'fact_energy_readings_staging'::text,
	        f.source_timestamp_ms,
	        f.reading_timestamp_utc,
	        f.reading_timestamp_saudi,
	        f.reading_date_saudi,
	        f.reading_time_saudi,
	        f.saudi_date_key,
	        f.saudi_time_key
	
	    FROM silver.fact_energy_readings_staging AS f
	    CROSS JOIN params AS p
	
	    WHERE f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	)
	
	SELECT
	    object_name,
	    COUNT(*) AS checked_rows,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_saudi
	              - reading_timestamp_utc
	              <> INTERVAL '3 hours'
	    ) AS incorrect_utc_offset,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_utc IS DISTINCT FROM
	            (
	                TO_TIMESTAMP(source_timestamp_ms / 1000.0)
	                AT TIME ZONE 'UTC'
	            )::timestamp without time zone
	    ) AS incorrect_utc_timestamp,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_saudi IS DISTINCT FROM
	            (
	                TO_TIMESTAMP(source_timestamp_ms / 1000.0)
	                AT TIME ZONE 'Asia/Riyadh'
	            )::timestamp without time zone
	    ) AS incorrect_saudi_timestamp,
	
	    COUNT(*) FILTER (
	        WHERE reading_date_saudi IS DISTINCT FROM
	              reading_timestamp_saudi::date
	    ) AS incorrect_saudi_date,
	
	    COUNT(*) FILTER (
	        WHERE reading_time_saudi IS DISTINCT FROM
	              reading_timestamp_saudi::time
	    ) AS incorrect_saudi_time,
	
	    COUNT(*) FILTER (
	        WHERE saudi_date_key IS DISTINCT FROM
	            TO_CHAR(
	                reading_timestamp_saudi,
	                'YYYYMMDD'
	            )::integer
	    ) AS incorrect_saudi_date_key,
	
	    COUNT(*) FILTER (
	        WHERE saudi_time_key IS DISTINCT FROM
	            TO_CHAR(
	                reading_timestamp_saudi,
	                'HH24MISS'
	            )::integer
	    ) AS incorrect_saudi_time_key
	
	FROM timestamp_rows
	
	GROUP BY object_name
	
	ORDER BY object_name;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 00:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-02 00:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	telemetries_check AS (
	    SELECT
	        'telemetries_landing'::text AS object_name,
	        COUNT(*) AS checked_rows,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_saudi
	                    - reading_timestamp_utc
	                  <> INTERVAL '3 hours'
	        ) AS incorrect_utc_offset,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_utc IS DISTINCT FROM
	                (
	                    TO_TIMESTAMP(timestamp / 1000.0)
	                    AT TIME ZONE 'UTC'
	                )
	        ) AS incorrect_utc_timestamp,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_saudi IS DISTINCT FROM
	                (
	                    TO_TIMESTAMP(timestamp / 1000.0)
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	        ) AS incorrect_saudi_timestamp,
	
	        COUNT(*) FILTER (
	            WHERE reading_date_saudi IS DISTINCT FROM
	                  reading_timestamp_saudi::date
	        ) AS incorrect_saudi_date,
	
	        COUNT(*) FILTER (
	            WHERE reading_time_saudi IS DISTINCT FROM
	                  reading_timestamp_saudi::time
	        ) AS incorrect_saudi_time,
	
	        COUNT(*) FILTER (
	            WHERE saudi_date_key IS DISTINCT FROM
	                  (
	                      EXTRACT(YEAR FROM reading_timestamp_saudi)::integer
	                      * 10000
	                    + EXTRACT(MONTH FROM reading_timestamp_saudi)::integer
	                      * 100
	                    + EXTRACT(DAY FROM reading_timestamp_saudi)::integer
	                  )
	        ) AS incorrect_saudi_date_key,
	
	        COUNT(*) FILTER (
	            WHERE saudi_time_key IS DISTINCT FROM
	                  (
	                      EXTRACT(HOUR FROM reading_timestamp_saudi)::integer
	                      * 10000
	                    + EXTRACT(MINUTE FROM reading_timestamp_saudi)::integer
	                      * 100
	                    + FLOOR(
	                          EXTRACT(SECOND FROM reading_timestamp_saudi)
	                      )::integer
	                  )
	        ) AS incorrect_saudi_time_key
	
	    FROM silver.telemetries_landing AS t
	    CROSS JOIN params AS p
	
	    WHERE t.timestamp >= p.start_ms
	      AND t.timestamp < p.end_ms
	),
	
	latest_check AS (
	    SELECT
	        'telemetries_latest_landing'::text AS object_name,
	        COUNT(*) AS checked_rows,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_saudi
	                    - reading_timestamp_utc
	                  <> INTERVAL '3 hours'
	        ) AS incorrect_utc_offset,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_utc IS DISTINCT FROM
	                (
	                    TO_TIMESTAMP(timestamp / 1000.0)
	                    AT TIME ZONE 'UTC'
	                )
	        ) AS incorrect_utc_timestamp,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_saudi IS DISTINCT FROM
	                (
	                    TO_TIMESTAMP(timestamp / 1000.0)
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	        ) AS incorrect_saudi_timestamp,
	
	        COUNT(*) FILTER (
	            WHERE reading_date_saudi IS DISTINCT FROM
	                  reading_timestamp_saudi::date
	        ) AS incorrect_saudi_date,
	
	        COUNT(*) FILTER (
	            WHERE reading_time_saudi IS DISTINCT FROM
	                  reading_timestamp_saudi::time
	        ) AS incorrect_saudi_time,
	
	        COUNT(*) FILTER (
	            WHERE saudi_date_key IS DISTINCT FROM
	                  (
	                      EXTRACT(YEAR FROM reading_timestamp_saudi)::integer
	                      * 10000
	                    + EXTRACT(MONTH FROM reading_timestamp_saudi)::integer
	                      * 100
	                    + EXTRACT(DAY FROM reading_timestamp_saudi)::integer
	                  )
	        ) AS incorrect_saudi_date_key,
	
	        COUNT(*) FILTER (
	            WHERE saudi_time_key IS DISTINCT FROM
	                  (
	                      EXTRACT(HOUR FROM reading_timestamp_saudi)::integer
	                      * 10000
	                    + EXTRACT(MINUTE FROM reading_timestamp_saudi)::integer
	                      * 100
	                    + FLOOR(
	                          EXTRACT(SECOND FROM reading_timestamp_saudi)
	                      )::integer
	                  )
	        ) AS incorrect_saudi_time_key
	
	    FROM silver.telemetries_latest_landing AS t
	    CROSS JOIN params AS p
	
	    WHERE t.timestamp >= p.start_ms
	      AND t.timestamp < p.end_ms
	),
	
	fact_check AS (
	    SELECT
	        'fact_energy_readings_staging'::text AS object_name,
	        COUNT(*) AS checked_rows,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_saudi
	                    - reading_timestamp_utc
	                  <> INTERVAL '3 hours'
	        ) AS incorrect_utc_offset,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_utc IS DISTINCT FROM
	                (
	                    TO_TIMESTAMP(source_timestamp_ms / 1000.0)
	                    AT TIME ZONE 'UTC'
	                )
	        ) AS incorrect_utc_timestamp,
	
	        COUNT(*) FILTER (
	            WHERE reading_timestamp_saudi IS DISTINCT FROM
	                (
	                    TO_TIMESTAMP(source_timestamp_ms / 1000.0)
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	        ) AS incorrect_saudi_timestamp,
	
	        COUNT(*) FILTER (
	            WHERE reading_date_saudi IS DISTINCT FROM
	                  reading_timestamp_saudi::date
	        ) AS incorrect_saudi_date,
	
	        COUNT(*) FILTER (
	            WHERE reading_time_saudi IS DISTINCT FROM
	                  reading_timestamp_saudi::time
	        ) AS incorrect_saudi_time,
	
	        COUNT(*) FILTER (
	            WHERE saudi_date_key IS DISTINCT FROM
	                  (
	                      EXTRACT(YEAR FROM reading_timestamp_saudi)::integer
	                      * 10000
	                    + EXTRACT(MONTH FROM reading_timestamp_saudi)::integer
	                      * 100
	                    + EXTRACT(DAY FROM reading_timestamp_saudi)::integer
	                  )
	        ) AS incorrect_saudi_date_key,
	
	        COUNT(*) FILTER (
	            WHERE saudi_time_key IS DISTINCT FROM
	                  (
	                      EXTRACT(HOUR FROM reading_timestamp_saudi)::integer
	                      * 10000
	                    + EXTRACT(MINUTE FROM reading_timestamp_saudi)::integer
	                      * 100
	                    + FLOOR(
	                          EXTRACT(SECOND FROM reading_timestamp_saudi)
	                      )::integer
	                  )
	        ) AS incorrect_saudi_time_key
	
	    FROM silver.fact_energy_readings_staging AS f
	    CROSS JOIN params AS p
	
	    WHERE f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	)
	
	SELECT * FROM telemetries_check
	UNION ALL
	SELECT * FROM latest_check
	UNION ALL
	SELECT * FROM fact_check
	ORDER BY object_name;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    energy_meter_key,
	    source_timestamp_ms,
	    COUNT(*) AS duplicate_row_count
	
	FROM silver.fact_energy_readings_staging
	
	GROUP BY
	    energy_meter_key,
	    source_timestamp_ms
	
	HAVING COUNT(*) > 1
	
	ORDER BY duplicate_row_count DESC;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    energy_meter_key,
	    source_timestamp_ms,
	    COUNT(*)
	FROM silver.fact_energy_readings_staging
	GROUP BY energy_meter_key, source_timestamp_ms;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        'a0396787-f0f9-4037-a5cd-232c3b6e0000'::uuid
	            AS selected_meter,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 00:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 01:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	timestamp_rows AS (
	    SELECT
	        'telemetries_landing'::text AS object_name,
	        t.timestamp AS source_timestamp_ms,
	        t.reading_timestamp_utc,
	        t.reading_timestamp_saudi,
	        t.reading_date_saudi,
	        t.reading_time_saudi,
	        t.saudi_date_key,
	        t.saudi_time_key
	
	    FROM silver.telemetries_landing AS t
	    CROSS JOIN params AS p
	
	    WHERE t.device_id = p.selected_meter
	      AND t.timestamp >= p.start_ms
	      AND t.timestamp < p.end_ms
	
	    UNION ALL
	
	    SELECT
	        'telemetries_latest_landing'::text,
	        t.timestamp,
	        t.reading_timestamp_utc,
	        t.reading_timestamp_saudi,
	        t.reading_date_saudi,
	        t.reading_time_saudi,
	        t.saudi_date_key,
	        t.saudi_time_key
	
	    FROM silver.telemetries_latest_landing AS t
	    CROSS JOIN params AS p
	
	    WHERE t.device_id = p.selected_meter
	
	    UNION ALL
	
	    SELECT
	        'fact_energy_readings_staging'::text,
	        f.source_timestamp_ms,
	        f.reading_timestamp_utc,
	        f.reading_timestamp_saudi,
	        f.reading_date_saudi,
	        f.reading_time_saudi,
	        f.saudi_date_key,
	        f.saudi_time_key
	
	    FROM silver.fact_energy_readings_staging AS f
	    CROSS JOIN params AS p
	
	    WHERE f.energy_meter_key = p.selected_meter
	      AND f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	)
	
	SELECT
	    object_name,
	    COUNT(*) AS checked_rows,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_utc IS NULL
	           OR reading_timestamp_saudi IS NULL
	    ) AS null_timestamps,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_saudi
	              - reading_timestamp_utc
	              <> INTERVAL '3 hours'
	    ) AS incorrect_saudi_offset,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_utc IS DISTINCT FROM
	              (
	                  TO_TIMESTAMP(source_timestamp_ms / 1000.0)
	                  AT TIME ZONE 'UTC'
	              )
	    ) AS incorrect_utc_timestamp,
	
	    COUNT(*) FILTER (
	        WHERE reading_timestamp_saudi IS DISTINCT FROM
	              (
	                  TO_TIMESTAMP(source_timestamp_ms / 1000.0)
	                  AT TIME ZONE 'Asia/Riyadh'
	              )
	    ) AS incorrect_saudi_timestamp,
	
	    COUNT(*) FILTER (
	        WHERE reading_date_saudi IS DISTINCT FROM
	              reading_timestamp_saudi::date
	    ) AS incorrect_saudi_date,
	
	    COUNT(*) FILTER (
	        WHERE reading_time_saudi IS DISTINCT FROM
	              reading_timestamp_saudi::time
	    ) AS incorrect_saudi_time,
	
	    COUNT(*) FILTER (
	        WHERE saudi_date_key IS DISTINCT FROM
	              TO_CHAR(
	                  reading_timestamp_saudi,
	                  'YYYYMMDD'
	              )::integer
	    ) AS incorrect_saudi_date_key,
	
	    COUNT(*) FILTER (
	        WHERE saudi_time_key IS DISTINCT FROM
	              TO_CHAR(
	                  reading_timestamp_saudi,
	                  'HH24MISS'
	              )::integer
	    ) AS incorrect_saudi_time_key
	
	FROM timestamp_rows
	
	GROUP BY object_name
	ORDER BY object_name;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        'a0396787-f0f9-4037-a5cd-232c3b6e0000'::uuid AS selected_meter,
	        (EXTRACT(EPOCH FROM (TIMESTAMP '2025-03-01 00:00:00' AT TIME ZONE 'Asia/Riyadh')) * 1000)::bigint AS start_ms,
	        (EXTRACT(EPOCH FROM (TIMESTAMP '2025-03-01 01:00:00' AT TIME ZONE 'Asia/Riyadh')) * 1000)::bigint AS end_ms
	)
	
	-- 1. Aggregate telemetries_landing
	SELECT
	    'telemetries_landing'::text AS object_name,
	    COUNT(*) AS checked_rows,
	    COUNT(*) FILTER (WHERE reading_timestamp_utc IS NULL OR reading_timestamp_saudi IS NULL) AS null_timestamps,
	    COUNT(*) FILTER (WHERE reading_timestamp_saudi - reading_timestamp_utc <> INTERVAL '3 hours') AS incorrect_saudi_offset,
	    COUNT(*) FILTER (WHERE reading_timestamp_utc IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'UTC')) AS incorrect_utc_timestamp,
	    COUNT(*) FILTER (WHERE reading_timestamp_saudi IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh')) AS incorrect_saudi_timestamp,
	    COUNT(*) FILTER (WHERE reading_date_saudi IS DISTINCT FROM reading_timestamp_saudi::date) AS incorrect_saudi_date,
	    COUNT(*) FILTER (WHERE reading_time_saudi IS DISTINCT FROM reading_timestamp_saudi::time) AS incorrect_saudi_time,
	    COUNT(*) FILTER (WHERE saudi_date_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'YYYYMMDD')::integer) AS incorrect_saudi_date_key,
	    COUNT(*) FILTER (WHERE saudi_time_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'HH24MISS')::integer) AS incorrect_saudi_time_key
	FROM silver.telemetries_landing AS t
	INNER JOIN params AS p ON t.device_id = p.selected_meter
	WHERE t.timestamp >= p.start_ms AND t.timestamp < p.end_ms
	
	UNION ALL
	
	-- 2. Aggregate telemetries_latest_landing
	SELECT
	    'telemetries_latest_landing'::text,
	    COUNT(*),
	    COUNT(*) FILTER (WHERE reading_timestamp_utc IS NULL OR reading_timestamp_saudi IS NULL),
	    COUNT(*) FILTER (WHERE reading_timestamp_saudi - reading_timestamp_utc <> INTERVAL '3 hours'),
	    COUNT(*) FILTER (WHERE reading_timestamp_utc IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'UTC')),
	    COUNT(*) FILTER (WHERE reading_timestamp_saudi IS DISTINCT FROM (TO_TIMESTAMP(t.timestamp / 1000.0) AT TIME ZONE 'Asia/Riyadh')),
	    COUNT(*) FILTER (WHERE reading_date_saudi IS DISTINCT FROM reading_timestamp_saudi::date),
	    COUNT(*) FILTER (WHERE reading_time_saudi IS DISTINCT FROM reading_timestamp_saudi::time),
	    COUNT(*) FILTER (WHERE saudi_date_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'YYYYMMDD')::integer),
	    COUNT(*) FILTER (WHERE saudi_time_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'HH24MISS')::integer)
	FROM silver.telemetries_latest_landing AS t
	INNER JOIN params AS p ON t.device_id = p.selected_meter
	-- (Note: Left without timestamp filters to match your original query)
	
	UNION ALL
	
	-- 3. Aggregate fact_energy_readings_staging
	SELECT
	    'fact_energy_readings_staging'::text,
	    COUNT(*),
	    COUNT(*) FILTER (WHERE reading_timestamp_utc IS NULL OR reading_timestamp_saudi IS NULL),
	    COUNT(*) FILTER (WHERE reading_timestamp_saudi - reading_timestamp_utc <> INTERVAL '3 hours'),
	    COUNT(*) FILTER (WHERE reading_timestamp_utc IS DISTINCT FROM (TO_TIMESTAMP(f.source_timestamp_ms / 1000.0) AT TIME ZONE 'UTC')),
	    COUNT(*) FILTER (WHERE reading_timestamp_saudi IS DISTINCT FROM (TO_TIMESTAMP(f.source_timestamp_ms / 1000.0) AT TIME ZONE 'Asia/Riyadh')),
	    COUNT(*) FILTER (WHERE reading_date_saudi IS DISTINCT FROM reading_timestamp_saudi::date),
	    COUNT(*) FILTER (WHERE reading_time_saudi IS DISTINCT FROM reading_timestamp_saudi::time),
	    COUNT(*) FILTER (WHERE saudi_date_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'YYYYMMDD')::integer),
	    COUNT(*) FILTER (WHERE saudi_time_key IS DISTINCT FROM TO_CHAR(reading_timestamp_saudi, 'HH24MISS')::integer)
	FROM silver.fact_energy_readings_staging AS f
	INNER JOIN params AS p ON f.energy_meter_key = p.selected_meter
	WHERE f.source_timestamp_ms >= p.start_ms AND f.source_timestamp_ms < p.end_ms;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    z.zone_name,
	
	    m.energy_meter_key AS device_id,
	    d.name AS device_name,
	    d.label AS device_label,
	    d.active AS device_active,
	    d.online AS device_online,
	
	    em.meter_label AS source_meter_label,
	    m.meter_label AS canonical_meter_label,
	
	    m.source_energy_meter_id,
	    m.facility_key,
	    m.zone_key,
	    m.grid_billing_account_key,
	
	    CASE
	        WHEN em.device_id IS NULL
	            THEN 'SOURCE_METER_RECORD_NOT_FOUND'
	
	        WHEN em.meter_label IS DISTINCT FROM m.meter_label
	            THEN 'SOURCE_AND_CANONICAL_LABEL_DIFFER'
	
	        ELSE 'MAPPING_MATCH'
	    END AS mapping_status
	
	FROM silver.dim_energy_meter_staging AS m
	
	LEFT JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	LEFT JOIN silver.devices_landing AS d
	    ON d.id = m.energy_meter_key
	
	LEFT JOIN silver.energy_meters_landing AS em
	    ON em.device_id = m.energy_meter_key
	
	ORDER BY
	    z.zone_name,
	    m.meter_label,
	    m.energy_meter_key;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    em.device_id,
	
	    d.name AS device_name,
	    d.label AS device_label,
	    d.active AS device_active,
	    d.online AS device_online,
	
	    em.meter_label AS source_meter_label,
	
	    m.meter_label AS canonical_meter_label,
	    z.zone_name AS canonical_zone_name,
	
	    m.zone_key,
	    m.facility_key,
	    m.grid_billing_account_key,
	
	    CASE
	        WHEN m.energy_meter_key IS NULL
	            THEN 'EXCLUDED_FROM_CANONICAL_ANALYSIS'
	
	        WHEN em.meter_label IS DISTINCT FROM m.meter_label
	            THEN 'SOURCE_AND_CANONICAL_LABEL_DIFFER'
	
	        ELSE 'INCLUDED_MAPPING_MATCH'
	    END AS analysis_status
	
	FROM silver.energy_meters_landing AS em
	
	LEFT JOIN silver.devices_landing AS d
	    ON d.id = em.device_id
	
	LEFT JOIN silver.dim_energy_meter_staging AS m
	    ON m.energy_meter_key = em.device_id
	
	LEFT JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	ORDER BY
	    analysis_status,
	    z.zone_name,
	    em.meter_label,
	    em.device_id;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    em.device_id,
	    d.name AS device_name,
	    d.label AS device_label,
	
	    em.meter_label AS source_meter_label,
	    m.meter_label AS canonical_meter_label,
	    z.zone_name,
	
	    CASE
	        WHEN m.energy_meter_key IS NULL
	            THEN 'EXCLUDED_FROM_CANONICAL_ANALYSIS'
	
	        WHEN em.meter_label IS DISTINCT FROM m.meter_label
	            THEN 'INVALID_OR_UNCONFIRMED_MAPPING'
	
	        ELSE 'MATCH'
	    END AS mapping_issue
	
	FROM silver.energy_meters_landing AS em
	
	LEFT JOIN silver.devices_landing AS d
	    ON d.id = em.device_id
	
	LEFT JOIN silver.dim_energy_meter_staging AS m
	    ON m.energy_meter_key = em.device_id
	
	LEFT JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	WHERE m.energy_meter_key IS NULL
	   OR em.meter_label IS DISTINCT FROM m.meter_label
	
	ORDER BY
	    z.zone_name,
	    em.meter_label;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    z.zone_name,
	
	    em.device_id,
	    d.name AS device_name,
	    d.label AS device_label,
	
	    em.meter_label AS source_meter_label,
	    m.meter_label AS canonical_meter_label,
	
	    CASE
	        WHEN m.energy_meter_key IS NULL
	            THEN 'EXCLUDED'
	
	        WHEN em.meter_label IS DISTINCT FROM m.meter_label
	            THEN 'INVALID_MAPPING'
	
	        ELSE 'VALID_MAPPING'
	    END AS mapping_status
	
	FROM silver.energy_meters_landing AS em
	
	LEFT JOIN silver.devices_landing AS d
	    ON d.id = em.device_id
	
	LEFT JOIN silver.dim_energy_meter_staging AS m
	    ON m.energy_meter_key = em.device_id
	
	LEFT JOIN silver.dim_zone_staging AS z
	    ON z.zone_key = m.zone_key
	
	WHERE em.meter_label ILIKE 'ZN.20-%'
	   OR z.zone_name = 'Zone 20'
	
	ORDER BY
	    em.meter_label,
	    em.device_id;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    DATE '2025-03-01'::timestamp
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    (DATE '2025-03-01' + 1)::timestamp
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	packets AS (
	    SELECT
	        t.device_id,
	        t.timestamp,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PF1'
	        ) AS pf1,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PF2'
	        ) AS pf2,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PF3'
	        ) AS pf3,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'PFa'
	        ) AS pfa,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'TkW'
	        ) AS total_kw,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'Amp1'
	        ) AS amp1,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'Amp2'
	        ) AS amp2,
	
	        MAX(t.dbl) FILTER (
	            WHERE td.key = 'Amp3'
	        ) AS amp3
	
	    FROM bronze.telemetries AS t
	
	    CROSS JOIN params AS p
	
	    JOIN bronze.telemetries_dictionaries AS td
	      ON td.id = t.key_id
	
	    JOIN silver.dim_energy_meter_staging AS m
	      ON m.energy_meter_key = t.device_id
	
	    JOIN silver.dim_zone_staging AS z
	      ON z.zone_key = m.zone_key
	
	    WHERE t.timestamp >= p.start_ms
	      AND t.timestamp < p.end_ms
	
	      AND td.key IN (
	          'PF1',
	          'PF2',
	          'PF3',
	          'PFa',
	          'TkW',
	          'Amp1',
	          'Amp2',
	          'Amp3'
	      )
	
	      AND z.zone_name ~ '^Zone (0[1-9]|1[0-9]|2[0-1])$'
	
	    GROUP BY
	        t.device_id,
	        t.timestamp
	),
	
	calculated AS (
	    SELECT
	        p.*,
	
	        (
	            COALESCE(p.pf1, 0)
	            + COALESCE(p.pf2, 0)
	            + COALESCE(p.pf3, 0)
	        ) / NULLIF(
	            (p.pf1 IS NOT NULL)::integer
	            + (p.pf2 IS NOT NULL)::integer
	            + (p.pf3 IS NOT NULL)::integer,
	            0
	        ) AS arithmetic_phase_pf_average,
	
	        (
	            COALESCE(p.amp1, 0)
	            + COALESCE(p.amp2, 0)
	            + COALESCE(p.amp3, 0)
	        ) / NULLIF(
	            (p.amp1 IS NOT NULL)::integer
	            + (p.amp2 IS NOT NULL)::integer
	            + (p.amp3 IS NOT NULL)::integer,
	            0
	        ) AS average_current_a
	
	    FROM packets AS p
	)
	
	SELECT
	    z.zone_name,
	    m.device_name,
	    m.meter_label,
	
	    TO_TIMESTAMP(c.timestamp / 1000.0)
	        AT TIME ZONE 'Asia/Riyadh'
	        AS reading_timestamp_saudi,
	
	    /* Power-factor readings */
	    c.pf1,
	    c.pf2,
	    c.pf3,
	    c.pfa,
	
	    /* Current readings */
	    c.amp1,
	    c.amp2,
	    c.amp3,
	    c.average_current_a,
	
	    /* PF comparison */
	    c.arithmetic_phase_pf_average,
	
	    c.pfa - c.arithmetic_phase_pf_average
	        AS pfa_minus_arithmetic_average,
	
	    c.total_kw,
	
	    CASE
	        WHEN ABS(COALESCE(c.total_kw, 0)) < 0.5
	          OR COALESCE(c.average_current_a, 0) < 1.0
	        THEN 'LOW_LOAD_PF_REVIEW'
	
	        WHEN ABS(
	            c.pfa - c.arithmetic_phase_pf_average
	        ) > 0.10
	        THEN 'PFA_DEFINITION_REVIEW'
	
	        ELSE 'WITHIN_EXPLORATORY_TOLERANCE'
	    END AS review_status
	
	FROM calculated AS c
	
	JOIN silver.dim_energy_meter_staging AS m
	  ON m.energy_meter_key = c.device_id
	
	JOIN silver.dim_zone_staging AS z
	  ON z.zone_key = m.zone_key
	
	WHERE c.pfa IS NOT NULL
	
	  AND z.zone_name ~ '^Zone (0[1-9]|1[0-9]|2[0-1])$'
	
	  AND (
	      ABS(COALESCE(c.total_kw, 0)) < 0.5
	      OR COALESCE(c.average_current_a, 0) < 1.0
	      OR ABS(
	          c.pfa - c.arithmetic_phase_pf_average
	      ) > 0.10
	  )
	
	ORDER BY
	    REGEXP_REPLACE(
	        z.zone_name,
	        '[^0-9]',
	        '',
	        'g'
	    )::integer,
	
	    m.meter_label,
	
	    ABS(
	        c.pfa - c.arithmetic_phase_pf_average
	    ) c.pfa,
	
	    c.timestamp
	
	LIMIT 1000;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        'a0396787-f0f9-4037-a5cd-232c3b6e0000'::uuid
	            AS selected_meter,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 00:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 01:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	base AS (
	    SELECT
	        f.energy_meter_key,
	        f.reading_timestamp_saudi,
	
	        f.current_phase_1_a,
	        f.current_phase_2_a,
	        f.current_phase_3_a,
	
	        (
	            f.current_phase_1_a
	            + f.current_phase_2_a
	            + f.current_phase_3_a
	        ) / 3.0 AS calculated_current_average_a
	
	    FROM silver.fact_energy_readings_staging AS f
	    CROSS JOIN params AS p
	
	    WHERE f.energy_meter_key = p.selected_meter
	      AND f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	
	      AND f.current_phase_1_a IS NOT NULL
	      AND f.current_phase_2_a IS NOT NULL
	      AND f.current_phase_3_a IS NOT NULL
	)
	
	SELECT
	    energy_meter_key,
	    reading_timestamp_saudi,
	
	    current_phase_1_a,
	    current_phase_2_a,
	    current_phase_3_a,
	
	    ROUND(
	        calculated_current_average_a::numeric,
	        2
	    ) AS calculated_current_average_a,
	
	    ROUND(
	        (
	            GREATEST(
	                current_phase_1_a,
	                current_phase_2_a,
	                current_phase_3_a
	            )
	            -
	            LEAST(
	                current_phase_1_a,
	                current_phase_2_a,
	                current_phase_3_a
	            )
	        )::numeric,
	        2
	    ) AS current_phase_spread_a,
	
	    CASE
	        WHEN ABS(calculated_current_average_a) > 0.1
	        THEN ROUND(
	            (
	                100.0
	                *
	                GREATEST(
	                    ABS(
	                        current_phase_1_a
	                        - calculated_current_average_a
	                    ),
	                    ABS(
	                        current_phase_2_a
	                        - calculated_current_average_a
	                    ),
	                    ABS(
	                        current_phase_3_a
	                        - calculated_current_average_a
	                    )
	                )
	                /
	                ABS(calculated_current_average_a)
	            )::numeric,
	            2
	        )
	    END AS current_imbalance_%
	
	FROM base
	
	ORDER BY reading_timestamp_saudi;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        'a0396787-f0f9-4037-a5cd-232c3b6e0000'::uuid
	            AS selected_meter,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 00:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-03-01 01:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	base AS (
	    SELECT
	        f.energy_meter_key,
	        f.reading_timestamp_saudi,
	
	        f.current_phase_1_a,
	        f.current_phase_2_a,
	        f.current_phase_3_a,
	
	        (
	            f.current_phase_1_a
	            + f.current_phase_2_a
	            + f.current_phase_3_a
	        ) / 3.0 AS calculated_current_average_a
	
	    FROM silver.fact_energy_readings_staging AS f
	    CROSS JOIN params AS p
	
	    WHERE f.energy_meter_key = p.selected_meter
	      AND f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	
	      AND f.current_phase_1_a IS NOT NULL
	      AND f.current_phase_2_a IS NOT NULL
	      AND f.current_phase_3_a IS NOT NULL
	)
	
	SELECT
	    energy_meter_key,
	    reading_timestamp_saudi,
	
	    current_phase_1_a,
	    current_phase_2_a,
	    current_phase_3_a,
	
	    ROUND(
	        calculated_current_average_a::numeric,
	        2
	    ) AS calculated_current_average_a,
	
	    ROUND(
	        (
	            GREATEST(
	                current_phase_1_a,
	                current_phase_2_a,
	                current_phase_3_a
	            )
	            -
	            LEAST(
	                current_phase_1_a,
	                current_phase_2_a,
	                current_phase_3_a
	            )
	        )::numeric,
	        2
	    ) AS current_phase_spread_a,
	
	    CASE
	        WHEN ABS(calculated_current_average_a) > 0.1
	        THEN ROUND(
	            (
	                100.0
	                *
	                GREATEST(
	                    ABS(
	                        current_phase_1_a
	                        - calculated_current_average_a
	                    ),
	                    ABS(
	                        current_phase_2_a
	                        - calculated_current_average_a
	                    ),
	                    ABS(
	                        current_phase_3_a
	                        - calculated_current_average_a
	                    )
	                )
	                /
	                ABS(calculated_current_average_a)
	            )::numeric,
	            2
	        )
	    END AS current_imbalance_"%"
	
	FROM base
	
	ORDER BY reading_timestamp_saudi;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    energy_meter_key,
	    reading_timestamp_saudi,
	    calculated_current_average_a,
	    current_phase_spread_a,
	    current_imbalance_pct,
	    current_imbalance_evaluation_status
	FROM silver.fact_energy_readings_staging
	WHERE current_imbalance_evaluation_status = 'EVALUATED'
	LIMIT 10;

-- ==========================================================================
-- from postgresql-2026-07-28_000000.log
-- ==========================================================================
SELECT
	    energy_meter_key,
	    reading_timestamp_saudi,
	    calculated_current_average_a,
	    current_phase_spread_a,
	    current_imbalance_pct,
	    current_imbalance_evaluation_status
	FROM silver.fact_energy_readings_staging
	WHERE current_imbalance_evaluation_status = 'EVALUATED'
	LIMIT 1;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH checked_readings AS (
	    SELECT
	        device_id,
	        reading_timestamp_utc,
	        reading_timestamp_saudi,
	        reading_date_saudi,
	        reading_time_saudi,
	
	        /* Team-approved voltage measurements */
	        v1,
	        v2,
	        v3,
	        vn1,
	        vn2,
	        vn3,
	
	        /* Team-approved current measurements */
	        amp1,
	        amp2,
	        amp3,
	
	        /* Active power */
	        tkw,
	        kw1,
	        kw2,
	        kw3,
	
	        /* Reactive power */
	        tkvar,
	
	        /* Power factor */
	        pfa,
	        pf1,
	        pf2,
	        pf3,
	
	        /* Frequency and energy */
	        hz,
	        kwh,
	        kvarh,
	
	        /* Number of approved values that are not NULL */
	        num_nonnulls(
	            v1, v2, v3,
	            vn1, vn2, vn3,
	            amp1, amp2, amp3,
	            tkw, kw1, kw2, kw3,
	            tkvar,
	            pfa, pf1, pf2, pf3,
	            hz,
	            kwh,
	            kvarh
	        ) AS populated_value_count,
	
	        /* Number of approved values that are greater than or less than zero */
	        num_nonnulls(
	            NULLIF(v1, 0),
	            NULLIF(v2, 0),
	            NULLIF(v3, 0),
	            NULLIF(vn1, 0),
	            NULLIF(vn2, 0),
	            NULLIF(vn3, 0),
	            NULLIF(amp1, 0),
	            NULLIF(amp2, 0),
	            NULLIF(amp3, 0),
	            NULLIF(tkw, 0),
	            NULLIF(kw1, 0),
	            NULLIF(kw2, 0),
	            NULLIF(kw3, 0),
	            NULLIF(tkvar, 0),
	            NULLIF(pfa, 0),
	            NULLIF(pf1, 0),
	            NULLIF(pf2, 0),
	            NULLIF(pf3, 0),
	            NULLIF(hz, 0),
	            NULLIF(kwh, 0),
	            NULLIF(kvarh, 0)
	        ) AS useful_value_count,
	
	        /* Count individual zero values */
	        (
	            CASE WHEN v1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN v2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN v3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN vn1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN vn2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN vn3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN amp1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN amp2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN amp3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN tkw = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kw1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kw2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kw3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN tkvar = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pfa = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pf1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pf2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pf3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN hz = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kwh = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kvarh = 0 THEN 1 ELSE 0 END
	        ) AS zero_value_count
	
	    FROM silver.fact_energy_readings_staging
	    WHERE reading_date_saudi = DATE '2025-03-01'
	)
	
	SELECT
	    *,
	    CASE
	        WHEN useful_value_count = 0
	            THEN 'EXCLUDE_FROM_GOLD'
	        ELSE 'KEEP_FOR_GOLD'
	    END AS gold_status
	
	FROM checked_readings
	ORDER BY
	    CASE
	        WHEN useful_value_count = 0 THEN 0
	        ELSE 1
	    END,
	    reading_timestamp_saudi,
	    device_id
	
	LIMIT 500;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH checked_readings AS (
	    SELECT
	        device_key,
	        reading_timestamp_utc,
	        reading_timestamp_saudi,
	        reading_date_saudi,
	        reading_time_saudi,
	
	        /* Team-approved voltage measurements */
	        v1,
	        v2,
	        v3,
	        vn1,
	        vn2,
	        vn3,
	
	        /* Team-approved current measurements */
	        amp1,
	        amp2,
	        amp3,
	
	        /* Active power */
	        tkw,
	        kw1,
	        kw2,
	        kw3,
	
	        /* Reactive power */
	        tkvar,
	
	        /* Power factor */
	        pfa,
	        pf1,
	        pf2,
	        pf3,
	
	        /* Frequency and energy */
	        hz,
	        kwh,
	        kvarh,
	
	        /* Number of approved values that are not NULL */
	        num_nonnulls(
	            v1, v2, v3,
	            vn1, vn2, vn3,
	            amp1, amp2, amp3,
	            tkw, kw1, kw2, kw3,
	            tkvar,
	            pfa, pf1, pf2, pf3,
	            hz,
	            kwh,
	            kvarh
	        ) AS populated_value_count,
	
	        /* Number of approved values that are greater than or less than zero */
	        num_nonnulls(
	            NULLIF(v1, 0),
	            NULLIF(v2, 0),
	            NULLIF(v3, 0),
	            NULLIF(vn1, 0),
	            NULLIF(vn2, 0),
	            NULLIF(vn3, 0),
	            NULLIF(amp1, 0),
	            NULLIF(amp2, 0),
	            NULLIF(amp3, 0),
	            NULLIF(tkw, 0),
	            NULLIF(kw1, 0),
	            NULLIF(kw2, 0),
	            NULLIF(kw3, 0),
	            NULLIF(tkvar, 0),
	            NULLIF(pfa, 0),
	            NULLIF(pf1, 0),
	            NULLIF(pf2, 0),
	            NULLIF(pf3, 0),
	            NULLIF(hz, 0),
	            NULLIF(kwh, 0),
	            NULLIF(kvarh, 0)
	        ) AS useful_value_count,
	
	        /* Count individual zero values */
	        (
	            CASE WHEN v1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN v2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN v3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN vn1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN vn2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN vn3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN amp1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN amp2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN amp3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN tkw = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kw1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kw2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kw3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN tkvar = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pfa = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pf1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pf2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN pf3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN hz = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kwh = 0 THEN 1 ELSE 0 END +
	            CASE WHEN kvarh = 0 THEN 1 ELSE 0 END
	        ) AS zero_value_count
	
	    FROM silver.fact_energy_readings_staging
	    WHERE reading_date_saudi = DATE '2025-03-01'
	)
	
	SELECT
	    *,
	    CASE
	        WHEN useful_value_count = 0
	            THEN 'EXCLUDE_FROM_GOLD'
	        ELSE 'KEEP_FOR_GOLD'
	    END AS gold_status
	
	FROM checked_readings
	ORDER BY
	    CASE
	        WHEN useful_value_count = 0 THEN 0
	        ELSE 1
	    END,
	    reading_timestamp_saudi,
	    device_id
	
	LIMIT 500;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH checked_readings AS (
	    SELECT
	        device_id,
	        reading_timestamp_saudi,
	
	        num_nonnulls(
	            NULLIF(v1, 0),
	            NULLIF(v2, 0),
	            NULLIF(v3, 0),
	            NULLIF(vn1, 0),
	            NULLIF(vn2, 0),
	            NULLIF(vn3, 0),
	            NULLIF(amp1, 0),
	            NULLIF(amp2, 0),
	            NULLIF(amp3, 0),
	            NULLIF(tkw, 0),
	            NULLIF(kw1, 0),
	            NULLIF(kw2, 0),
	            NULLIF(kw3, 0),
	            NULLIF(tkvar, 0),
	            NULLIF(pfa, 0),
	            NULLIF(pf1, 0),
	            NULLIF(pf2, 0),
	            NULLIF(pf3, 0),
	            NULLIF(hz, 0),
	            NULLIF(kwh, 0),
	            NULLIF(kvarh, 0)
	        ) AS useful_value_count
	
	    FROM silver.fact_energy_readings_staging
	    WHERE reading_date_saudi = DATE '2025-03-01'
	)
	
	SELECT
	    COUNT(*) AS total_silver_rows,
	
	    COUNT(*) FILTER (
	        WHERE useful_value_count > 0
	    ) AS rows_to_keep_in_gold,
	
	    COUNT(*) FILTER (
	        WHERE useful_value_count = 0
	    ) AS rows_to_exclude_from_gold,
	
	    ROUND(
	        100.0
	        * COUNT(*) FILTER (WHERE useful_value_count > 0)
	        / NULLIF(COUNT(*), 0),
	        2
	    ) AS kept_percentage
	
	FROM checked_readings;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH checked_readings AS (
	    SELECT
	        r.*,
	
	        /* Number of approved measurements containing any value */
	        num_nonnulls(
	            r.v1,
	            r.v2,
	            r.v3,
	            r.vn1,
	            r.vn2,
	            r.vn3,
	            r.amp1,
	            r.amp2,
	            r.amp3,
	            r.tkw,
	            r.kw1,
	            r.kw2,
	            r.kw3,
	            r.tkvar,
	            r.pfa,
	            r.pf1,
	            r.pf2,
	            r.pf3,
	            r.hz,
	            r.kwh,
	            r.kvarh
	        ) AS populated_value_count,
	
	        /* Number of approved measurements that are not zero or NULL */
	        num_nonnulls(
	            NULLIF(r.v1, 0),
	            NULLIF(r.v2, 0),
	            NULLIF(r.v3, 0),
	            NULLIF(r.vn1, 0),
	            NULLIF(r.vn2, 0),
	            NULLIF(r.vn3, 0),
	            NULLIF(r.amp1, 0),
	            NULLIF(r.amp2, 0),
	            NULLIF(r.amp3, 0),
	            NULLIF(r.tkw, 0),
	            NULLIF(r.kw1, 0),
	            NULLIF(r.kw2, 0),
	            NULLIF(r.kw3, 0),
	            NULLIF(r.tkvar, 0),
	            NULLIF(r.pfa, 0),
	            NULLIF(r.pf1, 0),
	            NULLIF(r.pf2, 0),
	            NULLIF(r.pf3, 0),
	            NULLIF(r.hz, 0),
	            NULLIF(r.kwh, 0),
	            NULLIF(r.kvarh, 0)
	        ) AS useful_value_count,
	
	        /* Number of approved measurements equal to zero */
	        (
	            CASE WHEN r.v1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.v2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.v3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.vn1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.vn2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.vn3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.amp1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.amp2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.amp3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.tkw = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.kw1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.kw2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.kw3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.tkvar = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.pfa = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.pf1 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.pf2 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.pf3 = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.hz = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.kwh = 0 THEN 1 ELSE 0 END +
	            CASE WHEN r.kvarh = 0 THEN 1 ELSE 0 END
	        ) AS zero_value_count
	
	    FROM silver.fact_energy_readings_staging AS r
	)
	
	SELECT
	    *,
	    CASE
	        WHEN useful_value_count = 0
	            THEN 'EXCLUDE_FROM_GOLD'
	        ELSE 'KEEP_FOR_GOLD'
	    END AS gold_status
	FROM checked_readings
	ORDER BY useful_value_count ASC
	LIMIT 500;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
SELECT *
	FROM silver.fact_energy_readings_staging
	LIMIT 10;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH base AS (
	    SELECT
	        f.*,
	
	        CASE
	            WHEN
	                COALESCE(ABS(f.voltage_line_1_v), 0) = 0
	                AND COALESCE(ABS(f.voltage_line_2_v), 0) = 0
	                AND COALESCE(ABS(f.voltage_line_3_v), 0) = 0
	
	                AND COALESCE(ABS(f.current_phase_1_a), 0) = 0
	                AND COALESCE(ABS(f.current_phase_2_a), 0) = 0
	                AND COALESCE(ABS(f.current_phase_3_a), 0) = 0
	
	                AND COALESCE(ABS(f.frequency_hz), 0) = 0
	
	                AND COALESCE(ABS(f.power_factor_phase_1), 0) = 0
	                AND COALESCE(ABS(f.power_factor_phase_2), 0) = 0
	                AND COALESCE(ABS(f.power_factor_phase_3), 0) = 0
	
	                AND COALESCE(ABS(f.active_power_phase_1_kw), 0) = 0
	                AND COALESCE(ABS(f.active_power_phase_2_kw), 0) = 0
	                AND COALESCE(ABS(f.active_power_phase_3_kw), 0) = 0
	                AND COALESCE(ABS(f.active_power_total_kw), 0) = 0
	
	                AND COALESCE(
	                    ABS(f.active_energy_cumulative_kwh),
	                    0
	                ) = 0
	
	            THEN 'EMPTY_OR_ALL_ZERO'
	            ELSE 'USABLE'
	        END AS gold_row_status
	
	    FROM silver.fact_energy_readings_staging AS f
	
	    WHERE f.reading_date_saudi = DATE '2025-04-16'
	)
	
	SELECT
	    gold_row_status,
	    COUNT(*) AS reading_count
	FROM base
	GROUP BY gold_row_status
	ORDER BY gold_row_status;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        1744741200000::bigint AS start_ms,
	        1744744800000::bigint AS end_ms
	)
	
	SELECT
	    silver_readings,
	    gold_readings,
	    silver_readings - gold_readings AS empty_rows_excluded
	
	FROM params AS p
	
	CROSS JOIN LATERAL (
	    SELECT COUNT(*) AS silver_readings
	    FROM silver.fact_energy_readings_staging AS f
	    WHERE f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	) AS s
	
	CROSS JOIN LATERAL (
	    SELECT COUNT(*) AS gold_readings
	    FROM gold.energy_reading AS g
	    WHERE g.source_timestamp_ms >= p.start_ms
	      AND g.source_timestamp_ms < p.end_ms
	) AS gold;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
SELECT COUNT(*)
	FROM gold.energy_reading
	WHERE source_timestamp_ms >= 1744741200000
	  AND source_timestamp_ms < 1744744800000;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH counts AS (
	    SELECT
	        COUNT(*) AS silver_readings,
	
	        COUNT(*) FILTER (
	            WHERE
	                /* Put the WHERE condition from gold.energy_reading here */
	                gold_row_condition
	        ) AS gold_readings
	
	    FROM silver.fact_energy_readings_staging AS f
	
	    WHERE f.source_timestamp_ms >= 1744741200000
	      AND f.source_timestamp_ms < 1744744800000
	)
	
	SELECT
	    silver_readings,
	    gold_readings,
	    silver_readings - gold_readings AS empty_rows_excluded
	FROM counts;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
WITH params AS (
	    SELECT
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-04-16 00:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS start_ms,
	
	        (
	            EXTRACT(
	                EPOCH FROM (
	                    TIMESTAMP '2025-04-16 01:00:00'
	                    AT TIME ZONE 'Asia/Riyadh'
	                )
	            ) * 1000
	        )::bigint AS end_ms
	),
	
	silver_count AS (
	    SELECT COUNT(*) AS reading_count
	    FROM silver.fact_energy_readings_staging AS f
	    CROSS JOIN params AS p
	    WHERE f.source_timestamp_ms >= p.start_ms
	      AND f.source_timestamp_ms < p.end_ms
	),
	
	gold_count AS (
	    SELECT COUNT(*) AS reading_count
	    FROM gold.energy_reading AS g
	    CROSS JOIN params AS p
	    WHERE g.source_timestamp_ms >= p.start_ms
	      AND g.source_timestamp_ms < p.end_ms
	)
	
	SELECT
	    s.reading_count AS silver_readings,
	    g.reading_count AS gold_readings,
	    s.reading_count - g.reading_count AS empty_rows_excluded
	FROM silver_count AS s
	CROSS JOIN gold_count AS g;

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
select * 

	from 

	(

	    SELECT 1 AS test_value;

	) "_"

	limit 0

-- ==========================================================================
-- from postgresql-2026-07-29_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."current_phase_1" as "current_phase_1",

	    "$Table"."current_phase_2" as "current_phase_2",

	    "$Table"."current_phase_3" as "current_phase_3",

	    "$Table"."current_average" as "current_average",

	    "$Table"."current_phase_spread" as "current_phase_spread",

	    "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	    "$Table"."current_imbalance_status" as "current_imbalance_status"

	from "gold"."current_imbalance" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."date" as "date",

	    "$Table"."hour" as "hour",

	    "$Table"."day_of_week" as "day_of_week",

	    "$Table"."day_of_month" as "day_of_month",

	    "$Table"."month" as "month",

	    "$Table"."is_weekend" as "is_weekend",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."previous_hour_consumption" as "previous_hour_consumption",

	    "$Table"."previous_day_consumption" as "previous_day_consumption",

	    "$Table"."previous_week_consumption" as "previous_week_consumption",

	    "$Table"."rolling_24_hour_average" as "rolling_24_hour_average",

	    "$Table"."rolling_7_day_average" as "rolling_7_day_average",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."energy_forecasting" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."hour_of_day" as "hour_of_day",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."energy_delta_count" as "energy_delta_count",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent"

	from "gold"."hourly_energy" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."date" as "date",

	    "$Table"."hour" as "hour",

	    "$Table"."day_of_week" as "day_of_week",

	    "$Table"."day_of_month" as "day_of_month",

	    "$Table"."month" as "month",

	    "$Table"."is_weekend" as "is_weekend",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."previous_hour_consumption" as "previous_hour_consumption",

	    "$Table"."previous_day_consumption" as "previous_day_consumption",

	    "$Table"."previous_week_consumption" as "previous_week_consumption",

	    "$Table"."rolling_24_hour_average" as "rolling_24_hour_average",

	    "$Table"."rolling_7_day_average" as "rolling_7_day_average",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."energy_forecasting" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."zone_count" as "zone_count",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."facility_reading" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."frequency" as "frequency",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."voltage_status" as "voltage_status",

	    "$Table"."frequency_status" as "frequency_status",

	    "$Table"."power_factor_status" as "power_factor_status",

	    "$Table"."overall_status" as "overall_status"

	from "gold"."power_quality" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."voltage_phase_1" as "voltage_phase_1",

	    "$Table"."voltage_phase_2" as "voltage_phase_2",

	    "$Table"."voltage_phase_3" as "voltage_phase_3",

	    "$Table"."voltage_average" as "voltage_average",

	    "$Table"."voltage_phase_spread" as "voltage_phase_spread",

	    "$Table"."voltage_imbalance_percent" as "voltage_imbalance_percent",

	    "$Table"."voltage_imbalance_status" as "voltage_imbalance_status"

	from "gold"."voltage_imbalance" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."zone_reading" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."duplicate_measurement_count" as "duplicate_measurement_count",

	    "$Table"."average_populated_measurement_count" as "average_populated_measurement_count",

	    "$Table"."populated_measurement_percent" as "populated_measurement_percent",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."measurement_coverage_status" as "measurement_coverage_status",

	    "$Table"."quality_status" as "quality_status"

	from "gold"."data_quality" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."date" as "date",

	    "$Table"."hour" as "hour",

	    "$Table"."day_of_week" as "day_of_week",

	    "$Table"."day_of_month" as "day_of_month",

	    "$Table"."month" as "month",

	    "$Table"."is_weekend" as "is_weekend",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."previous_hour_consumption" as "previous_hour_consumption",

	    "$Table"."previous_day_consumption" as "previous_day_consumption",

	    "$Table"."previous_week_consumption" as "previous_week_consumption",

	    "$Table"."rolling_24_hour_average" as "rolling_24_hour_average",

	    "$Table"."rolling_7_day_average" as "rolling_7_day_average",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."energy_forecasting" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."active" as "active",

	    "$Table"."online" as "online",

	    "$Table"."first_seen" as "first_seen",

	    "$Table"."latest_reading_timestamp" as "latest_reading_timestamp",

	    "$Table"."status_reference_timestamp" as "status_reference_timestamp",

	    "$Table"."minutes_since_latest_reading" as "minutes_since_latest_reading",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."meter_status" as "meter_status"

	from "gold"."meter_status" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."month" as "month",

	    "$Table"."year" as "year",

	    "$Table"."month_number" as "month_number",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."monthly_energy" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."active" as "active",

	    "$Table"."online" as "online",

	    "$Table"."first_seen" as "first_seen",

	    "$Table"."latest_reading_timestamp" as "latest_reading_timestamp",

	    "$Table"."status_reference_timestamp" as "status_reference_timestamp",

	    "$Table"."minutes_since_latest_reading" as "minutes_since_latest_reading",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."meter_status" as "meter_status"

	from "gold"."meter_status" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."month" as "month",

	    "$Table"."year" as "year",

	    "$Table"."month_number" as "month_number",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."monthly_energy" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."peak_active_power_kw" as "peak_active_power_kw",

	    "$Table"."peak_timestamp_saudi" as "peak_timestamp_saudi",

	    "$Table"."average_active_power_kw" as "average_active_power_kw",

	    "$Table"."minimum_active_power_kw" as "minimum_active_power_kw",

	    "$Table"."load_factor_percent" as "load_factor_percent"

	from "gold"."peak_demand" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."peak_active_power_kw" as "peak_active_power_kw",

	    "$Table"."peak_timestamp_saudi" as "peak_timestamp_saudi",

	    "$Table"."average_active_power_kw" as "average_active_power_kw",

	    "$Table"."minimum_active_power_kw" as "minimum_active_power_kw",

	    "$Table"."load_factor_percent" as "load_factor_percent"

	from "gold"."peak_demand" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."peak_active_power_kw" as "peak_active_power_kw",

	    "$Table"."peak_timestamp_saudi" as "peak_timestamp_saudi",

	    "$Table"."average_active_power_kw" as "average_active_power_kw",

	    "$Table"."minimum_active_power_kw" as "minimum_active_power_kw",

	    "$Table"."load_factor_percent" as "load_factor_percent"

	from "gold"."peak_demand" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    "$Table"."date_key" as "date_key",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."daily_energy" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."current_phase_1" as "current_phase_1",

	    "$Table"."current_phase_2" as "current_phase_2",

	    "$Table"."current_phase_3" as "current_phase_3",

	    "$Table"."current_average" as "current_average",

	    "$Table"."current_phase_spread" as "current_phase_spread",

	    "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	    "$Table"."current_imbalance_status" as "current_imbalance_status"

	from "gold"."current_imbalance" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."month" as "month",

	    "$Table"."year" as "year",

	    "$Table"."month_number" as "month_number",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."monthly_energy" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."date_key" as "date_key",

	    "$Table"."time_key" as "time_key",

	    "$Table"."source_timestamp_ms" as "source_timestamp_ms",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."voltage_line_average_v" as "voltage_line_average_v",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."source_measurement_row_count" as "source_measurement_row_count",

	    "$Table"."populated_measurement_count" as "populated_measurement_count",

	    "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

	    "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    "$Table"."calculated_current_average_a" as "calculated_current_average_a",

	    "$Table"."current_phase_spread_a" as "current_phase_spread_a",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

	    "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

	    "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status"

	from "gold"."energy_reading" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    "$Table"."date_key" as "date_key",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."daily_energy" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."duplicate_measurement_count" as "duplicate_measurement_count",

	    "$Table"."average_populated_measurement_count" as "average_populated_measurement_count",

	    "$Table"."populated_measurement_percent" as "populated_measurement_percent",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."measurement_coverage_status" as "measurement_coverage_status",

	    "$Table"."quality_status" as "quality_status"

	from "gold"."data_quality" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    "$Table"."date_key" as "date_key",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."daily_energy" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."zone_reading" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."duplicate_measurement_count" as "duplicate_measurement_count",

	    "$Table"."average_populated_measurement_count" as "average_populated_measurement_count",

	    "$Table"."populated_measurement_percent" as "populated_measurement_percent",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."measurement_coverage_status" as "measurement_coverage_status",

	    "$Table"."quality_status" as "quality_status"

	from "gold"."data_quality" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."date_key" as "date_key",

	    "$Table"."time_key" as "time_key",

	    "$Table"."source_timestamp_ms" as "source_timestamp_ms",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."voltage_line_average_v" as "voltage_line_average_v",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."source_measurement_row_count" as "source_measurement_row_count",

	    "$Table"."populated_measurement_count" as "populated_measurement_count",

	    "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

	    "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    "$Table"."calculated_current_average_a" as "calculated_current_average_a",

	    "$Table"."current_phase_spread_a" as "current_phase_spread_a",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

	    "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

	    "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status"

	from "gold"."energy_reading" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."zone_count" as "zone_count",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."facility_reading" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    "$Table"."date_key" as "date_key",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."daily_energy" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."date_key" as "date_key",

	    "$Table"."time_key" as "time_key",

	    "$Table"."source_timestamp_ms" as "source_timestamp_ms",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."voltage_line_average_v" as "voltage_line_average_v",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."source_measurement_row_count" as "source_measurement_row_count",

	    "$Table"."populated_measurement_count" as "populated_measurement_count",

	    "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

	    "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    "$Table"."calculated_current_average_a" as "calculated_current_average_a",

	    "$Table"."current_phase_spread_a" as "current_phase_spread_a",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

	    "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

	    "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status"

	from "gold"."energy_reading" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."voltage_phase_1" as "voltage_phase_1",

	    "$Table"."voltage_phase_2" as "voltage_phase_2",

	    "$Table"."voltage_phase_3" as "voltage_phase_3",

	    "$Table"."voltage_average" as "voltage_average",

	    "$Table"."voltage_phase_spread" as "voltage_phase_spread",

	    "$Table"."voltage_imbalance_percent" as "voltage_imbalance_percent",

	    "$Table"."voltage_imbalance_status" as "voltage_imbalance_status"

	from "gold"."voltage_imbalance" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."active" as "active",

	    "$Table"."online" as "online",

	    "$Table"."first_seen" as "first_seen",

	    "$Table"."latest_reading_timestamp" as "latest_reading_timestamp",

	    "$Table"."status_reference_timestamp" as "status_reference_timestamp",

	    "$Table"."minutes_since_latest_reading" as "minutes_since_latest_reading",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."meter_status" as "meter_status"

	from "gold"."meter_status" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."date_key" as "date_key",

	    "$Table"."time_key" as "time_key",

	    "$Table"."source_timestamp_ms" as "source_timestamp_ms",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."voltage_line_average_v" as "voltage_line_average_v",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."source_measurement_row_count" as "source_measurement_row_count",

	    "$Table"."populated_measurement_count" as "populated_measurement_count",

	    "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

	    "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    "$Table"."calculated_current_average_a" as "calculated_current_average_a",

	    "$Table"."current_phase_spread_a" as "current_phase_spread_a",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

	    "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

	    "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status",

	    "$Table"."meter" as "meter",

	    "$Table"."meter_serial_number" as "meter_serial_number",

	    "$Table"."phase_count" as "phase_count",

	    "$Table"."energy_meter_type_name" as "energy_meter_type_name",

	    "$Table"."is_meter_active" as "is_meter_active",

	    "$Table"."device" as "device",

	    "$Table"."device_label" as "device_label",

	    "$Table"."device_serial_number" as "device_serial_number",

	    "$Table"."device_type_name" as "device_type_name",

	    "$Table"."device_category_name" as "device_category_name",

	    "$Table"."is_device_active" as "is_device_active",

	    "$Table"."is_device_online" as "is_device_online",

	    "$Table"."mapping_status" as "mapping_status",

	    "$Table"."zone" as "zone",

	    "$Table"."parent_zone_name" as "parent_zone_name",

	    "$Table"."hierarchy_level" as "hierarchy_level",

	    "$Table"."facility" as "facility"

	from "gold"."meter_reading" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."voltage_phase_1" as "voltage_phase_1",

	    "$Table"."voltage_phase_2" as "voltage_phase_2",

	    "$Table"."voltage_phase_3" as "voltage_phase_3",

	    "$Table"."voltage_average" as "voltage_average",

	    "$Table"."voltage_phase_spread" as "voltage_phase_spread",

	    "$Table"."voltage_imbalance_percent" as "voltage_imbalance_percent",

	    "$Table"."voltage_imbalance_status" as "voltage_imbalance_status"

	from "gold"."voltage_imbalance" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."hour_of_day" as "hour_of_day",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."energy_delta_count" as "energy_delta_count",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent"

	from "gold"."hourly_energy" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."frequency" as "frequency",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."voltage_status" as "voltage_status",

	    "$Table"."frequency_status" as "frequency_status",

	    "$Table"."power_factor_status" as "power_factor_status",

	    "$Table"."overall_status" as "overall_status"

	from "gold"."power_quality" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."date_key" as "date_key",

	    "$Table"."time_key" as "time_key",

	    "$Table"."source_timestamp_ms" as "source_timestamp_ms",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."voltage_line_average_v" as "voltage_line_average_v",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."source_measurement_row_count" as "source_measurement_row_count",

	    "$Table"."populated_measurement_count" as "populated_measurement_count",

	    "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

	    "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    "$Table"."calculated_current_average_a" as "calculated_current_average_a",

	    "$Table"."current_phase_spread_a" as "current_phase_spread_a",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

	    "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

	    "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status",

	    "$Table"."meter" as "meter",

	    "$Table"."meter_serial_number" as "meter_serial_number",

	    "$Table"."phase_count" as "phase_count",

	    "$Table"."energy_meter_type_name" as "energy_meter_type_name",

	    "$Table"."is_meter_active" as "is_meter_active",

	    "$Table"."device" as "device",

	    "$Table"."device_label" as "device_label",

	    "$Table"."device_serial_number" as "device_serial_number",

	    "$Table"."device_type_name" as "device_type_name",

	    "$Table"."device_category_name" as "device_category_name",

	    "$Table"."is_device_active" as "is_device_active",

	    "$Table"."is_device_online" as "is_device_online",

	    "$Table"."mapping_status" as "mapping_status",

	    "$Table"."zone" as "zone",

	    "$Table"."parent_zone_name" as "parent_zone_name",

	    "$Table"."hierarchy_level" as "hierarchy_level",

	    "$Table"."facility" as "facility"

	from "gold"."meter_reading" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."peak_active_power_kw" as "peak_active_power_kw",

	    "$Table"."peak_timestamp_saudi" as "peak_timestamp_saudi",

	    "$Table"."average_active_power_kw" as "average_active_power_kw",

	    "$Table"."minimum_active_power_kw" as "minimum_active_power_kw",

	    "$Table"."load_factor_percent" as "load_factor_percent"

	from "gold"."peak_demand" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."date" as "date",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."duplicate_measurement_count" as "duplicate_measurement_count",

	    "$Table"."average_populated_measurement_count" as "average_populated_measurement_count",

	    "$Table"."populated_measurement_percent" as "populated_measurement_percent",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."measurement_coverage_status" as "measurement_coverage_status",

	    "$Table"."quality_status" as "quality_status"

	from "gold"."data_quality" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."date" as "date",

	    "$Table"."hour" as "hour",

	    "$Table"."day_of_week" as "day_of_week",

	    "$Table"."day_of_month" as "day_of_month",

	    "$Table"."month" as "month",

	    "$Table"."is_weekend" as "is_weekend",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."previous_hour_consumption" as "previous_hour_consumption",

	    "$Table"."previous_day_consumption" as "previous_day_consumption",

	    "$Table"."previous_week_consumption" as "previous_week_consumption",

	    "$Table"."rolling_24_hour_average" as "rolling_24_hour_average",

	    "$Table"."rolling_7_day_average" as "rolling_7_day_average",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."energy_forecasting" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."month" as "month",

	    "$Table"."year" as "year",

	    "$Table"."month_number" as "month_number",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."missing_reading_count" as "missing_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count"

	from "gold"."monthly_energy" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."frequency" as "frequency",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."voltage_status" as "voltage_status",

	    "$Table"."frequency_status" as "frequency_status",

	    "$Table"."power_factor_status" as "power_factor_status",

	    "$Table"."overall_status" as "overall_status"

	from "gold"."power_quality" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."source_energy_meter_id" as varchar) as "source_energy_meter_id",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."date_key" as "date_key",

	    "$Table"."time_key" as "time_key",

	    "$Table"."source_timestamp_ms" as "source_timestamp_ms",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."voltage_line_average_v" as "voltage_line_average_v",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_neutral_average_v" as "voltage_neutral_average_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."source_measurement_row_count" as "source_measurement_row_count",

	    "$Table"."populated_measurement_count" as "populated_measurement_count",

	    "$Table"."duplicate_measurement_row_count" as "duplicate_measurement_row_count",

	    "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    "$Table"."calculated_current_average_a" as "calculated_current_average_a",

	    "$Table"."current_phase_spread_a" as "current_phase_spread_a",

	    "$Table"."current_imbalance_pct" as "current_imbalance_pct",

	    "$Table"."current_imbalance_evaluation_status" as "current_imbalance_evaluation_status",

	    "$Table"."calculated_voltage_average_v" as "calculated_voltage_average_v",

	    "$Table"."voltage_phase_spread_v" as "voltage_phase_spread_v",

	    "$Table"."voltage_imbalance_pct" as "voltage_imbalance_pct",

	    "$Table"."voltage_imbalance_evaluation_status" as "voltage_imbalance_evaluation_status",

	    "$Table"."meter" as "meter",

	    "$Table"."meter_serial_number" as "meter_serial_number",

	    "$Table"."phase_count" as "phase_count",

	    "$Table"."energy_meter_type_name" as "energy_meter_type_name",

	    "$Table"."is_meter_active" as "is_meter_active",

	    "$Table"."device" as "device",

	    "$Table"."device_label" as "device_label",

	    "$Table"."device_serial_number" as "device_serial_number",

	    "$Table"."device_type_name" as "device_type_name",

	    "$Table"."device_category_name" as "device_category_name",

	    "$Table"."is_device_active" as "is_device_active",

	    "$Table"."is_device_online" as "is_device_online",

	    "$Table"."mapping_status" as "mapping_status",

	    "$Table"."zone" as "zone",

	    "$Table"."parent_zone_name" as "parent_zone_name",

	    "$Table"."hierarchy_level" as "hierarchy_level",

	    "$Table"."facility" as "facility"

	from "gold"."meter_reading" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."zone_reading" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."zone_reading" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."saudi_time_key" as "saudi_time_key",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."zone_count" as "zone_count",

	    "$Table"."meter_count" as "meter_count",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."frequency_average_hz" as "frequency_average_hz",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."aggregation_status" as "aggregation_status"

	from "gold"."facility_reading" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_hour_saudi" as "reading_hour_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."saudi_date_key" as "saudi_date_key",

	    "$Table"."hour_of_day" as "hour_of_day",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."energy_consumption_kwh" as "energy_consumption_kwh",

	    "$Table"."energy_delta_count" as "energy_delta_count",

	    "$Table"."cumulative_reset_or_decrease_count" as "cumulative_reset_or_decrease_count",

	    "$Table"."active_power_average_kw" as "active_power_average_kw",

	    "$Table"."active_power_peak_kw" as "active_power_peak_kw",

	    "$Table"."active_power_minimum_kw" as "active_power_minimum_kw",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."voltage_average_v" as "voltage_average_v",

	    "$Table"."current_average_a" as "current_average_a",

	    "$Table"."current_imbalance_average_pct" as "current_imbalance_average_pct",

	    "$Table"."current_imbalance_maximum_pct" as "current_imbalance_maximum_pct",

	    "$Table"."voltage_imbalance_average_pct" as "voltage_imbalance_average_pct",

	    "$Table"."voltage_imbalance_maximum_pct" as "voltage_imbalance_maximum_pct",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent"

	from "gold"."hourly_energy" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."current_phase_1" as "current_phase_1",

	    "$Table"."current_phase_2" as "current_phase_2",

	    "$Table"."current_phase_3" as "current_phase_3",

	    "$Table"."current_average" as "current_average",

	    "$Table"."current_phase_spread" as "current_phase_spread",

	    "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	    "$Table"."current_imbalance_status" as "current_imbalance_status"

	from "gold"."current_imbalance" "$Table"

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "$Table"."reading_date_saudi" as "reading_date_saudi",

	    "$Table"."reading_time_saudi" as "reading_time_saudi",

	    cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."current_phase_1" as "current_phase_1",

	    "$Table"."current_phase_2" as "current_phase_2",

	    "$Table"."current_phase_3" as "current_phase_3",

	    "$Table"."current_average" as "current_average",

	    "$Table"."current_phase_spread" as "current_phase_spread",

	    "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	    "$Table"."current_imbalance_status" as "current_imbalance_status"

	from "gold"."current_imbalance" "$Table"

	limit 100

-- ==========================================================================
-- from postgresql-2026-07-30_000000.log
-- ==========================================================================
select cast("$Table"."meter_id" as varchar) as "meter_id",

	    "$Table"."meter" as "meter",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    "$Table"."zone" as "zone",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    "$Table"."facility" as "facility",

	    "$Table"."active" as "active",

	    "$Table"."online" as "online",

	    "$Table"."first_seen" as "first_seen",

	    "$Table"."latest_reading_timestamp" as "latest_reading_timestamp",

	    "$Table"."status_reference_timestamp" as "status_reference_timestamp",

	    "$Table"."minutes_since_latest_reading" as "minutes_since_latest_reading",

	    "$Table"."expected_reading_count" as "expected_reading_count",

	    "$Table"."actual_reading_count" as "actual_reading_count",

	    "$Table"."data_completeness_percent" as "data_completeness_percent",

	    "$Table"."meter_status" as "meter_status"

	from "gold"."meter_status" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select "_"."meter_id"

	from 

	(

	    select "rows"."meter_id" as "meter_id"

	    from 

	    (

	        select cast("$Table"."meter_id" as varchar) as "meter_id"

	        from "gold"."current_imbalance" "$Table"

	    ) "rows"

	    group by "meter_id"

	) "_"

	order by "_"."meter_id"

	limit 501

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select "_"."meter_id",

	    "_"."a0"

	from 

	(

	    select "rows"."meter_id" as "meter_id",

	        sum("rows"."current_average") as "a0"

	    from 

	    (

	        select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	            "$Table"."reading_date_saudi" as "reading_date_saudi",

	            "$Table"."reading_time_saudi" as "reading_time_saudi",

	            cast("$Table"."meter_id" as varchar) as "meter_id",

	            "$Table"."meter" as "meter",

	            cast("$Table"."zone_key" as varchar) as "zone_key",

	            "$Table"."zone" as "zone",

	            cast("$Table"."facility_key" as varchar) as "facility_key",

	            "$Table"."facility" as "facility",

	            "$Table"."current_phase_1" as "current_phase_1",

	            "$Table"."current_phase_2" as "current_phase_2",

	            "$Table"."current_phase_3" as "current_phase_3",

	            "$Table"."current_average" as "current_average",

	            "$Table"."current_phase_spread" as "current_phase_spread",

	            "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	            "$Table"."current_imbalance_status" as "current_imbalance_status"

	        from "gold"."current_imbalance" "$Table"

	    ) "rows"

	    group by "meter_id"

	) "_"

	where not "_"."a0" is null

	limit 1000001

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select "_"."zone"

	from 

	(

	    select "rows"."zone" as "zone"

	    from 

	    (

	        select "$Table"."zone" as "zone"

	        from "gold"."current_imbalance" "$Table"

	    ) "rows"

	    group by "zone"

	) "_"

	order by "_"."zone"

	limit 501

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select "rows"."meter_id" as "meter_id",

	    count(1) as "a0"

	from 

	(

	    select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	        "$Table"."reading_date_saudi" as "reading_date_saudi",

	        "$Table"."reading_time_saudi" as "reading_time_saudi",

	        cast("$Table"."meter_id" as varchar) as "meter_id",

	        "$Table"."meter" as "meter",

	        cast("$Table"."zone_key" as varchar) as "zone_key",

	        "$Table"."zone" as "zone",

	        cast("$Table"."facility_key" as varchar) as "facility_key",

	        "$Table"."facility" as "facility",

	        "$Table"."current_phase_1" as "current_phase_1",

	        "$Table"."current_phase_2" as "current_phase_2",

	        "$Table"."current_phase_3" as "current_phase_3",

	        "$Table"."current_average" as "current_average",

	        "$Table"."current_phase_spread" as "current_phase_spread",

	        "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	        "$Table"."current_imbalance_status" as "current_imbalance_status"

	    from "gold"."current_imbalance" "$Table"

	) "rows"

	group by "meter_id"

	limit 1000001

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select "_"."zone_key",

	    "_"."zone"

	from 

	(

	    select "rows"."zone_key" as "zone_key",

	        "rows"."zone" as "zone"

	    from 

	    (

	        select cast("$Table"."zone_key" as varchar) as "zone_key",

	            "$Table"."zone" as "zone"

	        from "gold"."current_imbalance" "$Table"

	    ) "rows"

	    group by "zone_key",

	        "zone"

	) "_"

	order by "_"."zone",

	        "_"."zone_key"

	limit 501

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select sum("rows"."current_average") as "a0"

	from 

	(

	    select "$Table"."current_average" as "current_average"

	    from "gold"."current_imbalance" "$Table"

	) "rows"

-- ==========================================================================
-- from postgresql-2026-07-31_000000.log
-- ==========================================================================
select "_"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	    "_"."reading_date_saudi" as "reading_date_saudi",

	    "_"."reading_time_saudi" as "reading_time_saudi",

	    "_"."meter_id" as "meter_id",

	    "_"."meter" as "meter",

	    "_"."zone_key" as "zone_key",

	    "_"."zone" as "zone",

	    "_"."facility_key" as "facility_key",

	    "_"."facility" as "facility",

	    "_"."current_phase_1" as "current_phase_1",

	    "_"."current_phase_2" as "current_phase_2",

	    "_"."current_phase_3" as "current_phase_3",

	    "_"."current_average" as "current_average",

	    "_"."current_phase_spread" as "current_phase_spread",

	    "_"."current_imbalance_percent" as "current_imbalance_percent",

	    "_"."current_imbalance_status" as "current_imbalance_status",

	    1 as "c0"

	from 

	(

	    select "$Table"."reading_timestamp_saudi" as "reading_timestamp_saudi",

	        "$Table"."reading_date_saudi" as "reading_date_saudi",

	        "$Table"."reading_time_saudi" as "reading_time_saudi",

	        cast("$Table"."meter_id" as varchar) as "meter_id",

	        "$Table"."meter" as "meter",

	        cast("$Table"."zone_key" as varchar) as "zone_key",

	        "$Table"."zone" as "zone",

	        cast("$Table"."facility_key" as varchar) as "facility_key",

	        "$Table"."facility" as "facility",

	        "$Table"."current_phase_1" as "current_phase_1",

	        "$Table"."current_phase_2" as "current_phase_2",

	        "$Table"."current_phase_3" as "current_phase_3",

	        "$Table"."current_average" as "current_average",

	        "$Table"."current_phase_spread" as "current_phase_spread",

	        "$Table"."current_imbalance_percent" as "current_imbalance_percent",

	        "$Table"."current_imbalance_status" as "current_imbalance_status"

	    from "gold"."current_imbalance" "$Table"

	) "_"

	limit 3

-- ==========================================================================
-- from postgresql-2026-08-02_152512.log
-- ==========================================================================
DROP SCHEMA IF EXISTS gold CASCADE;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
-- Columns of the Silver staging fact view
	SELECT column_name, data_type
	FROM information_schema.columns
	WHERE table_schema = 'silver' AND table_name = 'fact_energy_readings_staging'
	ORDER BY ordinal_position;
	
	-- Columns of the Silver energy meter dimension
	SELECT column_name, data_type
	FROM information_schema.columns
	WHERE table_schema = 'silver' AND table_name = 'dim_energy_meter_staging'
	ORDER BY ordinal_position;
	
	-- Sample rows so we can see actual values (limit keeps it light)
	SELECT * FROM silver.fact_energy_readings_staging LIMIT 20;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT DISTINCT energy_meter_id
	FROM silver.fact_energy_readings_staging
	LIMIT 20;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT MIN(reading_timestamp_utc) AS earliest, MAX(reading_timestamp_utc) AS latest
	FROM silver.fact_energy_readings_staging
	WHERE energy_meter_id = 1;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
WITH one_meter_one_week AS (
	    SELECT
	        energy_meter_id,
	        reading_timestamp_utc,
	        kwh
	    FROM silver.fact_energy_readings_staging
	    WHERE energy_meter_id = 1
	      AND reading_timestamp_utc >= '2026-07-01'
	      AND reading_timestamp_utc <  '2026-07-08'
	    ORDER BY reading_timestamp_utc
	)
	SELECT
	    reading_timestamp_utc,
	    kwh,
	    reading_timestamp_utc - LAG(reading_timestamp_utc) OVER (ORDER BY reading_timestamp_utc) AS time_gap,
	    kwh - LAG(kwh) OVER (ORDER BY reading_timestamp_utc) AS kwh_delta
	FROM one_meter_one_week;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
WITH one_meter_one_week AS (
	    SELECT
	        energy_meter_id,
	        reading_timestamp_utc,
	        kwh
	    FROM silver.fact_energy_readings_staging
	    WHERE energy_meter_id = 1
	      AND reading_timestamp_utc >= '2026-07-01'
	      AND reading_timestamp_utc <  '2026-07-08'
	),
	deltas AS (
	    SELECT
	        kwh - LAG(kwh) OVER (ORDER BY reading_timestamp_utc) AS kwh_delta
	    FROM one_meter_one_week
	)
	SELECT
	    COUNT(*) FILTER (WHERE kwh_delta < 0)  AS negative_deltas,
	    COUNT(*) FILTER (WHERE kwh_delta = 0)  AS zero_deltas,
	    COUNT(*) FILTER (WHERE kwh_delta > 0)  AS positive_deltas,
	    COUNT(*) FILTER (WHERE kwh_delta IS NULL) AS null_deltas
	FROM deltas;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT *
	FROM silver.fact_energy_readings_staging
	LIMIT 20;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT a0396787-f0f9-4037-a5cd-232c3b6edde3, key
	FROM bronze.telemetries_dictionaries
	WHERE key IN ('kWh', 'V1', 'Amp1', 'TkW');

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    device_id,
	    key_id,
	    "timestamp",
	    to_timestamp("timestamp"::numeric / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	    dbl,
	    long
	FROM bronze.telemetries
	WHERE device_id = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND key_id = <kwh_id_from_step_1>
	  AND "timestamp" >= extract(epoch FROM timestamp '2026-07-01 00:00:00 UTC') * 1000
	  AND "timestamp" <  extract(epoch FROM timestamp '2026-07-08 00:00:00 UTC') * 1000
	ORDER BY "timestamp";

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    device_id,
	    key_id,
	    "timestamp",
	    to_timestamp("timestamp"::numeric / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	    dbl,
	    long
	FROM bronze.telemetries
	WHERE device_id = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND key_id = a0396787-f0f9-4037-a5cd-232c3b6edde3
	  AND "timestamp" >= extract(epoch FROM timestamp '2026-07-01 00:00:00 UTC') * 1000
	  AND "timestamp" <  extract(epoch FROM timestamp '2026-07-08 00:00:00 UTC') * 1000
	ORDER BY "timestamp";

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    device_id,
	    key_id,
	    "timestamp",
	    to_timestamp("timestamp"::numeric / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	    dbl,
	    long
	FROM bronze.telemetries
	WHERE device_id = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND key_id = 23
	  AND "timestamp" >= extract(epoch FROM timestamp '2026-07-01 00:00:00 UTC') * 1000
	  AND "timestamp" <  extract(epoch FROM timestamp '2026-07-08 00:00:00 UTC') * 1000
	ORDER BY "timestamp";

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    device_id,
	    key_id,
	    "timestamp",
	    to_timestamp("timestamp"::numeric / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	    dbl,
	    long
	FROM bronze.telemetries
	WHERE device_id = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND key_id = 23
	  AND "timestamp" >= extract(epoch FROM timestamp '2025-07-01 00:00:00 UTC') * 1000
	  AND "timestamp" <  extract(epoch FROM timestamp '2026-07-02 00:00:00 UTC') * 1000
	ORDER BY "timestamp";

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    device_id,
	    key_id,
	    "timestamp",
	    to_timestamp("timestamp"::numeric / 1000.0) AT TIME ZONE 'UTC' AS reading_timestamp_utc,
	    dbl,
	    long
	FROM bronze.telemetries
	WHERE device_id = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND key_id = 41
	  AND "timestamp" >= extract(epoch FROM timestamp '2025-07-01 00:00:00 UTC') * 1000
	  AND "timestamp" <  extract(epoch FROM timestamp '2025-07-01 06:00:00 UTC') * 1000
	ORDER BY "timestamp";

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
-- ============================================================
	-- silver.fact_energy_readings_flagged
	--
	-- Row-level data quality flagging view built on top of
	-- silver.fact_energy_readings_staging.
	--
	-- Adds boolean flag columns per the SADINhub flagging criteria
	-- (voltage, current, frequency, power factor, active/apparent/
	-- reactive power, accumulated energy).
	--
	-- IMPORTANT PLACEHOLDERS TO EDIT BEFORE PRODUCTION USE:
	--   - v_cb_max_rating_a   : circuit breaker max current rating
	--                            (varies per meter -- currently a
	--                            single placeholder constant)
	--   - v_kva_user_max      : user-defined max apparent power
	--   - v_kvar_user_max     : user-defined max reactive power
	--   - v_kwh_user_max      : user-defined max cumulative kWh
	--   - v_kvah_user_max     : user-defined max cumulative kVAh
	--   - v_kvarh_user_max    : user-defined max cumulative kVArh
	--
	-- Once meter-specific CB ratings / user-defined maxes are
	-- available (e.g. from a lookup table), replace the constants
	-- below with a JOIN to that table instead.
	-- ============================================================
	
	CREATE OR REPLACE VIEW silver.fact_energy_readings_flagged AS
	WITH constants AS (
	    SELECT
	        30.0  AS spike_moderate_pct,      -- >=30% change vs previous reading
	        50.0  AS spike_high_pct,          -- >=50% change vs previous reading
	        5.0   AS consistency_tolerance_pct, -- total vs sum-of-phases tolerance
	        -- --- PLACEHOLDERS: replace with real values or a lookup join ---
	        9999999.0 AS v_cb_max_rating_a,   -- TODO: per-meter CB current rating
	        9999999.0 AS v_cb_max_rating_kw,  -- TODO: per-meter CB active power rating
	        9999999.0 AS v_kva_user_max,      -- TODO: user-defined kVA ceiling
	        9999999.0 AS v_kvar_user_max,     -- TODO: user-defined kVAr ceiling
	        9999999.0 AS v_kwh_user_max,      -- TODO: user-defined kWh ceiling
	        9999999.0 AS v_kvah_user_max,     -- TODO: user-defined kVAh ceiling
	        9999999.0 AS v_kvarh_user_max     -- TODO: user-defined kVArh ceiling
	),
	base AS (
	    SELECT
	        f.*,
	        c.spike_moderate_pct,
	        c.spike_high_pct,
	        c.consistency_tolerance_pct,
	        c.v_cb_max_rating_a,
	        c.v_cb_max_rating_kw,
	        c.v_kva_user_max,
	        c.v_kvar_user_max,
	        c.v_kwh_user_max,
	        c.v_kvah_user_max,
	        c.v_kvarh_user_max,
	
	        -- Previous-reading values for spike detection (per meter, ordered by time)
	        LAG(f.voltage_neutral_1_v)      OVER w AS prev_vn1,
	        LAG(f.voltage_neutral_2_v)      OVER w AS prev_vn2,
	        LAG(f.voltage_neutral_3_v)      OVER w AS prev_vn3,
	        LAG(f.voltage_neutral_average_v) OVER w AS prev_vna,
	
	        LAG(f.current_phase_1_a)        OVER w AS prev_amp1,
	        LAG(f.current_phase_2_a)        OVER w AS prev_amp2,
	        LAG(f.current_phase_3_a)        OVER w AS prev_amp3,
	        LAG(f.current_average_a)        OVER w AS prev_ampa,
	
	        LAG(f.frequency_hz)             OVER w AS prev_hz,
	
	        LAG(f.power_factor_phase_1)     OVER w AS prev_pf1,
	        LAG(f.power_factor_phase_2)     OVER w AS prev_pf2,
	        LAG(f.power_factor_phase_3)     OVER w AS prev_pf3,
	        LAG(f.power_factor_average)     OVER w AS prev_pfa,
	
	        LAG(f.active_power_phase_1_kw)  OVER w AS prev_kw1,
	        LAG(f.active_power_phase_2_kw)  OVER w AS prev_kw2,
	        LAG(f.active_power_phase_3_kw)  OVER w AS prev_kw3,
	        LAG(f.active_power_total_kw)    OVER w AS prev_tkw,
	
	        LAG(f.apparent_power_phase_1_kva) OVER w AS prev_kva1,
	        LAG(f.apparent_power_phase_2_kva) OVER w AS prev_kva2,
	        LAG(f.apparent_power_phase_3_kva) OVER w AS prev_kva3,
	        LAG(f.apparent_power_total_kva)   OVER w AS prev_tkva,
	
	        LAG(f.reactive_power_phase_1_kvar) OVER w AS prev_kvar1,
	        LAG(f.reactive_power_phase_2_kvar) OVER w AS prev_kvar2,
	        LAG(f.reactive_power_phase_3_kvar) OVER w AS prev_kvar3,
	        LAG(f.reactive_power_total_kvar)   OVER w AS prev_tkvar,
	
	        LAG(f.active_energy_cumulative_kwh)     OVER w AS prev_kwh,
	        LAG(f.apparent_energy_cumulative_kvah)  OVER w AS prev_kvah,
	        LAG(f.reactive_energy_cumulative_kvarh) OVER w AS prev_kvarh
	
	    FROM silver.fact_energy_readings_staging f
	    CROSS JOIN constants c
	    WINDOW w AS (PARTITION BY f.energy_meter_key ORDER BY f.reading_timestamp_utc)
	)
	SELECT
	    b.*,
	
	    -- ============================================================
	    -- VOLTAGE (Line-to-Neutral): Vn1, Vn2, Vn3, Vna
	    -- Hard limit 207-253V | Acceptable 215-245V
	    -- ============================================================
	    (b.voltage_neutral_1_v < 207 OR b.voltage_neutral_1_v > 253) AS vn1_hard_limit_flag,
	    (b.voltage_neutral_1_v < 215 OR b.voltage_neutral_1_v > 245) AS vn1_acceptable_range_flag,
	    (b.prev_vn1 IS NOT NULL AND b.prev_vn1 <> 0
	        AND ABS(b.voltage_neutral_1_v - b.prev_vn1) / ABS(b.prev_vn1) * 100 >= b.spike_high_pct)     AS vn1_high_spike_flag,
	    (b.prev_vn1 IS NOT NULL AND b.prev_vn1 <> 0
	        AND ABS(b.voltage_neutral_1_v - b.prev_vn1) / ABS(b.prev_vn1) * 100 >= b.spike_moderate_pct)  AS vn1_moderate_spike_flag,
	
	    (b.voltage_neutral_2_v < 207 OR b.voltage_neutral_2_v > 253) AS vn2_hard_limit_flag,
	    (b.voltage_neutral_2_v < 215 OR b.voltage_neutral_2_v > 245) AS vn2_acceptable_range_flag,
	    (b.prev_vn2 IS NOT NULL AND b.prev_vn2 <> 0
	        AND ABS(b.voltage_neutral_2_v - b.prev_vn2) / ABS(b.prev_vn2) * 100 >= b.spike_high_pct)     AS vn2_high_spike_flag,
	    (b.prev_vn2 IS NOT NULL AND b.prev_vn2 <> 0
	        AND ABS(b.voltage_neutral_2_v - b.prev_vn2) / ABS(b.prev_vn2) * 100 >= b.spike_moderate_pct)  AS vn2_moderate_spike_flag,
	
	    (b.voltage_neutral_3_v < 207 OR b.voltage_neutral_3_v > 253) AS vn3_hard_limit_flag,
	    (b.voltage_neutral_3_v < 215 OR b.voltage_neutral_3_v > 245) AS vn3_acceptable_range_flag,
	    (b.prev_vn3 IS NOT NULL AND b.prev_vn3 <> 0
	        AND ABS(b.voltage_neutral_3_v - b.prev_vn3) / ABS(b.prev_vn3) * 100 >= b.spike_high_pct)     AS vn3_high_spike_flag,
	    (b.prev_vn3 IS NOT NULL AND b.prev_vn3 <> 0
	        AND ABS(b.voltage_neutral_3_v - b.prev_vn3) / ABS(b.prev_vn3) * 100 >= b.spike_moderate_pct)  AS vn3_moderate_spike_flag,
	
	    -- Phase spread check: max<min within acceptable range (i.e. any phase outside 215-245 while others are within)
	    (GREATEST(b.voltage_neutral_1_v, b.voltage_neutral_2_v, b.voltage_neutral_3_v)
	        - LEAST(b.voltage_neutral_1_v, b.voltage_neutral_2_v, b.voltage_neutral_3_v)) AS vn_phase_spread_v,
	
	    -- ============================================================
	    -- CURRENT: Amp1, Amp2, Amp3, Ampa
	    -- Hard limit: 0 to CB max rating
	    -- ============================================================
	    (b.current_phase_1_a < 0 OR b.current_phase_1_a > b.v_cb_max_rating_a) AS amp1_hard_limit_flag,
	    (b.prev_amp1 IS NOT NULL AND b.prev_amp1 <> 0
	        AND ABS(b.current_phase_1_a - b.prev_amp1) / ABS(b.prev_amp1) * 100 >= b.spike_high_pct)     AS amp1_high_spike_flag,
	    (b.prev_amp1 IS NOT NULL AND b.prev_amp1 <> 0
	        AND ABS(b.current_phase_1_a - b.prev_amp1) / ABS(b.prev_amp1) * 100 >= b.spike_moderate_pct)  AS amp1_moderate_spike_flag,
	
	    (b.current_phase_2_a < 0 OR b.current_phase_2_a > b.v_cb_max_rating_a) AS amp2_hard_limit_flag,
	    (b.prev_amp2 IS NOT NULL AND b.prev_amp2 <> 0
	        AND ABS(b.current_phase_2_a - b.prev_amp2) / ABS(b.prev_amp2) * 100 >= b.spike_high_pct)     AS amp2_high_spike_flag,
	    (b.prev_amp2 IS NOT NULL AND b.prev_amp2 <> 0
	        AND ABS(b.current_phase_2_a - b.prev_amp2) / ABS(b.prev_amp2) * 100 >= b.spike_moderate_pct)  AS amp2_moderate_spike_flag,
	
	    (b.current_phase_3_a < 0 OR b.current_phase_3_a > b.v_cb_max_rating_a) AS amp3_hard_limit_flag,
	    (b.prev_amp3 IS NOT NULL AND b.prev_amp3 <> 0
	        AND ABS(b.current_phase_3_a - b.prev_amp3) / ABS(b.prev_amp3) * 100 >= b.spike_high_pct)     AS amp3_high_spike_flag,
	    (b.prev_amp3 IS NOT NULL AND b.prev_amp3 <> 0
	        AND ABS(b.current_phase_3_a - b.prev_amp3) / ABS(b.prev_amp3) * 100 >= b.spike_moderate_pct)  AS amp3_moderate_spike_flag,
	
	    (GREATEST(b.current_phase_1_a, b.current_phase_2_a, b.current_phase_3_a)
	        - LEAST(b.current_phase_1_a, b.current_phase_2_a, b.current_phase_3_a)) AS current_phase_spread_a,
	
	    -- ============================================================
	    -- FREQUENCY: Hz
	    -- Hard limit 59.3-60.5 | Acceptable 59-61
	    -- ============================================================
	    (b.frequency_hz < 59.3 OR b.frequency_hz > 60.5) AS hz_hard_limit_flag,
	    (b.frequency_hz < 59.0 OR b.frequency_hz > 61.0) AS hz_acceptable_range_flag,
	    (b.prev_hz IS NOT NULL AND b.prev_hz <> 0
	        AND ABS(b.frequency_hz - b.prev_hz) / ABS(b.prev_hz) * 100 >= b.spike_high_pct)     AS hz_high_spike_flag,
	    (b.prev_hz IS NOT NULL AND b.prev_hz <> 0
	        AND ABS(b.frequency_hz - b.prev_hz) / ABS(b.prev_hz) * 100 >= b.spike_moderate_pct)  AS hz_moderate_spike_flag,
	
	    -- ============================================================
	    -- POWER FACTOR: PF1, PF2, PF3, PFa
	    -- Valid physical range -1 to 1 | Hard limit 0.6-1.0 | Acceptable 0.8-1.0
	    -- ============================================================
	    (b.power_factor_phase_1 < -1 OR b.power_factor_phase_1 > 1) AS pf1_invalid_range_flag,
	    (b.power_factor_phase_1 < 0.6)  AS pf1_below_hard_limit_flag,
	    (b.power_factor_phase_1 < 0.8)  AS pf1_below_acceptable_flag,
	    (b.prev_pf1 IS NOT NULL AND b.prev_pf1 <> 0
	        AND ABS(b.power_factor_phase_1 - b.prev_pf1) / ABS(b.prev_pf1) * 100 >= b.spike_high_pct)    AS pf1_high_spike_flag,
	
	    (b.power_factor_phase_2 < -1 OR b.power_factor_phase_2 > 1) AS pf2_invalid_range_flag,
	    (b.power_factor_phase_2 < 0.6)  AS pf2_below_hard_limit_flag,
	    (b.power_factor_phase_2 < 0.8)  AS pf2_below_acceptable_flag,
	    (b.prev_pf2 IS NOT NULL AND b.prev_pf2 <> 0
	        AND ABS(b.power_factor_phase_2 - b.prev_pf2) / ABS(b.prev_pf2) * 100 >= b.spike_high_pct)    AS pf2_high_spike_flag,
	
	    (b.power_factor_phase_3 < -1 OR b.power_factor_phase_3 > 1) AS pf3_invalid_range_flag,
	    (b.power_factor_phase_3 < 0.6)  AS pf3_below_hard_limit_flag,
	    (b.power_factor_phase_3 < 0.8)  AS pf3_below_acceptable_flag,
	    (b.prev_pf3 IS NOT NULL AND b.prev_pf3 <> 0
	        AND ABS(b.power_factor_phase_3 - b.prev_pf3) / ABS(b.prev_pf3) * 100 >= b.spike_high_pct)    AS pf3_high_spike_flag,
	
	    -- ============================================================
	    -- ACTIVE POWER: kW1, kW2, kW3, TkW
	    -- Hard limit: 0 to CB max rating | TkW should ~= sum(kW1,kW2,kW3) +-5%
	    -- ============================================================
	    (b.active_power_phase_1_kw < 0 OR b.active_power_phase_1_kw > b.v_cb_max_rating_kw) AS kw1_hard_limit_flag,
	    (b.prev_kw1 IS NOT NULL AND b.prev_kw1 <> 0
	        AND ABS(b.active_power_phase_1_kw - b.prev_kw1) / ABS(b.prev_kw1) * 100 >= b.spike_high_pct) AS kw1_high_spike_flag,
	
	    (b.active_power_phase_2_kw < 0 OR b.active_power_phase_2_kw > b.v_cb_max_rating_kw) AS kw2_hard_limit_flag,
	    (b.prev_kw2 IS NOT NULL AND b.prev_kw2 <> 0
	        AND ABS(b.active_power_phase_2_kw - b.prev_kw2) / ABS(b.prev_kw2) * 100 >= b.spike_high_pct) AS kw2_high_spike_flag,
	
	    (b.active_power_phase_3_kw < 0 OR b.active_power_phase_3_kw > b.v_cb_max_rating_kw) AS kw3_hard_limit_flag,
	    (b.prev_kw3 IS NOT NULL AND b.prev_kw3 <> 0
	        AND ABS(b.active_power_phase_3_kw - b.prev_kw3) / ABS(b.prev_kw3) * 100 >= b.spike_high_pct) AS kw3_high_spike_flag,
	
	    (b.active_power_total_kw < 0) AS tkw_negative_flag,
	    (
	        num_nonnulls(b.active_power_phase_1_kw, b.active_power_phase_2_kw, b.active_power_phase_3_kw, b.active_power_total_kw) = 4
	        AND ABS(
	            b.active_power_total_kw
	            - (b.active_power_phase_1_kw + b.active_power_phase_2_kw + b.active_power_phase_3_kw)
	        ) / NULLIF(ABS(b.active_power_phase_1_kw + b.active_power_phase_2_kw + b.active_power_phase_3_kw), 0) * 100
	        > b.consistency_tolerance_pct
	    ) AS tkw_sum_consistency_flag,
	
	    -- ============================================================
	    -- APPARENT POWER: kVA1, kVA2, kVA3, TkVA
	    -- Hard limit: 0 to user-defined max | TkVA should ~= sum +-5%
	    -- ============================================================
	    (b.apparent_power_phase_1_kva < 0 OR b.apparent_power_phase_1_kva > b.v_kva_user_max) AS kva1_hard_limit_flag,
	    (b.apparent_power_phase_2_kva < 0 OR b.apparent_power_phase_2_kva > b.v_kva_user_max) AS kva2_hard_limit_flag,
	    (b.apparent_power_phase_3_kva < 0 OR b.apparent_power_phase_3_kva > b.v_kva_user_max) AS kva3_hard_limit_flag,
	    (b.apparent_power_total_kva < 0) AS tkva_negative_flag,
	    (
	        num_nonnulls(b.apparent_power_phase_1_kva, b.apparent_power_phase_2_kva, b.apparent_power_phase_3_kva, b.apparent_power_total_kva) = 4
	        AND ABS(
	            b.apparent_power_total_kva
	            - (b.apparent_power_phase_1_kva + b.apparent_power_phase_2_kva + b.apparent_power_phase_3_kva)
	        ) / NULLIF(ABS(b.apparent_power_phase_1_kva + b.apparent_power_phase_2_kva + b.apparent_power_phase_3_kva), 0) * 100
	        > b.consistency_tolerance_pct
	    ) AS tkva_sum_consistency_flag,
	
	    -- ============================================================
	    -- REACTIVE POWER: kVAr1, kVAr2, kVAr3, TkVAr
	    -- Any value allowed (leading/lagging) | TkVAr should ~= sum +-5%
	    -- ============================================================
	    (
	        num_nonnulls(b.reactive_power_phase_1_kvar, b.reactive_power_phase_2_kvar, b.reactive_power_phase_3_kvar, b.reactive_power_total_kvar) = 4
	        AND ABS(
	            b.reactive_power_total_kvar
	            - (b.reactive_power_phase_1_kvar + b.reactive_power_phase_2_kvar + b.reactive_power_phase_3_kvar)
	        ) / NULLIF(ABS(b.reactive_power_phase_1_kvar + b.reactive_power_phase_2_kvar + b.reactive_power_phase_3_kvar), 0) * 100
	        > b.consistency_tolerance_pct
	    ) AS tkvar_sum_consistency_flag,
	
	    -- ============================================================
	    -- ACCUMULATED ENERGY: kWh, kVAh, kVArh
	    -- Cannot decrement | Hard limit: 0 to user-defined max
	    -- ============================================================
	    (b.prev_kwh IS NOT NULL AND b.active_energy_cumulative_kwh < b.prev_kwh) AS kwh_decrement_flag,
	    (b.active_energy_cumulative_kwh < 0 OR b.active_energy_cumulative_kwh > b.v_kwh_user_max) AS kwh_hard_limit_flag,
	
	    (b.prev_kvah IS NOT NULL AND b.apparent_energy_cumulative_kvah < b.prev_kvah) AS kvah_decrement_flag,
	    (b.apparent_energy_cumulative_kvah < 0 OR b.apparent_energy_cumulative_kvah > b.v_kvah_user_max) AS kvah_hard_limit_flag,
	
	    (b.prev_kvarh IS NOT NULL AND b.reactive_energy_cumulative_kvarh < b.prev_kvarh) AS kvarh_decrement_flag,
	    (b.reactive_energy_cumulative_kvarh < 0 OR b.reactive_energy_cumulative_kvarh > b.v_kvarh_user_max) AS kvarh_hard_limit_flag
	
	FROM base b;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
CREATE OR REPLACE VIEW silver.fact_energy_readings_flagged AS
	WITH constants AS (
	    SELECT
	        30.0  AS spike_moderate_pct,      -- >=30% change vs previous reading
	        50.0  AS spike_high_pct,          -- >=50% change vs previous reading
	        5.0   AS consistency_tolerance_pct, -- total vs sum-of-phases tolerance
	        -- --- PLACEHOLDERS: replace with real values or a lookup join ---
	        9999999.0 AS v_cb_max_rating_a,   -- TODO: per-meter CB current rating
	        9999999.0 AS v_cb_max_rating_kw,  -- TODO: per-meter CB active power rating
	        9999999.0 AS v_kva_user_max,      -- TODO: user-defined kVA ceiling
	        9999999.0 AS v_kvar_user_max,     -- TODO: user-defined kVAr ceiling
	        9999999.0 AS v_kwh_user_max,      -- TODO: user-defined kWh ceiling
	        9999999.0 AS v_kvah_user_max,     -- TODO: user-defined kVAh ceiling
	        9999999.0 AS v_kvarh_user_max     -- TODO: user-defined kVArh ceiling
	),
	base AS (
	    SELECT
	        f.*,
	        c.spike_moderate_pct,
	        c.spike_high_pct,
	        c.consistency_tolerance_pct,
	        c.v_cb_max_rating_a,
	        c.v_cb_max_rating_kw,
	        c.v_kva_user_max,
	        c.v_kvar_user_max,
	        c.v_kwh_user_max,
	        c.v_kvah_user_max,
	        c.v_kvarh_user_max,
	 
	        -- Previous-reading values for spike detection (per meter, ordered by time)
	        LAG(f.voltage_neutral_1_v)      OVER w AS prev_vn1,
	        LAG(f.voltage_neutral_2_v)      OVER w AS prev_vn2,
	        LAG(f.voltage_neutral_3_v)      OVER w AS prev_vn3,
	        LAG(f.voltage_neutral_average_v) OVER w AS prev_vna,
	 
	        LAG(f.current_phase_1_a)        OVER w AS prev_amp1,
	        LAG(f.current_phase_2_a)        OVER w AS prev_amp2,
	        LAG(f.current_phase_3_a)        OVER w AS prev_amp3,
	        LAG(f.current_average_a)        OVER w AS prev_ampa,
	 
	        LAG(f.frequency_hz)             OVER w AS prev_hz,
	 
	        LAG(f.power_factor_phase_1)     OVER w AS prev_pf1,
	        LAG(f.power_factor_phase_2)     OVER w AS prev_pf2,
	        LAG(f.power_factor_phase_3)     OVER w AS prev_pf3,
	        LAG(f.power_factor_average)     OVER w AS prev_pfa,
	 
	        LAG(f.active_power_phase_1_kw)  OVER w AS prev_kw1,
	        LAG(f.active_power_phase_2_kw)  OVER w AS prev_kw2,
	        LAG(f.active_power_phase_3_kw)  OVER w AS prev_kw3,
	        LAG(f.active_power_total_kw)    OVER w AS prev_tkw,
	 
	        LAG(f.apparent_power_phase_1_kva) OVER w AS prev_kva1,
	        LAG(f.apparent_power_phase_2_kva) OVER w AS prev_kva2,
	        LAG(f.apparent_power_phase_3_kva) OVER w AS prev_kva3,
	        LAG(f.apparent_power_total_kva)   OVER w AS prev_tkva,
	 
	        LAG(f.reactive_power_phase_1_kvar) OVER w AS prev_kvar1,
	        LAG(f.reactive_power_phase_2_kvar) OVER w AS prev_kvar2,
	        LAG(f.reactive_power_phase_3_kvar) OVER w AS prev_kvar3,
	        LAG(f.reactive_power_total_kvar)   OVER w AS prev_tkvar,
	 
	        LAG(f.active_energy_cumulative_kwh)     OVER w AS prev_kwh,
	        LAG(f.apparent_energy_cumulative_kvah)  OVER w AS prev_kvah,
	        LAG(f.reactive_energy_cumulative_kvarh) OVER w AS prev_kvarh
	 
	    FROM silver.fact_energy_readings_staging f
	    CROSS JOIN constants c
	    WINDOW w AS (PARTITION BY f.energy_meter_key ORDER BY f.reading_timestamp_utc)
	)
	SELECT
	    b.*,
	 
	    -- ============================================================
	    -- VOLTAGE (Line-to-Neutral): Vn1, Vn2, Vn3, Vna
	    -- Hard limit 207-253V | Acceptable 215-245V
	    -- ============================================================
	    (b.voltage_neutral_1_v < 207 OR b.voltage_neutral_1_v > 253) AS vn1_hard_limit_flag,
	    (b.voltage_neutral_1_v < 215 OR b.voltage_neutral_1_v > 245) AS vn1_acceptable_range_flag,
	    (b.prev_vn1 IS NOT NULL AND b.prev_vn1 <> 0
	        AND ABS(b.voltage_neutral_1_v - b.prev_vn1) / ABS(b.prev_vn1) * 100 >= b.spike_high_pct)     AS vn1_high_spike_flag,
	    (b.prev_vn1 IS NOT NULL AND b.prev_vn1 <> 0
	        AND ABS(b.voltage_neutral_1_v - b.prev_vn1) / ABS(b.prev_vn1) * 100 >= b.spike_moderate_pct)  AS vn1_moderate_spike_flag,
	 
	    (b.voltage_neutral_2_v < 207 OR b.voltage_neutral_2_v > 253) AS vn2_hard_limit_flag,
	    (b.voltage_neutral_2_v < 215 OR b.voltage_neutral_2_v > 245) AS vn2_acceptable_range_flag,
	    (b.prev_vn2 IS NOT NULL AND b.prev_vn2 <> 0
	        AND ABS(b.voltage_neutral_2_v - b.prev_vn2) / ABS(b.prev_vn2) * 100 >= b.spike_high_pct)     AS vn2_high_spike_flag,
	    (b.prev_vn2 IS NOT NULL AND b.prev_vn2 <> 0
	        AND ABS(b.voltage_neutral_2_v - b.prev_vn2) / ABS(b.prev_vn2) * 100 >= b.spike_moderate_pct)  AS vn2_moderate_spike_flag,
	 
	    (b.voltage_neutral_3_v < 207 OR b.voltage_neutral_3_v > 253) AS vn3_hard_limit_flag,
	    (b.voltage_neutral_3_v < 215 OR b.voltage_neutral_3_v > 245) AS vn3_acceptable_range_flag,
	    (b.prev_vn3 IS NOT NULL AND b.prev_vn3 <> 0
	        AND ABS(b.voltage_neutral_3_v - b.prev_vn3) / ABS(b.prev_vn3) * 100 >= b.spike_high_pct)     AS vn3_high_spike_flag,
	    (b.prev_vn3 IS NOT NULL AND b.prev_vn3 <> 0
	        AND ABS(b.voltage_neutral_3_v - b.prev_vn3) / ABS(b.prev_vn3) * 100 >= b.spike_moderate_pct)  AS vn3_moderate_spike_flag,
	 
	    -- Phase spread check: max<min within acceptable range (i.e. any phase outside 215-245 while others are within)
	    (GREATEST(b.voltage_neutral_1_v, b.voltage_neutral_2_v, b.voltage_neutral_3_v)
	        - LEAST(b.voltage_neutral_1_v, b.voltage_neutral_2_v, b.voltage_neutral_3_v)) AS vn_phase_spread_v,
	 
	    -- ============================================================
	    -- CURRENT: Amp1, Amp2, Amp3, Ampa
	    -- Hard limit: 0 to CB max rating
	    -- ============================================================
	    (b.current_phase_1_a < 0 OR b.current_phase_1_a > b.v_cb_max_rating_a) AS amp1_hard_limit_flag,
	    (b.prev_amp1 IS NOT NULL AND b.prev_amp1 <> 0
	        AND ABS(b.current_phase_1_a - b.prev_amp1) / ABS(b.prev_amp1) * 100 >= b.spike_high_pct)     AS amp1_high_spike_flag,
	    (b.prev_amp1 IS NOT NULL AND b.prev_amp1 <> 0
	        AND ABS(b.current_phase_1_a - b.prev_amp1) / ABS(b.prev_amp1) * 100 >= b.spike_moderate_pct)  AS amp1_moderate_spike_flag,
	 
	    (b.current_phase_2_a < 0 OR b.current_phase_2_a > b.v_cb_max_rating_a) AS amp2_hard_limit_flag,
	    (b.prev_amp2 IS NOT NULL AND b.prev_amp2 <> 0
	        AND ABS(b.current_phase_2_a - b.prev_amp2) / ABS(b.prev_amp2) * 100 >= b.spike_high_pct)     AS amp2_high_spike_flag,
	    (b.prev_amp2 IS NOT NULL AND b.prev_amp2 <> 0
	        AND ABS(b.current_phase_2_a - b.prev_amp2) / ABS(b.prev_amp2) * 100 >= b.spike_moderate_pct)  AS amp2_moderate_spike_flag,
	 
	    (b.current_phase_3_a < 0 OR b.current_phase_3_a > b.v_cb_max_rating_a) AS amp3_hard_limit_flag,
	    (b.prev_amp3 IS NOT NULL AND b.prev_amp3 <> 0
	        AND ABS(b.current_phase_3_a - b.prev_amp3) / ABS(b.prev_amp3) * 100 >= b.spike_high_pct)     AS amp3_high_spike_flag,
	    (b.prev_amp3 IS NOT NULL AND b.prev_amp3 <> 0
	        AND ABS(b.current_phase_3_a - b.prev_amp3) / ABS(b.prev_amp3) * 100 >= b.spike_moderate_pct)  AS amp3_moderate_spike_flag,
	 
	    (GREATEST(b.current_phase_1_a, b.current_phase_2_a, b.current_phase_3_a)
	        - LEAST(b.current_phase_1_a, b.current_phase_2_a, b.current_phase_3_a)) AS current_phase_spread_a,
	 
	    -- ============================================================
	    -- FREQUENCY: Hz
	    -- Hard limit 59.3-60.5 | Acceptable 59-61
	    -- ============================================================
	    (b.frequency_hz < 59.3 OR b.frequency_hz > 60.5) AS hz_hard_limit_flag,
	    (b.frequency_hz < 59.0 OR b.frequency_hz > 61.0) AS hz_acceptable_range_flag,
	    (b.prev_hz IS NOT NULL AND b.prev_hz <> 0
	        AND ABS(b.frequency_hz - b.prev_hz) / ABS(b.prev_hz) * 100 >= b.spike_high_pct)     AS hz_high_spike_flag,
	    (b.prev_hz IS NOT NULL AND b.prev_hz <> 0
	        AND ABS(b.frequency_hz - b.prev_hz) / ABS(b.prev_hz) * 100 >= b.spike_moderate_pct)  AS hz_moderate_spike_flag,
	 
	    -- ============================================================
	    -- POWER FACTOR: PF1, PF2, PF3, PFa
	    -- Valid physical range -1 to 1 | Hard limit 0.6-1.0 | Acceptable 0.8-1.0
	    -- ============================================================
	    (b.power_factor_phase_1 < -1 OR b.power_factor_phase_1 > 1) AS pf1_invalid_range_flag,
	    (b.power_factor_phase_1 < 0.6)  AS pf1_below_hard_limit_flag,
	    (b.power_factor_phase_1 < 0.8)  AS pf1_below_acceptable_flag,
	    (b.prev_pf1 IS NOT NULL AND b.prev_pf1 <> 0
	        AND ABS(b.power_factor_phase_1 - b.prev_pf1) / ABS(b.prev_pf1) * 100 >= b.spike_high_pct)    AS pf1_high_spike_flag,
	 
	    (b.power_factor_phase_2 < -1 OR b.power_factor_phase_2 > 1) AS pf2_invalid_range_flag,
	    (b.power_factor_phase_2 < 0.6)  AS pf2_below_hard_limit_flag,
	    (b.power_factor_phase_2 < 0.8)  AS pf2_below_acceptable_flag,
	    (b.prev_pf2 IS NOT NULL AND b.prev_pf2 <> 0
	        AND ABS(b.power_factor_phase_2 - b.prev_pf2) / ABS(b.prev_pf2) * 100 >= b.spike_high_pct)    AS pf2_high_spike_flag,
	 
	    (b.power_factor_phase_3 < -1 OR b.power_factor_phase_3 > 1) AS pf3_invalid_range_flag,
	    (b.power_factor_phase_3 < 0.6)  AS pf3_below_hard_limit_flag,
	    (b.power_factor_phase_3 < 0.8)  AS pf3_below_acceptable_flag,
	    (b.prev_pf3 IS NOT NULL AND b.prev_pf3 <> 0
	        AND ABS(b.power_factor_phase_3 - b.prev_pf3) / ABS(b.prev_pf3) * 100 >= b.spike_high_pct)    AS pf3_high_spike_flag,
	 
	    -- ============================================================
	    -- ACTIVE POWER: kW1, kW2, kW3, TkW
	    -- Hard limit: 0 to CB max rating | TkW should ~= sum(kW1,kW2,kW3) +-5%
	    -- ============================================================
	    (b.active_power_phase_1_kw < 0 OR b.active_power_phase_1_kw > b.v_cb_max_rating_kw) AS kw1_hard_limit_flag,
	    (b.prev_kw1 IS NOT NULL AND b.prev_kw1 <> 0
	        AND ABS(b.active_power_phase_1_kw - b.prev_kw1) / ABS(b.prev_kw1) * 100 >= b.spike_high_pct) AS kw1_high_spike_flag,
	 
	    (b.active_power_phase_2_kw < 0 OR b.active_power_phase_2_kw > b.v_cb_max_rating_kw) AS kw2_hard_limit_flag,
	    (b.prev_kw2 IS NOT NULL AND b.prev_kw2 <> 0
	        AND ABS(b.active_power_phase_2_kw - b.prev_kw2) / ABS(b.prev_kw2) * 100 >= b.spike_high_pct) AS kw2_high_spike_flag,
	 
	    (b.active_power_phase_3_kw < 0 OR b.active_power_phase_3_kw > b.v_cb_max_rating_kw) AS kw3_hard_limit_flag,
	    (b.prev_kw3 IS NOT NULL AND b.prev_kw3 <> 0
	        AND ABS(b.active_power_phase_3_kw - b.prev_kw3) / ABS(b.prev_kw3) * 100 >= b.spike_high_pct) AS kw3_high_spike_flag,
	 
	    (b.active_power_total_kw < 0) AS tkw_negative_flag,
	    (
	        num_nonnulls(b.active_power_phase_1_kw, b.active_power_phase_2_kw, b.active_power_phase_3_kw, b.active_power_total_kw) = 4
	        AND ABS(
	            b.active_power_total_kw
	            - (b.active_power_phase_1_kw + b.active_power_phase_2_kw + b.active_power_phase_3_kw)
	        ) / NULLIF(ABS(b.active_power_phase_1_kw + b.active_power_phase_2_kw + b.active_power_phase_3_kw), 0) * 100
	        > b.consistency_tolerance_pct
	    ) AS tkw_sum_consistency_flag,
	 
	    -- ============================================================
	    -- APPARENT POWER: kVA1, kVA2, kVA3, TkVA
	    -- Hard limit: 0 to user-defined max | TkVA should ~= sum +-5%
	    -- ============================================================
	    (b.apparent_power_phase_1_kva < 0 OR b.apparent_power_phase_1_kva > b.v_kva_user_max) AS kva1_hard_limit_flag,
	    (b.apparent_power_phase_2_kva < 0 OR b.apparent_power_phase_2_kva > b.v_kva_user_max) AS kva2_hard_limit_flag,
	    (b.apparent_power_phase_3_kva < 0 OR b.apparent_power_phase_3_kva > b.v_kva_user_max) AS kva3_hard_limit_flag,
	    (b.apparent_power_total_kva < 0) AS tkva_negative_flag,
	    (
	        num_nonnulls(b.apparent_power_phase_1_kva, b.apparent_power_phase_2_kva, b.apparent_power_phase_3_kva, b.apparent_power_total_kva) = 4
	        AND ABS(
	            b.apparent_power_total_kva
	            - (b.apparent_power_phase_1_kva + b.apparent_power_phase_2_kva + b.apparent_power_phase_3_kva)
	        ) / NULLIF(ABS(b.apparent_power_phase_1_kva + b.apparent_power_phase_2_kva + b.apparent_power_phase_3_kva), 0) * 100
	        > b.consistency_tolerance_pct
	    ) AS tkva_sum_consistency_flag,
	 
	    -- ============================================================
	    -- REACTIVE POWER: kVAr1, kVAr2, kVAr3, TkVAr
	    -- Any value allowed (leading/lagging) | TkVAr should ~= sum +-5%
	    -- ============================================================
	    (
	        num_nonnulls(b.reactive_power_phase_1_kvar, b.reactive_power_phase_2_kvar, b.reactive_power_phase_3_kvar, b.reactive_power_total_kvar) = 4
	        AND ABS(
	            b.reactive_power_total_kvar
	            - (b.reactive_power_phase_1_kvar + b.reactive_power_phase_2_kvar + b.reactive_power_phase_3_kvar)
	        ) / NULLIF(ABS(b.reactive_power_phase_1_kvar + b.reactive_power_phase_2_kvar + b.reactive_power_phase_3_kvar), 0) * 100
	        > b.consistency_tolerance_pct
	    ) AS tkvar_sum_consistency_flag,
	 
	    -- ============================================================
	    -- ACCUMULATED ENERGY: kWh, kVAh, kVArh
	    -- Cannot decrement | Hard limit: 0 to user-defined max
	    -- ============================================================
	    (b.prev_kwh IS NOT NULL AND b.active_energy_cumulative_kwh < b.prev_kwh) AS kwh_decrement_flag,
	    (b.active_energy_cumulative_kwh < 0 OR b.active_energy_cumulative_kwh > b.v_kwh_user_max) AS kwh_hard_limit_flag,
	 
	    (b.prev_kvah IS NOT NULL AND b.apparent_energy_cumulative_kvah < b.prev_kvah) AS kvah_decrement_flag,
	    (b.apparent_energy_cumulative_kvah < 0 OR b.apparent_energy_cumulative_kvah > b.v_kvah_user_max) AS kvah_hard_limit_flag,
	 
	    (b.prev_kvarh IS NOT NULL AND b.reactive_energy_cumulative_kvarh < b.prev_kvarh) AS kvarh_decrement_flag,
	    (b.reactive_energy_cumulative_kvarh < 0 OR b.reactive_energy_cumulative_kvarh > b.v_kvarh_user_max) AS kvarh_hard_limit_flag
	 
	FROM base b;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    energy_meter_key,
	    reading_timestamp_utc,
	
	    voltage_neutral_1_v,
	    vn1_hard_limit_flag,
	    vn1_acceptable_range_flag,
	    vn1_high_spike_flag,
	
	    current_phase_1_a,
	    amp1_hard_limit_flag,
	
	    active_power_phase_1_kw,
	    active_power_phase_2_kw,
	    active_power_phase_3_kw,
	    active_power_total_kw,
	    tkw_sum_consistency_flag,
	
	    active_energy_cumulative_kwh,
	    kwh_decrement_flag
	
	FROM silver.fact_energy_readings_flagged
	
	WHERE energy_meter_key =
	      'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	
	  AND reading_timestamp_utc >=
	      TIMESTAMP '2025-07-01 00:00:00'
	
	  AND reading_timestamp_utc <
	      TIMESTAMP '2025-07-02 00:00:00'
	
	ORDER BY reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
WITH classified_results AS (
	
	    -- Paste the previous query here,
	    -- but remove its final ORDER BY
	
	)
	
	SELECT
	    status,
	    COUNT(*) AS reading_count
	FROM classified_results
	GROUP BY status
	ORDER BY CASE status
	    WHEN 'Invalid' THEN 1
	    WHEN 'Critical' THEN 2
	    WHEN 'Problematic' THEN 3
	    WHEN 'Anomaly' THEN 4
	    WHEN 'Review Required' THEN 5
	    WHEN 'Acceptable' THEN 6
	    ELSE 7
	END;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
WITH classified_results AS (
	
	    -- Paste the previous query here,
	    -- but remove its final ORDER BY
	
	
	
	SELECT
	    status,
	    COUNT(*) AS reading_count
	FROM classified_results
	GROUP BY status
	ORDER BY CASE status
	    WHEN 'Invalid' THEN 1
	    WHEN 'Critical' THEN 2
	    WHEN 'Problematic' THEN 3
	    WHEN 'Anomaly' THEN 4
	    WHEN 'Review Required' THEN 5
	    WHEN 'Acceptable' THEN 6
	    ELSE 7
	END;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    status,
	    COUNT(*) AS reading_count
	FROM classified_results
	GROUP BY status
	ORDER BY CASE status
	    WHEN 'Invalid' THEN 1
	    WHEN 'Critical' THEN 2
	    WHEN 'Problematic' THEN 3
	    WHEN 'Anomaly' THEN 4
	    WHEN 'Review Required' THEN 5
	    WHEN 'Acceptable' THEN 6
	    ELSE 7
	END;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
CREATE OR REPLACE FUNCTION silver.status_rank(
	    p_status text
	)
	RETURNS integer
	LANGUAGE sql
	IMMUTABLE
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
	
	
	-- ============================================================
	-- 2. Return the worst status from multiple checks
	--
	-- Example:
	-- silver.worst_status('Acceptable', 'Problematic')
	-- returns Problematic
	-- ============================================================
	
	CREATE OR REPLACE FUNCTION silver.worst_status(
	    VARIADIC p_statuses text[]
	)
	RETURNS text
	LANGUAGE sql
	IMMUTABLE
	AS $$
	    SELECT status_value
	    FROM unnest(p_statuses) AS status_value
	    WHERE status_value IS NOT NULL
	    ORDER BY silver.status_rank(status_value) DESC
	    LIMIT 1;
	$$;
	
	
	-- ============================================================
	-- 3. Standard scalar classification
	--
	-- Used for:
	-- Voltage
	-- Current
	-- Frequency
	-- Active Power
	-- Apparent Power
	-- Reactive Power
	--
	-- Logic:
	-- Invalid physical range
	-- Critical hard limit
	-- Anomaly >= high spike threshold
	-- Review Required outside acceptable range
	-- Acceptable otherwise
	-- ============================================================
	
	CREATE OR REPLACE FUNCTION silver.classify_standard(
	    p_value           double precision,
	    p_prev_value      double precision,
	    p_hard_min        double precision,
	    p_hard_max        double precision,
	    p_acceptable_min  double precision,
	    p_acceptable_max  double precision,
	    p_invalid_min     double precision DEFAULT NULL,
	    p_invalid_max     double precision DEFAULT NULL,
	    p_spike_pct       double precision DEFAULT 50.0
	)
	RETURNS text
	LANGUAGE sql
	IMMUTABLE
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
	
	
	-- ============================================================
	-- 4. Power Factor
	--
	-- Invalid: outside physical range -1 through 1
	-- Problematic: below 0.6
	-- Review Required: 0.6 through below 0.8
	-- Anomaly: high spike, unless already Problematic
	-- Acceptable: 0.8 through 1.0
	-- ============================================================
	
	CREATE OR REPLACE FUNCTION silver.classify_power_factor(
	    p_value      double precision,
	    p_prev_value double precision,
	    p_spike_pct  double precision DEFAULT 50.0
	)
	RETURNS text
	LANGUAGE sql
	IMMUTABLE
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
	
	
	-- ============================================================
	-- 5. Accumulated Energy
	--
	-- Used for:
	-- kWh
	-- kVAh
	-- kVArh
	--
	-- Invalid: negative
	-- Critical: above user-defined maximum
	-- Anomaly: cumulative counter decremented
	-- ============================================================
	
	CREATE OR REPLACE FUNCTION silver.classify_energy(
	    p_value      double precision,
	    p_prev_value double precision,
	    p_user_max   double precision DEFAULT NULL
	)
	RETURNS text
	LANGUAGE sql
	IMMUTABLE
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
	
	
	-- ============================================================
	-- 6. Total versus sum-of-phases consistency
	--
	-- Used for:
	-- TkW   versus kW1 + kW2 + kW3
	-- TkVA  versus kVA1 + kVA2 + kVA3
	-- TkVAr versus kVAr1 + kVAr2 + kVAr3
	--
	-- Outside +/-5% = Invalid
	-- ============================================================
	
	CREATE OR REPLACE FUNCTION silver.classify_consistency(
	    p_total         double precision,
	    p_phase_sum     double precision,
	    p_tolerance_pct double precision DEFAULT 5.0
	)
	RETURNS text
	LANGUAGE sql
	IMMUTABLE
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
	
	
	-- ============================================================
	-- 7. Phase imbalance classification
	--
	-- p_evaluation_status must be:
	-- WITHIN_ACCEPTABLE
	-- OUTSIDE_ACCEPTABLE
	-- EVALUATED (backward-compatible mode)
	--
	-- Problematic:
	-- imbalance exists while all phases are acceptable
	--
	-- Critical:
	-- imbalance exists and one or more phases are outside
	-- the acceptable range
	--
	-- Default phase-spread threshold is 5%.
	-- This remains configurable because the sheet does not give
	-- a separate exact phase-imbalance percentage.
	-- ============================================================
	
	CREATE OR REPLACE FUNCTION silver.classify_phase_imbalance(
	    p_imbalance_pct              double precision,
	    p_evaluation_status          text,
	    p_problematic_threshold_pct  double precision DEFAULT 5.0,
	    p_critical_threshold_pct     double precision DEFAULT 5.0
	)
	RETURNS text
	LANGUAGE sql
	IMMUTABLE
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

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT *
	FROM silver.agg_energy_4h
	WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND bucket_start_utc >= '2025-07-01' AND bucket_start_utc < '2025-07-02'
	ORDER BY bucket_start_utc;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT bucket_start_utc, kwh_consumption, reading_count
	FROM silver.agg_energy_1d
	WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND bucket_start_utc = '2025-07-01'::date;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
-- ============================================================
	-- Add status columns to silver.agg_energy_4h
	--
	-- Rolled up from silver.agg_energy_1h using worst_status() --
	-- a 4-hour block inherits the WORST status any of its 4
	-- component hours had, per metric.
	-- ============================================================
	
	ALTER TABLE silver.agg_energy_4h
	    ADD COLUMN IF NOT EXISTS status_vn1  text,
	    ADD COLUMN IF NOT EXISTS status_vn2  text,
	    ADD COLUMN IF NOT EXISTS status_vn3  text,
	    ADD COLUMN IF NOT EXISTS status_v1   text,
	    ADD COLUMN IF NOT EXISTS status_v2   text,
	    ADD COLUMN IF NOT EXISTS status_v3   text,
	    ADD COLUMN IF NOT EXISTS status_amp1 text,
	    ADD COLUMN IF NOT EXISTS status_amp2 text,
	    ADD COLUMN IF NOT EXISTS status_amp3 text,
	    ADD COLUMN IF NOT EXISTS status_hz   text,
	    ADD COLUMN IF NOT EXISTS status_pf1  text,
	    ADD COLUMN IF NOT EXISTS status_pf2  text,
	    ADD COLUMN IF NOT EXISTS status_pf3  text,
	    ADD COLUMN IF NOT EXISTS status_kw1  text,
	    ADD COLUMN IF NOT EXISTS status_kw2  text,
	    ADD COLUMN IF NOT EXISTS status_kw3  text,
	    ADD COLUMN IF NOT EXISTS status_tkw  text,
	    ADD COLUMN IF NOT EXISTS status_kva1 text,
	    ADD COLUMN IF NOT EXISTS status_kva2 text,
	    ADD COLUMN IF NOT EXISTS status_kva3 text,
	    ADD COLUMN IF NOT EXISTS status_tkva text,
	    ADD COLUMN IF NOT EXISTS status_kvar1 text,
	    ADD COLUMN IF NOT EXISTS status_kvar2 text,
	    ADD COLUMN IF NOT EXISTS status_kvar3 text,
	    ADD COLUMN IF NOT EXISTS status_tkvar text,
	    ADD COLUMN IF NOT EXISTS overall_status text;
	
	-- Roll up worst-case status per metric from the 4 hourly rows in each block
	WITH rolled_up AS (
	    SELECT
	        h.energy_meter_key,
	        date_trunc('day', h.bucket_start_utc)
	            + (floor(extract(hour FROM h.bucket_start_utc) / 4) * interval '4 hour') AS bucket_4h,
	
	        silver.worst_status(VARIADIC array_agg(h.status_vn1))  AS status_vn1,
	        silver.worst_status(VARIADIC array_agg(h.status_vn2))  AS status_vn2,
	        silver.worst_status(VARIADIC array_agg(h.status_vn3))  AS status_vn3,
	        silver.worst_status(VARIADIC array_agg(h.status_v1))   AS status_v1,
	        silver.worst_status(VARIADIC array_agg(h.status_v2))   AS status_v2,
	        silver.worst_status(VARIADIC array_agg(h.status_v3))   AS status_v3,
	        silver.worst_status(VARIADIC array_agg(h.status_amp1)) AS status_amp1,
	        silver.worst_status(VARIADIC array_agg(h.status_amp2)) AS status_amp2,
	        silver.worst_status(VARIADIC array_agg(h.status_amp3)) AS status_amp3,
	        silver.worst_status(VARIADIC array_agg(h.status_hz))   AS status_hz,
	        silver.worst_status(VARIADIC array_agg(h.status_pf1))  AS status_pf1,
	        silver.worst_status(VARIADIC array_agg(h.status_pf2))  AS status_pf2,
	        silver.worst_status(VARIADIC array_agg(h.status_pf3))  AS status_pf3,
	        silver.worst_status(VARIADIC array_agg(h.status_kw1))  AS status_kw1,
	        silver.worst_status(VARIADIC array_agg(h.status_kw2))  AS status_kw2,
	        silver.worst_status(VARIADIC array_agg(h.status_kw3))  AS status_kw3,
	        silver.worst_status(VARIADIC array_agg(h.status_tkw))  AS status_tkw,
	        silver.worst_status(VARIADIC array_agg(h.status_kva1)) AS status_kva1,
	        silver.worst_status(VARIADIC array_agg(h.status_kva2)) AS status_kva2,
	        silver.worst_status(VARIADIC array_agg(h.status_kva3)) AS status_kva3,
	        silver.worst_status(VARIADIC array_agg(h.status_tkva)) AS status_tkva,
	        silver.worst_status(VARIADIC array_agg(h.status_kvar1)) AS status_kvar1,
	        silver.worst_status(VARIADIC array_agg(h.status_kvar2)) AS status_kvar2,
	        silver.worst_status(VARIADIC array_agg(h.status_kvar3)) AS status_kvar3,
	        silver.worst_status(VARIADIC array_agg(h.status_tkvar)) AS status_tkvar,
	        silver.worst_status(VARIADIC array_agg(h.overall_status)) AS overall_status
	    FROM silver.agg_energy_1h h
	    GROUP BY h.energy_meter_key,
	             date_trunc('day', h.bucket_start_utc)
	                + (floor(extract(hour FROM h.bucket_start_utc) / 4) * interval '4 hour')
	)
	UPDATE silver.agg_energy_4h a
	SET
	    status_vn1 = r.status_vn1, status_vn2 = r.status_vn2, status_vn3 = r.status_vn3,
	    status_v1 = r.status_v1, status_v2 = r.status_v2, status_v3 = r.status_v3,
	    status_amp1 = r.status_amp1, status_amp2 = r.status_amp2, status_amp3 = r.status_amp3,
	    status_hz = r.status_hz,
	    status_pf1 = r.status_pf1, status_pf2 = r.status_pf2, status_pf3 = r.status_pf3,
	    status_kw1 = r.status_kw1, status_kw2 = r.status_kw2, status_kw3 = r.status_kw3, status_tkw = r.status_tkw,
	    status_kva1 = r.status_kva1, status_kva2 = r.status_kva2, status_kva3 = r.status_kva3, status_tkva = r.status_tkva,
	    status_kvar1 = r.status_kvar1, status_kvar2 = r.status_kvar2, status_kvar3 = r.status_kvar3, status_tkvar = r.status_tkvar,
	    overall_status = r.overall_status
	FROM rolled_up r
	WHERE a.energy_meter_key = r.energy_meter_key
	  AND a.bucket_start_utc = r.bucket_4h
	  AND a.overall_status IS NULL;  -- only backfill unclassified rows, safe to re-run

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT bucket_start_utc, status_pf1, status_tkw, overall_status
	FROM silver.agg_energy_4h
	WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND bucket_start_utc >= '2025-07-01' AND bucket_start_utc < '2025-07-02'
	ORDER BY bucket_start_utc;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT bucket_start_utc, kwh_consumption, overall_status, reading_count
	FROM silver.agg_energy_3d
	WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	ORDER BY bucket_start_utc LIMIT 5;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
-- ============================================================
	-- silver.agg_energy_3d
	-- Rolled up from silver.agg_energy_1d.
	-- 3-day buckets anchored to the epoch so they're consistent
	-- (day 0-2, 3-5, 6-8, ...) rather than drifting per meter.
	-- ============================================================
	
	CREATE TABLE IF NOT EXISTS silver.agg_energy_3d (
	    energy_meter_key            uuid NOT NULL,
	    facility_key                uuid,
	    zone_key                    uuid,
	    grid_billing_account_key    uuid,
	    bucket_start_utc             timestamp without time zone NOT NULL,
	
	    kwh_consumption              double precision,
	    kvarh_consumption            double precision,
	    kvah_consumption             double precision,
	
	    avg_vn1 double precision, min_vn1 double precision, max_vn1 double precision,
	    avg_vn2 double precision, min_vn2 double precision, max_vn2 double precision,
	    avg_vn3 double precision, min_vn3 double precision, max_vn3 double precision,
	
	    avg_v1 double precision, min_v1 double precision, max_v1 double precision,
	    avg_v2 double precision, min_v2 double precision, max_v2 double precision,
	    avg_v3 double precision, min_v3 double precision, max_v3 double precision,
	
	    avg_amp1 double precision, max_amp1 double precision,
	    avg_amp2 double precision, max_amp2 double precision,
	    avg_amp3 double precision, max_amp3 double precision,
	
	    avg_frequency_hz double precision, min_frequency_hz double precision, max_frequency_hz double precision,
	
	    avg_pf1 double precision, min_pf1 double precision,
	    avg_pf2 double precision, min_pf2 double precision,
	    avg_pf3 double precision, min_pf3 double precision,
	
	    avg_kw1 double precision, max_kw1 double precision,
	    avg_kw2 double precision, max_kw2 double precision,
	    avg_kw3 double precision, max_kw3 double precision,
	    avg_tkw double precision, max_tkw double precision,
	
	    avg_kva1 double precision, max_kva1 double precision,
	    avg_kva2 double precision, max_kva2 double precision,
	    avg_kva3 double precision, max_kva3 double precision,
	    avg_tkva double precision, max_tkva double precision,
	
	    avg_kvar1 double precision, max_kvar1 double precision,
	    avg_kvar2 double precision, max_kvar2 double precision,
	    avg_kvar3 double precision, max_kvar3 double precision,
	    avg_tkvar double precision, max_tkvar double precision,
	
	    reading_count                integer,
	
	    status_vn1  text, status_vn2  text, status_vn3  text,
	    status_v1   text, status_v2   text, status_v3   text,
	    status_amp1 text, status_amp2 text, status_amp3 text,
	    status_hz   text,
	    status_pf1  text, status_pf2  text, status_pf3  text,
	    status_kw1  text, status_kw2  text, status_kw3  text, status_tkw  text,
	    status_kva1 text, status_kva2 text, status_kva3 text, status_tkva text,
	    status_kvar1 text, status_kvar2 text, status_kvar3 text, status_tkvar text,
	    overall_status text,
	
	    loaded_at                    timestamp without time zone DEFAULT now(),
	
	    PRIMARY KEY (energy_meter_key, bucket_start_utc)
	);
	
	INSERT INTO silver.agg_energy_3d (
	    energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_start_utc,
	    kwh_consumption, kvarh_consumption, kvah_consumption,
	    avg_vn1, min_vn1, max_vn1, avg_vn2, min_vn2, max_vn2, avg_vn3, min_vn3, max_vn3,
	    avg_v1, min_v1, max_v1, avg_v2, min_v2, max_v2, avg_v3, min_v3, max_v3,
	    avg_amp1, max_amp1, avg_amp2, max_amp2, avg_amp3, max_amp3,
	    avg_frequency_hz, min_frequency_hz, max_frequency_hz,
	    avg_pf1, min_pf1, avg_pf2, min_pf2, avg_pf3, min_pf3,
	    avg_kw1, max_kw1, avg_kw2, max_kw2, avg_kw3, max_kw3, avg_tkw, max_tkw,
	    avg_kva1, max_kva1, avg_kva2, max_kva2, avg_kva3, max_kva3, avg_tkva, max_tkva,
	    avg_kvar1, max_kvar1, avg_kvar2, max_kvar2, avg_kvar3, max_kvar3, avg_tkvar, max_tkvar,
	    reading_count,
	    status_vn1, status_vn2, status_vn3, status_v1, status_v2, status_v3,
	    status_amp1, status_amp2, status_amp3, status_hz,
	    status_pf1, status_pf2, status_pf3,
	    status_kw1, status_kw2, status_kw3, status_tkw,
	    status_kva1, status_kva2, status_kva3, status_tkva,
	    status_kvar1, status_kvar2, status_kvar3, status_tkvar,
	    overall_status
	)
	WITH last_loaded AS (
	    SELECT COALESCE(MAX(bucket_start_utc), '1970-01-01'::timestamp) AS cutoff
	    FROM silver.agg_energy_3d
	),
	source AS (
	    SELECT
	        d.*,
	        -- 3-day buckets anchored to epoch (day 0), so grouping is stable
	        ('1970-01-01'::date + (floor((d.bucket_start_utc::date - '1970-01-01'::date) / 3) * 3))::timestamp AS bucket_3d
	    FROM silver.agg_energy_1d d, last_loaded l
	    WHERE d.bucket_start_utc > l.cutoff
	)
	SELECT
	    energy_meter_key, facility_key, zone_key, grid_billing_account_key,
	    bucket_3d,
	
	    SUM(kwh_consumption), SUM(kvarh_consumption), SUM(kvah_consumption),
	
	    SUM(avg_vn1 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_vn1), MAX(max_vn1),
	    SUM(avg_vn2 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_vn2), MAX(max_vn2),
	    SUM(avg_vn3 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_vn3), MAX(max_vn3),
	
	    SUM(avg_v1 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_v1), MAX(max_v1),
	    SUM(avg_v2 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_v2), MAX(max_v2),
	    SUM(avg_v3 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_v3), MAX(max_v3),
	
	    SUM(avg_amp1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_amp1),
	    SUM(avg_amp2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_amp2),
	    SUM(avg_amp3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_amp3),
	
	    SUM(avg_frequency_hz * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_frequency_hz), MAX(max_frequency_hz),
	
	    SUM(avg_pf1 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_pf1),
	    SUM(avg_pf2 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_pf2),
	    SUM(avg_pf3 * reading_count) / NULLIF(SUM(reading_count), 0), MIN(min_pf3),
	
	    SUM(avg_kw1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kw1),
	    SUM(avg_kw2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kw2),
	    SUM(avg_kw3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kw3),
	    SUM(avg_tkw * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_tkw),
	
	    SUM(avg_kva1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kva1),
	    SUM(avg_kva2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kva2),
	    SUM(avg_kva3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kva3),
	    SUM(avg_tkva * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_tkva),
	
	    SUM(avg_kvar1 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kvar1),
	    SUM(avg_kvar2 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kvar2),
	    SUM(avg_kvar3 * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_kvar3),
	    SUM(avg_tkvar * reading_count) / NULLIF(SUM(reading_count), 0), MAX(max_tkvar),
	
	    SUM(reading_count)::integer,
	
	    silver.worst_status(VARIADIC array_agg(status_vn1)),
	    silver.worst_status(VARIADIC array_agg(status_vn2)),
	    silver.worst_status(VARIADIC array_agg(status_vn3)),
	    silver.worst_status(VARIADIC array_agg(status_v1)),
	    silver.worst_status(VARIADIC array_agg(status_v2)),
	    silver.worst_status(VARIADIC array_agg(status_v3)),
	    silver.worst_status(VARIADIC array_agg(status_amp1)),
	    silver.worst_status(VARIADIC array_agg(status_amp2)),
	    silver.worst_status(VARIADIC array_agg(status_amp3)),
	    silver.worst_status(VARIADIC array_agg(status_hz)),
	    silver.worst_status(VARIADIC array_agg(status_pf1)),
	    silver.worst_status(VARIADIC array_agg(status_pf2)),
	    silver.worst_status(VARIADIC array_agg(status_pf3)),
	    silver.worst_status(VARIADIC array_agg(status_kw1)),
	    silver.worst_status(VARIADIC array_agg(status_kw2)),
	    silver.worst_status(VARIADIC array_agg(status_kw3)),
	    silver.worst_status(VARIADIC array_agg(status_tkw)),
	    silver.worst_status(VARIADIC array_agg(status_kva1)),
	    silver.worst_status(VARIADIC array_agg(status_kva2)),
	    silver.worst_status(VARIADIC array_agg(status_kva3)),
	    silver.worst_status(VARIADIC array_agg(status_tkva)),
	    silver.worst_status(VARIADIC array_agg(status_kvar1)),
	    silver.worst_status(VARIADIC array_agg(status_kvar2)),
	    silver.worst_status(VARIADIC array_agg(status_kvar3)),
	    silver.worst_status(VARIADIC array_agg(status_tkvar)),
	    silver.worst_status(VARIADIC array_agg(overall_status))
	
	FROM source
	GROUP BY energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_3d
	ON CONFLICT (energy_meter_key, bucket_start_utc) DO NOTHING;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT
	    c.relname AS object_name,
	    CASE c.relkind
	        WHEN 'v' THEN format(
	            'CREATE OR REPLACE VIEW %I.%I AS%n%s;',
	            n.nspname,
	            c.relname,
	            pg_get_viewdef(c.oid, true)
	        )
	        WHEN 'm' THEN format(
	            'CREATE MATERIALIZED VIEW %I.%I AS%n%s;',
	            n.nspname,
	            c.relname,
	            pg_get_viewdef(c.oid, true)
	        )
	    END AS complete_create_statement,
	    md5(
	        regexp_replace(
	            pg_get_viewdef(c.oid, true),
	            '\s+',
	            ' ',
	            'g'
	        )
	    ) AS normalized_definition_md5
	FROM pg_class AS c
	JOIN pg_namespace AS n
	    ON n.oid = c.relnamespace
	WHERE n.nspname = 'silver'
	  AND c.relname IN (
	      'fact_energy_readings_staging',
	      'dim_energy_meter_staging',
	      'energy_meter_mapping_audit_staging',
	      'fact_energy_readings_flagged'
	  )
	  AND c.relkind IN ('v', 'm')
	ORDER BY c.relname;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT reading_timestamp_utc, status_vn1, status_v1, status_pf1, overall_status
	FROM silver.fact_energy_readings_flagged
	WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND reading_timestamp_utc >= '2025-07-01' AND reading_timestamp_utc < '2025-07-01 04:00:00'
	ORDER BY reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-08-03_000000.log
-- ==========================================================================
SELECT COUNT(*) FROM silver.data_quality_summary;

-- ==========================================================================
-- from postgresql-2026-08-04_000000.log
-- ==========================================================================
SELECT
	    COUNT(*) FILTER (WHERE status_kw1='Critical' OR status_kw2='Critical' OR status_kw3='Critical') AS active_power_critical_rows,
	    COUNT(*) FILTER (WHERE (status_kw1='Critical' OR status_kw2='Critical' OR status_kw3='Critical') AND overall_status='Critical') AS active_power_critical_and_overall_critical,
	    COUNT(*) FILTER (WHERE (status_kw1='Critical' OR status_kw2='Critical' OR status_kw3='Critical') AND overall_status='Invalid') AS active_power_critical_but_overall_invalid
	FROM silver.fact_energy_readings_flagged f
	JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = f.energy_meter_key
	WHERE m.meter_label = 'ZN.16-PB_child__1_ch3pm';

-- ==========================================================================
-- from postgresql-2026-08-04_000000.log
-- ==========================================================================
SELECT
	    ROUND(MIN(active_power_total_kw)::numeric, 2) AS min_tkw_all_time,
	    COUNT(*) FILTER (WHERE active_power_total_kw < 0) AS negative_reading_count,
	    COUNT(*) AS total_readings
	FROM silver.fact_energy_readings_staging f
	JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = f.energy_meter_key
	WHERE m.meter_label = 'ZN.16-PB_child__1_ch3pm';

-- ==========================================================================
-- from postgresql-2026-08-04_000000.log
-- ==========================================================================
SELECT
	    COUNT(*) FILTER (WHERE status_vn1='Critical' OR status_vn2='Critical' OR status_vn3='Critical') AS voltage_neutral_critical,
	    COUNT(*) FILTER (WHERE status_v1='Critical' OR status_v2='Critical' OR status_v3='Critical') AS voltage_line_critical,
	    COUNT(*) FILTER (WHERE status_hz='Critical') AS frequency_critical,
	    COUNT(*) FILTER (WHERE status_amp1='Critical' OR status_amp2='Critical' OR status_amp3='Critical') AS current_critical,
	    COUNT(*) FILTER (WHERE status_kw1='Critical' OR status_kw2='Critical' OR status_kw3='Critical') AS active_power_critical,
	    COUNT(*) FILTER (WHERE status_kva1='Critical' OR status_kva2='Critical' OR status_kva3='Critical') AS apparent_power_critical,
	    COUNT(*) FILTER (WHERE status_kwh='Critical' OR status_kvah='Critical' OR status_kvarh='Critical') AS energy_critical,
	    COUNT(*) FILTER (WHERE overall_status='Invalid') AS invalid_rows
	FROM silver.fact_energy_readings_flagged
	WHERE energy_meter_key = '<dce95f37-66a8-4b01-8b78-5f49b73d9eb5>'::uuid;

-- ==========================================================================
-- from postgresql-2026-08-04_000000.log
-- ==========================================================================
SELECT
	    'ZN.5-PB' AS meter,
	    COUNT(*) FILTER (WHERE status_vn1='Critical' OR status_vn2='Critical' OR status_vn3='Critical') AS voltage_neutral_critical,
	    COUNT(*) FILTER (WHERE status_v1='Critical' OR status_v2='Critical' OR status_v3='Critical') AS voltage_line_critical,
	    COUNT(*) FILTER (WHERE status_hz='Critical') AS frequency_critical,
	    COUNT(*) FILTER (WHERE status_amp1='Critical' OR status_amp2='Critical' OR status_amp3='Critical') AS current_critical,
	    COUNT(*) FILTER (WHERE status_kw1='Critical' OR status_kw2='Critical' OR status_kw3='Critical') AS active_power_critical,
	    COUNT(*) FILTER (WHERE status_kva1='Critical' OR status_kva2='Critical' OR status_kva3='Critical') AS apparent_power_critical,
	    COUNT(*) FILTER (WHERE status_kwh='Critical' OR status_kvah='Critical' OR status_kvarh='Critical') AS energy_critical,
	    COUNT(*) FILTER (WHERE overall_status='Invalid') AS invalid_rows
	FROM silver.fact_energy_readings_flagged f
	JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = f.energy_meter_key
	WHERE m.meter_label = 'ZN.5-PB_child__1_ch3pm'
	
	UNION ALL
	
	SELECT
	    'ZN.8-PB.2',
	    COUNT(*) FILTER (WHERE status_vn1='Critical' OR status_vn2='Critical' OR status_vn3='Critical'),
	    COUNT(*) FILTER (WHERE status_v1='Critical' OR status_v2='Critical' OR status_v3='Critical'),
	    COUNT(*) FILTER (WHERE status_hz='Critical'),
	    COUNT(*) FILTER (WHERE status_amp1='Critical' OR status_amp2='Critical' OR status_amp3='Critical'),
	    COUNT(*) FILTER (WHERE status_kw1='Critical' OR status_kw2='Critical' OR status_kw3='Critical'),
	    COUNT(*) FILTER (WHERE status_kva1='Critical' OR status_kva2='Critical' OR status_kva3='Critical'),
	    COUNT(*) FILTER (WHERE status_kwh='Critical' OR status_kvah='Critical' OR status_kvarh='Critical'),
	    COUNT(*) FILTER (WHERE overall_status='Invalid')
	FROM silver.fact_energy_readings_flagged f
	JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = f.energy_meter_key
	WHERE m.meter_label = 'ZN.8-PB.2_child__1_ch3pm';

-- ==========================================================================
-- from postgresql-2026-08-04_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."bucket_start_utc" as "bucket_start_utc",

	    "$Table"."kwh_consumption" as "kwh_consumption",

	    "$Table"."kvarh_consumption" as "kvarh_consumption",

	    "$Table"."kvah_consumption" as "kvah_consumption",

	    "$Table"."avg_vn1" as "avg_vn1",

	    "$Table"."min_vn1" as "min_vn1",

	    "$Table"."max_vn1" as "max_vn1",

	    "$Table"."avg_vn2" as "avg_vn2",

	    "$Table"."min_vn2" as "min_vn2",

	    "$Table"."max_vn2" as "max_vn2",

	    "$Table"."avg_vn3" as "avg_vn3",

	    "$Table"."min_vn3" as "min_vn3",

	    "$Table"."max_vn3" as "max_vn3",

	    "$Table"."avg_v1" as "avg_v1",

	    "$Table"."min_v1" as "min_v1",

	    "$Table"."max_v1" as "max_v1",

	    "$Table"."avg_v2" as "avg_v2",

	    "$Table"."min_v2" as "min_v2",

	    "$Table"."max_v2" as "max_v2",

	    "$Table"."avg_v3" as "avg_v3",

	    "$Table"."min_v3" as "min_v3",

	    "$Table"."max_v3" as "max_v3",

	    "$Table"."avg_amp1" as "avg_amp1",

	    "$Table"."max_amp1" as "max_amp1",

	    "$Table"."avg_amp2" as "avg_amp2",

	    "$Table"."max_amp2" as "max_amp2",

	    "$Table"."avg_amp3" as "avg_amp3",

	    "$Table"."max_amp3" as "max_amp3",

	    "$Table"."avg_frequency_hz" as "avg_frequency_hz",

	    "$Table"."min_frequency_hz" as "min_frequency_hz",

	    "$Table"."max_frequency_hz" as "max_frequency_hz",

	    "$Table"."avg_pf1" as "avg_pf1",

	    "$Table"."min_pf1" as "min_pf1",

	    "$Table"."avg_pf2" as "avg_pf2",

	    "$Table"."min_pf2" as "min_pf2",

	    "$Table"."avg_pf3" as "avg_pf3",

	    "$Table"."min_pf3" as "min_pf3",

	    "$Table"."avg_kw1" as "avg_kw1",

	    "$Table"."max_kw1" as "max_kw1",

	    "$Table"."avg_kw2" as "avg_kw2",

	    "$Table"."max_kw2" as "max_kw2",

	    "$Table"."avg_kw3" as "avg_kw3",

	    "$Table"."max_kw3" as "max_kw3",

	    "$Table"."avg_tkw" as "avg_tkw",

	    "$Table"."max_tkw" as "max_tkw",

	    "$Table"."avg_kva1" as "avg_kva1",

	    "$Table"."max_kva1" as "max_kva1",

	    "$Table"."avg_kva2" as "avg_kva2",

	    "$Table"."max_kva2" as "max_kva2",

	    "$Table"."avg_kva3" as "avg_kva3",

	    "$Table"."max_kva3" as "max_kva3",

	    "$Table"."avg_tkva" as "avg_tkva",

	    "$Table"."max_tkva" as "max_tkva",

	    "$Table"."avg_kvar1" as "avg_kvar1",

	    "$Table"."max_kvar1" as "max_kvar1",

	    "$Table"."avg_kvar2" as "avg_kvar2",

	    "$Table"."max_kvar2" as "max_kvar2",

	    "$Table"."avg_kvar3" as "avg_kvar3",

	    "$Table"."max_kvar3" as "max_kvar3",

	    "$Table"."avg_tkvar" as "avg_tkvar",

	    "$Table"."max_tkvar" as "max_tkvar",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."loaded_at" as "loaded_at",

	    "$Table"."status_vn1" as "status_vn1",

	    "$Table"."status_vn2" as "status_vn2",

	    "$Table"."status_vn3" as "status_vn3",

	    "$Table"."status_v1" as "status_v1",

	    "$Table"."status_v2" as "status_v2",

	    "$Table"."status_v3" as "status_v3",

	    "$Table"."status_amp1" as "status_amp1",

	    "$Table"."status_amp2" as "status_amp2",

	    "$Table"."status_amp3" as "status_amp3",

	    "$Table"."status_hz" as "status_hz",

	    "$Table"."status_pf1" as "status_pf1",

	    "$Table"."status_pf2" as "status_pf2",

	    "$Table"."status_pf3" as "status_pf3",

	    "$Table"."status_kw1" as "status_kw1",

	    "$Table"."status_kw2" as "status_kw2",

	    "$Table"."status_kw3" as "status_kw3",

	    "$Table"."status_tkw" as "status_tkw",

	    "$Table"."status_kva1" as "status_kva1",

	    "$Table"."status_kva2" as "status_kva2",

	    "$Table"."status_kva3" as "status_kva3",

	    "$Table"."status_tkva" as "status_tkva",

	    "$Table"."status_kvar1" as "status_kvar1",

	    "$Table"."status_kvar2" as "status_kvar2",

	    "$Table"."status_kvar3" as "status_kvar3",

	    "$Table"."status_tkvar" as "status_tkvar",

	    "$Table"."overall_status" as "overall_status"

	from "gold"."energy_daily" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-08-04_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."bucket_start_utc" as "bucket_start_utc",

	    "$Table"."kwh_consumption" as "kwh_consumption",

	    "$Table"."kvarh_consumption" as "kvarh_consumption",

	    "$Table"."kvah_consumption" as "kvah_consumption",

	    "$Table"."avg_vn1" as "avg_vn1",

	    "$Table"."min_vn1" as "min_vn1",

	    "$Table"."max_vn1" as "max_vn1",

	    "$Table"."avg_vn2" as "avg_vn2",

	    "$Table"."min_vn2" as "min_vn2",

	    "$Table"."max_vn2" as "max_vn2",

	    "$Table"."avg_vn3" as "avg_vn3",

	    "$Table"."min_vn3" as "min_vn3",

	    "$Table"."max_vn3" as "max_vn3",

	    "$Table"."avg_v1" as "avg_v1",

	    "$Table"."min_v1" as "min_v1",

	    "$Table"."max_v1" as "max_v1",

	    "$Table"."avg_v2" as "avg_v2",

	    "$Table"."min_v2" as "min_v2",

	    "$Table"."max_v2" as "max_v2",

	    "$Table"."avg_v3" as "avg_v3",

	    "$Table"."min_v3" as "min_v3",

	    "$Table"."max_v3" as "max_v3",

	    "$Table"."avg_amp1" as "avg_amp1",

	    "$Table"."max_amp1" as "max_amp1",

	    "$Table"."avg_amp2" as "avg_amp2",

	    "$Table"."max_amp2" as "max_amp2",

	    "$Table"."avg_amp3" as "avg_amp3",

	    "$Table"."max_amp3" as "max_amp3",

	    "$Table"."avg_frequency_hz" as "avg_frequency_hz",

	    "$Table"."min_frequency_hz" as "min_frequency_hz",

	    "$Table"."max_frequency_hz" as "max_frequency_hz",

	    "$Table"."avg_pf1" as "avg_pf1",

	    "$Table"."min_pf1" as "min_pf1",

	    "$Table"."avg_pf2" as "avg_pf2",

	    "$Table"."min_pf2" as "min_pf2",

	    "$Table"."avg_pf3" as "avg_pf3",

	    "$Table"."min_pf3" as "min_pf3",

	    "$Table"."avg_kw1" as "avg_kw1",

	    "$Table"."max_kw1" as "max_kw1",

	    "$Table"."avg_kw2" as "avg_kw2",

	    "$Table"."max_kw2" as "max_kw2",

	    "$Table"."avg_kw3" as "avg_kw3",

	    "$Table"."max_kw3" as "max_kw3",

	    "$Table"."avg_tkw" as "avg_tkw",

	    "$Table"."max_tkw" as "max_tkw",

	    "$Table"."avg_kva1" as "avg_kva1",

	    "$Table"."max_kva1" as "max_kva1",

	    "$Table"."avg_kva2" as "avg_kva2",

	    "$Table"."max_kva2" as "max_kva2",

	    "$Table"."avg_kva3" as "avg_kva3",

	    "$Table"."max_kva3" as "max_kva3",

	    "$Table"."avg_tkva" as "avg_tkva",

	    "$Table"."max_tkva" as "max_tkva",

	    "$Table"."avg_kvar1" as "avg_kvar1",

	    "$Table"."max_kvar1" as "max_kvar1",

	    "$Table"."avg_kvar2" as "avg_kvar2",

	    "$Table"."max_kvar2" as "max_kvar2",

	    "$Table"."avg_kvar3" as "avg_kvar3",

	    "$Table"."max_kvar3" as "max_kvar3",

	    "$Table"."avg_tkvar" as "avg_tkvar",

	    "$Table"."max_tkvar" as "max_tkvar",

	    "$Table"."reading_count" as "reading_count",

	    "$Table"."status_vn1" as "status_vn1",

	    "$Table"."status_vn2" as "status_vn2",

	    "$Table"."status_vn3" as "status_vn3",

	    "$Table"."status_v1" as "status_v1",

	    "$Table"."status_v2" as "status_v2",

	    "$Table"."status_v3" as "status_v3",

	    "$Table"."status_amp1" as "status_amp1",

	    "$Table"."status_amp2" as "status_amp2",

	    "$Table"."status_amp3" as "status_amp3",

	    "$Table"."status_hz" as "status_hz",

	    "$Table"."status_pf1" as "status_pf1",

	    "$Table"."status_pf2" as "status_pf2",

	    "$Table"."status_pf3" as "status_pf3",

	    "$Table"."status_kw1" as "status_kw1",

	    "$Table"."status_kw2" as "status_kw2",

	    "$Table"."status_kw3" as "status_kw3",

	    "$Table"."status_tkw" as "status_tkw",

	    "$Table"."status_kva1" as "status_kva1",

	    "$Table"."status_kva2" as "status_kva2",

	    "$Table"."status_kva3" as "status_kva3",

	    "$Table"."status_tkva" as "status_tkva",

	    "$Table"."status_kvar1" as "status_kvar1",

	    "$Table"."status_kvar2" as "status_kvar2",

	    "$Table"."status_kvar3" as "status_kvar3",

	    "$Table"."status_tkvar" as "status_tkvar",

	    "$Table"."overall_status" as "overall_status",

	    "$Table"."loaded_at" as "loaded_at"

	from "gold"."energy_weekly" "$Table"

	limit 1000

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
select * views from silver

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
select * view from silver

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
CREATE OR REPLACE VIEW gold.energy_5min AS
	SELECT * FROM silver.agg_energy_5min;

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
CREATE OR REPLACE VIEW gold.energy_5min AS
	SELECT * FROM silver.agg_energy_5min

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
-- ============================================================
	-- silver.agg_energy_5min
	--
	-- Identical structure and logic to silver.agg_energy_30min --
	-- raw scan of silver.fact_energy_readings_staging, cumulative
	-- counters (kWh, kVArh) as sum-of-positive-deltas, everything
	-- else as AVG/MIN/MAX, apparent-power family excluded (confirmed
	-- empty facility-wide). Only difference: 5-minute buckets instead
	-- of 30-minute ones.
	--
	-- EXPECTED SHAPE: since raw readings arrive roughly every 5
	-- minutes already, most buckets will contain exactly 1 reading,
	-- so avg = min = max in most rows. Buckets with a real gap in
	-- that window simply won't produce a row (same behavior as every
	-- other grain -- no row is emitted for a bucket with zero
	-- readings). Occasional buckets may show reading_count = 2 if two
	-- readings land inside the same 5-minute window due to timing
	-- jitter in the source telemetry.
	--
	-- Safe to re-run repeatedly (incremental load).
	-- ============================================================
	
	CREATE TABLE IF NOT EXISTS silver.agg_energy_5min (
	    energy_meter_key            uuid NOT NULL,
	    facility_key                uuid,
	    zone_key                    uuid,
	    grid_billing_account_key    uuid,
	    bucket_start_utc             timestamp without time zone NOT NULL,
	
	    kwh_consumption              double precision,
	    kvarh_consumption            double precision,
	
	    avg_vn1 double precision, min_vn1 double precision, max_vn1 double precision,
	    avg_vn2 double precision, min_vn2 double precision, max_vn2 double precision,
	    avg_vn3 double precision, min_vn3 double precision, max_vn3 double precision,
	
	    avg_v1 double precision, min_v1 double precision, max_v1 double precision,
	    avg_v2 double precision, min_v2 double precision, max_v2 double precision,
	    avg_v3 double precision, min_v3 double precision, max_v3 double precision,
	
	    avg_amp1 double precision, max_amp1 double precision,
	    avg_amp2 double precision, max_amp2 double precision,
	    avg_amp3 double precision, max_amp3 double precision,
	
	    avg_frequency_hz double precision, min_frequency_hz double precision, max_frequency_hz double precision,
	
	    avg_pf1 double precision, min_pf1 double precision,
	    avg_pf2 double precision, min_pf2 double precision,
	    avg_pf3 double precision, min_pf3 double precision,
	
	    avg_kw1 double precision, max_kw1 double precision,
	    avg_kw2 double precision, max_kw2 double precision,
	    avg_kw3 double precision, max_kw3 double precision,
	    avg_tkw double precision, max_tkw double precision,
	
	    avg_kvar1 double precision, max_kvar1 double precision,
	    avg_kvar2 double precision, max_kvar2 double precision,
	    avg_kvar3 double precision, max_kvar3 double precision,
	    avg_tkvar double precision, max_tkvar double precision,
	
	    reading_count                integer,
	    loaded_at                    timestamp without time zone DEFAULT now(),
	
	    PRIMARY KEY (energy_meter_key, bucket_start_utc)
	);
	
	-- ============================================================
	-- Incremental load
	-- ============================================================
	
	INSERT INTO silver.agg_energy_5min (
	    energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_start_utc,
	    kwh_consumption, kvarh_consumption,
	    avg_vn1, min_vn1, max_vn1, avg_vn2, min_vn2, max_vn2, avg_vn3, min_vn3, max_vn3,
	    avg_v1, min_v1, max_v1, avg_v2, min_v2, max_v2, avg_v3, min_v3, max_v3,
	    avg_amp1, max_amp1, avg_amp2, max_amp2, avg_amp3, max_amp3,
	    avg_frequency_hz, min_frequency_hz, max_frequency_hz,
	    avg_pf1, min_pf1, avg_pf2, min_pf2, avg_pf3, min_pf3,
	    avg_kw1, max_kw1, avg_kw2, max_kw2, avg_kw3, max_kw3, avg_tkw, max_tkw,
	    avg_kvar1, max_kvar1, avg_kvar2, max_kvar2, avg_kvar3, max_kvar3, avg_tkvar, max_tkvar,
	    reading_count
	)
	WITH last_loaded AS (
	    SELECT COALESCE(MAX(bucket_start_utc), '1970-01-01'::timestamp) AS cutoff
	    FROM silver.agg_energy_5min
	),
	base AS (
	    SELECT f.*
	    FROM silver.fact_energy_readings_staging f, last_loaded l
	    WHERE f.reading_timestamp_utc > l.cutoff
	),
	deltas AS (
	    SELECT
	        *,
	        GREATEST(active_energy_cumulative_kwh
	            - LAG(active_energy_cumulative_kwh) OVER (PARTITION BY energy_meter_key ORDER BY reading_timestamp_utc), 0) AS kwh_delta,
	        GREATEST(reactive_energy_cumulative_kvarh
	            - LAG(reactive_energy_cumulative_kvarh) OVER (PARTITION BY energy_meter_key ORDER BY reading_timestamp_utc), 0) AS kvarh_delta
	    FROM base
	),
	bucketed AS (
	    SELECT
	        *,
	        date_trunc('hour', reading_timestamp_utc)
	            + (floor(extract(minute FROM reading_timestamp_utc) / 5.0)::int * interval '5 minutes') AS bucket_start_utc
	    FROM deltas
	)
	SELECT
	    energy_meter_key, facility_key, zone_key, grid_billing_account_key,
	    bucket_start_utc,
	
	    SUM(kwh_delta)   AS kwh_consumption,
	    SUM(kvarh_delta) AS kvarh_consumption,
	
	    AVG(voltage_neutral_1_v), MIN(voltage_neutral_1_v), MAX(voltage_neutral_1_v),
	    AVG(voltage_neutral_2_v), MIN(voltage_neutral_2_v), MAX(voltage_neutral_2_v),
	    AVG(voltage_neutral_3_v), MIN(voltage_neutral_3_v), MAX(voltage_neutral_3_v),
	
	    AVG(voltage_line_1_v), MIN(voltage_line_1_v), MAX(voltage_line_1_v),
	    AVG(voltage_line_2_v), MIN(voltage_line_2_v), MAX(voltage_line_2_v),
	    AVG(voltage_line_3_v), MIN(voltage_line_3_v), MAX(voltage_line_3_v),
	
	    AVG(current_phase_1_a), MAX(current_phase_1_a),
	    AVG(current_phase_2_a), MAX(current_phase_2_a),
	    AVG(current_phase_3_a), MAX(current_phase_3_a),
	
	    AVG(frequency_hz), MIN(frequency_hz), MAX(frequency_hz),
	
	    AVG(power_factor_phase_1), MIN(power_factor_phase_1),
	    AVG(power_factor_phase_2), MIN(power_factor_phase_2),
	    AVG(power_factor_phase_3), MIN(power_factor_phase_3),
	
	    AVG(active_power_phase_1_kw), MAX(active_power_phase_1_kw),
	    AVG(active_power_phase_2_kw), MAX(active_power_phase_2_kw),
	    AVG(active_power_phase_3_kw), MAX(active_power_phase_3_kw),
	    AVG(active_power_total_kw),   MAX(active_power_total_kw),
	
	    AVG(reactive_power_phase_1_kvar), MAX(reactive_power_phase_1_kvar),
	    AVG(reactive_power_phase_2_kvar), MAX(reactive_power_phase_2_kvar),
	    AVG(reactive_power_phase_3_kvar), MAX(reactive_power_phase_3_kvar),
	    AVG(reactive_power_total_kvar),   MAX(reactive_power_total_kvar),
	
	    COUNT(*) AS reading_count
	
	FROM bucketed
	GROUP BY energy_meter_key, facility_key, zone_key, grid_billing_account_key, bucket_start_utc
	ON CONFLICT (energy_meter_key, bucket_start_utc) DO NOTHING;

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
SELECT * FROM silver.fact_energy_readings_flagged;

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
-- ============================================================
	-- silver.fact_energy_readings_snapshot (CORRECTED)
	--
	-- Combines the REAL measured values (from staging) with their
	-- quality status (from flagged) -- one row per actual reading,
	-- real timestamp, real number, plus its status flag. No
	-- averaging, no bucketing, nothing invented.
	--
	-- fact_energy_readings_flagged alone only has status_* columns,
	-- no actual values -- confirmed via information_schema. This
	-- version fixes that by joining back to fact_energy_readings_staging
	-- for the real numbers.
	--
	-- Full refresh (TRUNCATE + reload), same reasoning as before:
	-- flagged's spike-detection depends on reading order, so an
	-- incremental filter risks a wrong "previous reading" at the seam.
	-- ============================================================
	
	DROP TABLE IF EXISTS silver.fact_energy_readings_snapshot CASCADE;
	
	CREATE TABLE silver.fact_energy_readings_snapshot AS
	SELECT
	    s.energy_meter_key, s.facility_key, s.zone_key, s.grid_billing_account_key,
	    s.reading_timestamp_utc,
	
	    -- Cumulative counters (real values, as reported)
	    s.active_energy_cumulative_kwh,
	    s.reactive_energy_cumulative_kvarh,
	    s.apparent_energy_cumulative_kvah,
	
	    -- Voltage (Line-to-Neutral)
	    s.voltage_neutral_1_v, s.voltage_neutral_2_v, s.voltage_neutral_3_v,
	
	    -- Voltage (Line-to-Line)
	    s.voltage_line_1_v, s.voltage_line_2_v, s.voltage_line_3_v,
	
	    -- Current
	    s.current_phase_1_a, s.current_phase_2_a, s.current_phase_3_a,
	
	    -- Frequency
	    s.frequency_hz,
	
	    -- Power Factor
	    s.power_factor_phase_1, s.power_factor_phase_2, s.power_factor_phase_3, s.power_factor_average,
	
	    -- Active Power
	    s.active_power_phase_1_kw, s.active_power_phase_2_kw, s.active_power_phase_3_kw, s.active_power_total_kw,
	
	    -- Apparent Power
	    s.apparent_power_phase_1_kva, s.apparent_power_phase_2_kva, s.apparent_power_phase_3_kva, s.apparent_power_total_kva,
	
	    -- Reactive Power
	    s.reactive_power_phase_1_kvar, s.reactive_power_phase_2_kvar, s.reactive_power_phase_3_kvar, s.reactive_power_total_kvar,
	
	    -- Quality status, per reading (from the flagged view)
	    g.status_vn1, g.status_vn2, g.status_vn3, g.status_vna,
	    g.status_v1, g.status_v2, g.status_v3, g.status_va,
	    g.status_amp1, g.status_amp2, g.status_amp3, g.status_ampa,
	    g.status_hz,
	    g.status_pf1, g.status_pf2, g.status_pf3, g.status_pfa,
	    g.status_kw1, g.status_kw2, g.status_kw3, g.status_tkw,
	    g.status_kva1, g.status_kva2, g.status_kva3, g.status_tkva,
	    g.status_kvar1, g.status_kvar2, g.status_kvar3, g.status_tkvar,
	    g.status_kwh, g.status_kvah, g.status_kvarh,
	    g.overall_status
	
	FROM silver.fact_energy_readings_staging s
	JOIN silver.fact_energy_readings_flagged g
	    ON g.energy_meter_key = s.energy_meter_key
	   AND g.reading_timestamp_utc = s.reading_timestamp_utc;
	
	ALTER TABLE silver.fact_energy_readings_snapshot
	    ADD CONSTRAINT pk_energy_readings_snapshot
	    PRIMARY KEY (energy_meter_key, reading_timestamp_utc);

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
SELECT
	    (SELECT COUNT(*) FROM silver.fact_energy_readings_staging)  AS staging_count,
	    (SELECT COUNT(*) FROM silver.fact_energy_readings_flagged)  AS flagged_count,
	    (SELECT COUNT(*) FROM silver.fact_energy_readings_snapshot) AS snapshot_count;

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
WITH bronze_packet_counts AS (
	    SELECT device_id, COUNT(DISTINCT timestamp) AS bronze_packet_count
	    FROM bronze.telemetries
	    WHERE device_id IN (SELECT DISTINCT source_energy_meter_id FROM silver.fact_energy_readings_snapshot)
	    GROUP BY device_id
	),
	silver_packet_counts AS (
	    SELECT source_energy_meter_id, COUNT(*) AS silver_packet_count
	    FROM silver.fact_energy_readings_snapshot
	    GROUP BY source_energy_meter_id
	)
	SELECT
	    b.device_id,
	    b.bronze_packet_count,
	    s.silver_packet_count,
	    (b.bronze_packet_count - s.silver_packet_count) AS diff
	FROM bronze_packet_counts b
	JOIN silver_packet_counts s ON s.source_energy_meter_id = b.device_id
	ORDER BY ABS(b.bronze_packet_count - s.silver_packet_count) DESC;

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
-- Change meter and hour if desired
	SELECT
	    meter_label,
	    reading_timestamp_utc,
	    voltage_neutral_1_v,
	    status_vn1
	FROM gold.energy_raw
	WHERE meter_label = 'ZN.5-PB_child__1_ch3pm'
	  AND reading_timestamp_utc >= TIMESTAMP '2025-04-06 12:00:00'
	  AND reading_timestamp_utc <  TIMESTAMP '2025-04-06 13:00:00'
	ORDER BY reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-08-09_000000.log
-- ==========================================================================
SELECT
	    meter_label,
	    bucket_start_utc,
	    avg_vn1,
	    min_vn1,
	    max_vn1,
	    status_vn1
	FROM gold.energy_hourly
	WHERE meter_label = 'ZN.5-PB_child__1_ch3pm'
	  AND bucket_start_utc = TIMESTAMP '2025-04-06 12:00:00';

-- ==========================================================================
-- from postgresql-2026-08-10_000000.log
-- ==========================================================================
-- ============================================================
	-- silver.dim_meter_cb_rating
	-- Per-meter circuit breaker max rating, needed for Current
	-- classification (each meter has its own CB rating, unlike
	-- every other metric which uses one fixed threshold facility-wide).
	-- ============================================================
	
	CREATE TABLE IF NOT EXISTS silver.dim_meter_cb_rating (
	    energy_meter_key    uuid PRIMARY KEY REFERENCES silver.dim_energy_meter_staging(energy_meter_key),
	    cb_max_rating_a      double precision NOT NULL,
	    updated_at           timestamp without time zone DEFAULT now()
	);
	
	-- Populate using meter_label to look up the real energy_meter_key,
	-- so we don't have to hand-type 31 UUIDs. The two name corrections
	-- already confirmed: 'ZN.20-PB' -> 'ZN.20-PB.1', 'ZN.21-PB.1' -> 'ZN.21-PB'.
	
	INSERT INTO silver.dim_meter_cb_rating (energy_meter_key, cb_max_rating_a)
	SELECT d.energy_meter_key, v.cb_max_rating_a
	FROM (VALUES
	    ('ZN.1-PB.1_child__1_ch3pm',  100),
	    ('ZN.1-PB.2_child__1_ch3pm',  100),
	    ('ZN.2-PB_child__1_ch3pm',    100),
	    ('ZN.3-PB.1_child__1_ch3pm',  100),
	    ('ZN.3-PB.2_child__1_ch3pm',  100),
	    ('ZN.4-PB.1_child__1_ch3pm',  100),
	    ('ZN.4-PB.2_child__1_ch3pm',  125),
	    ('ZN.5-PB_child__1_ch3pm',    100),
	    ('ZN.6-PB_child__1_ch3pm',    250),
	    ('ZN.7-PB_child__1_ch3pm',    250),
	    ('ZN.8-PB.1_child__1_ch3pm',  160),
	    ('ZN.8-PB.2_child__1_ch3pm',  160),
	    ('ZN.9-PB_child__1_ch3pm',    250),
	    ('ZN.10-PB.1_child__1_ch3pm', 80),
	    ('ZN.10-PB.2_child__1_ch3pm', 80),
	    ('ZN.11-PB.1_child__1_ch3pm', 80),
	    ('ZN.11-PB.2_child__1_ch3pm', 80),
	    ('ZN.12-PB_child__1_ch3pm',   100),
	    ('ZN.13-PB.1_child__1_ch3pm', 125),
	    ('ZN.13-PB.2_child__1_ch3pm', 125),
	    ('ZN.14-PB_child__1_ch3pm',   80),
	    ('ZN.15-PB.1_child__1_ch3pm', 125),
	    ('ZN.15-PB.2_child__1_ch3pm', 250),
	    ('ZN.16-PB_child__1_ch3pm',   200),
	    ('ZN.17-PB_child__1_ch3pm',   250),
	    ('ZN.18-PB_child__1_ch3pm',   100),
	    ('ZN.19-PB.1_child__1_ch3pm', 160),
	    ('ZN.19-PB.2_child__1_ch3pm', 250),
	    ('ZN.20-PB.1_child__1_ch3pm', 100),  -- was 'ZN.20-PB' in source
	    ('ZN.20-PB.2_child__1_ch3pm', 100),
	    ('ZN.21-PB_child__1_ch3pm',   100)   -- was 'ZN.21-PB.1' in source
	) AS v(meter_label, cb_max_rating_a)
	JOIN silver.dim_energy_meter_staging d ON d.meter_label = v.meter_label
	ON CONFLICT (energy_meter_key) DO UPDATE SET
	    cb_max_rating_a = EXCLUDED.cb_max_rating_a,
	    updated_at = now();
	
	-- Sanity check: should return exactly 31 rows, and the "missing"
	-- query right below it should return 0 rows (every canonical
	-- meter has a CB rating).
	SELECT COUNT(*) AS cb_ratings_loaded FROM silver.dim_meter_cb_rating;
	
	SELECT d.meter_label
	FROM silver.dim_energy_meter_staging d
	LEFT JOIN silver.dim_meter_cb_rating cb ON cb.energy_meter_key = d.energy_meter_key
	WHERE cb.energy_meter_key IS NULL;

-- ==========================================================================
-- from postgresql-2026-08-10_000000.log
-- ==========================================================================
-- ============================================================
	-- Corrected classify_* functions
	--
	-- Changes from the originals:
	-- - 5 tiers only, no Anomaly (prev_value comparison removed
	--   from every function except energy's decrement check)
	-- - Invalid is now reserved for NULL/corrupt data only -- the
	--   old numeric Invalid thresholds (e.g. PF>1.0) are absorbed
	--   into Critical, since Critical already covers those values
	-- - classify_current now takes each meter's own CB rating as
	--   a parameter, instead of a fixed threshold
	-- - classify_voltage_line / classify_voltage_neutral now use
	--   the confirmed nested-band shape with 2%-of-Max margins
	-- - classify_active_power, classify_apparent_power,
	--   classify_reactive_power are NOT rewritten -- confirmed
	--   dropped entirely, calls to them will be removed from the
	--   views/tables in the next step, not from this file
	-- ============================================================
	
	-- ------------------------------------------------------------
	-- Voltage (Line-to-Line): Min 360, Max 440, Acceptable 380-420
	-- Margin = 2% of Max (440) = 8.8
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_voltage_line(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 360 OR value > 440 THEN RETURN 'Critical'; END IF;
	    IF value >= 380 AND value <= 420 THEN RETURN 'Acceptable'; END IF;
	    IF (value >= 371.2 AND value < 380) OR (value > 420 AND value <= 428.8) THEN RETURN 'Review Required'; END IF;
	    RETURN 'Problematic';  -- remaining zones: 360-371.2 and 428.8-440
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Voltage (Line-to-Neutral): Min 207, Max 253, Acceptable 215-245
	-- Margin = 2% of Max (253) = 5.06
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_voltage_neutral(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 207 OR value > 253 THEN RETURN 'Critical'; END IF;
	    IF value >= 215 AND value <= 245 THEN RETURN 'Acceptable'; END IF;
	    IF (value >= 209.94 AND value < 215) OR (value > 245 AND value <= 250.06) THEN RETURN 'Review Required'; END IF;
	    RETURN 'Problematic';  -- remaining zones: 207-209.94 and 250.06-253
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Frequency: Min 59, Max 61, Acceptable 59.3-60.5
	-- No Review Required tier -- straight Acceptable -> Problematic
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_frequency(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 59 OR value > 61 THEN RETURN 'Critical'; END IF;
	    IF value >= 59.3 AND value <= 60.5 THEN RETURN 'Acceptable'; END IF;
	    RETURN 'Problematic';  -- remaining zones: 59-59.3 and 60.5-61
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Power Factor: Min 0.6, Max 1, Acceptable 0.8-1 (Acceptable
	-- Max = Max, so there's no upper Review Required/Problematic band)
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_power_factor(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 0.6 OR value > 1 THEN RETURN 'Critical'; END IF;
	    IF value >= 0.8 AND value <= 1 THEN RETURN 'Acceptable'; END IF;
	    IF value >= 0.78 AND value < 0.8 THEN RETURN 'Review Required'; END IF;
	    RETURN 'Problematic';  -- remaining zone: 0.6-0.78
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Current: per-meter CB rating. Margin = 15% of cb_max, split
	-- into thirds -- inner third (nearer Acceptable) = Review
	-- Required, outer two-thirds (nearer the edge) = Problematic.
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_current(value double precision, cb_max double precision)
	RETURNS text AS $$
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
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Accumulated Energy (kWh only): the one function that still
	-- needs the previous reading -- a decrement is only detectable
	-- by comparing to what came right before it.
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_accumulated_energy(value double precision, prev_value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF prev_value IS NULL THEN RETURN 'Acceptable'; END IF;  -- first-ever reading for this meter, nothing to compare
	    IF value < prev_value THEN RETURN 'Invalid'; END IF;      -- decrement -- counter went backward
	    RETURN 'Acceptable';
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ============================================================
	-- Quick self-test -- run these to confirm each function behaves
	-- as expected before touching any real table.
	-- ============================================================
	SELECT
	    silver.classify_voltage_line(400)   AS should_be_acceptable,
	    silver.classify_voltage_line(375)   AS should_be_review_required,
	    silver.classify_voltage_line(365)   AS should_be_problematic,
	    silver.classify_voltage_line(300)   AS should_be_critical,
	    silver.classify_voltage_line(NULL)  AS should_be_invalid;
	
	SELECT
	    silver.classify_frequency(59.8)     AS should_be_acceptable,
	    silver.classify_frequency(59.1)     AS should_be_problematic,
	    silver.classify_frequency(58)       AS should_be_critical;
	
	SELECT
	    silver.classify_power_factor(0.9)   AS should_be_acceptable,
	    silver.classify_power_factor(0.79)  AS should_be_review_required,
	    silver.classify_power_factor(0.7)   AS should_be_problematic,
	    silver.classify_power_factor(1.5)   AS should_be_critical;
	
	-- Current, CB=80 (matches the worked example: Problematic 0-4 and 76-80,
	-- Review Required 4-12 and 68-76, Acceptable 12-68, Critical <0 or >80)
	SELECT
	    silver.classify_current(40, 80)     AS should_be_acceptable,
	    silver.classify_current(8, 80)      AS should_be_review_required,
	    silver.classify_current(2, 80)      AS should_be_problematic,
	    silver.classify_current(90, 80)     AS should_be_critical,
	    silver.classify_current(50, NULL)   AS should_be_invalid;
	
	SELECT
	    silver.classify_accumulated_energy(48.0, 47.5)  AS should_be_acceptable,
	    silver.classify_accumulated_energy(47.0, 47.5)  AS should_be_invalid_decrement,
	    silver.classify_accumulated_energy(46.5, NULL)  AS should_be_acceptable_first_reading;

-- ==========================================================================
-- from postgresql-2026-08-10_000000.log
-- ==========================================================================
-- ============================================================
	-- Corrected classify_* functions
	--
	-- Changes from the originals:
	-- - 5 tiers only, no Anomaly (prev_value comparison removed
	--   from every function except energy's decrement check)
	-- - Invalid is now reserved for NULL/corrupt data only -- the
	--   old numeric Invalid thresholds (e.g. PF>1.0) are absorbed
	--   into Critical, since Critical already covers those values
	-- - classify_current now takes each meter's own CB rating as
	--   a parameter, instead of a fixed threshold
	-- - classify_voltage_line / classify_voltage_neutral now use
	--   the confirmed nested-band shape with 2%-of-Max margins
	-- - classify_active_power, classify_apparent_power,
	--   classify_reactive_power are NOT rewritten -- confirmed
	--   dropped entirely, calls to them will be removed from the
	--   views/tables in the next step, not from this file
	-- ============================================================
	
	-- ------------------------------------------------------------
	-- Voltage (Line-to-Line): Min 360, Max 440, Acceptable 380-420
	-- Margin = 2% of Max (440) = 8.8
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_voltage_line(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 360 OR value > 440 THEN RETURN 'Critical'; END IF;
	    IF value >= 380 AND value <= 420 THEN RETURN 'Acceptable'; END IF;
	    IF (value >= 371.2 AND value < 380) OR (value > 420 AND value <= 428.8) THEN RETURN 'Review Required'; END IF;
	    RETURN 'Problematic';  -- remaining zones: 360-371.2 and 428.8-440
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Voltage (Line-to-Neutral): Min 207, Max 253, Acceptable 215-245
	-- Margin = 2% of Max (253) = 5.06
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_voltage_neutral(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 207 OR value > 253 THEN RETURN 'Critical'; END IF;
	    IF value >= 215 AND value <= 245 THEN RETURN 'Acceptable'; END IF;
	    IF (value >= 209.94 AND value < 215) OR (value > 245 AND value <= 250.06) THEN RETURN 'Review Required'; END IF;
	    RETURN 'Problematic';  -- remaining zones: 207-209.94 and 250.06-253
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Frequency: Min 59, Max 61, Acceptable 59.3-60.5
	-- No Review Required tier -- straight Acceptable -> Problematic
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_frequency(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 59 OR value > 61 THEN RETURN 'Critical'; END IF;
	    IF value >= 59.3 AND value <= 60.5 THEN RETURN 'Acceptable'; END IF;
	    RETURN 'Problematic';  -- remaining zones: 59-59.3 and 60.5-61
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Power Factor: Min 0.6, Max 1, Acceptable 0.8-1 (Acceptable
	-- Max = Max, so there's no upper Review Required/Problematic band)
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_power_factor(value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF value < 0.6 OR value > 1 THEN RETURN 'Critical'; END IF;
	    IF value >= 0.8 AND value <= 1 THEN RETURN 'Acceptable'; END IF;
	    IF value >= 0.78 AND value < 0.8 THEN RETURN 'Review Required'; END IF;
	    RETURN 'Problematic';  -- remaining zone: 0.6-0.78
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Current: per-meter CB rating. Margin = 15% of cb_max, split
	-- into thirds -- inner third (nearer Acceptable) = Review
	-- Required, outer two-thirds (nearer the edge) = Problematic.
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_current(value double precision, cb_max double precision)
	RETURNS text AS $$
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
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ------------------------------------------------------------
	-- Accumulated Energy (kWh only): the one function that still
	-- needs the previous reading -- a decrement is only detectable
	-- by comparing to what came right before it.
	-- ------------------------------------------------------------
	CREATE OR REPLACE FUNCTION silver.classify_accumulated_energy(value double precision, prev_value double precision)
	RETURNS text AS $$
	BEGIN
	    IF value IS NULL THEN RETURN 'Invalid'; END IF;
	    IF prev_value IS NULL THEN RETURN 'Acceptable'; END IF;  -- first-ever reading for this meter, nothing to compare
	    IF value < prev_value THEN RETURN 'Invalid'; END IF;      -- decrement -- counter went backward
	    RETURN 'Acceptable';
	END;
	$$ LANGUAGE plpgsql IMMUTABLE;
	
	-- ============================================================
	-- Quick self-test -- run these to confirm each function behaves
	-- as expected before touching any real table.
	-- ============================================================
	SELECT
	    silver.classify_voltage_line(400::double precision)   AS should_be_acceptable,
	    silver.classify_voltage_line(375::double precision)   AS should_be_review_required,
	    silver.classify_voltage_line(365::double precision)   AS should_be_problematic,
	    silver.classify_voltage_line(300::double precision)   AS should_be_critical,
	    silver.classify_voltage_line(NULL::double precision)  AS should_be_invalid;
	
	SELECT
	    silver.classify_frequency(59.8::double precision)     AS should_be_acceptable,
	    silver.classify_frequency(59.1::double precision)     AS should_be_problematic,
	    silver.classify_frequency(58::double precision)       AS should_be_critical;
	
	SELECT
	    silver.classify_power_factor(0.9::double precision)   AS should_be_acceptable,
	    silver.classify_power_factor(0.79::double precision)  AS should_be_review_required,
	    silver.classify_power_factor(0.7::double precision)   AS should_be_problematic,
	    silver.classify_power_factor(1.5::double precision)   AS should_be_critical;
	
	-- Current, CB=80 (matches the worked example: Problematic 0-4 and 76-80,
	-- Review Required 4-12 and 68-76, Acceptable 12-68, Critical <0 or >80)
	SELECT
	    silver.classify_current(40::double precision, 80::double precision)   AS should_be_acceptable,
	    silver.classify_current(8::double precision, 80::double precision)    AS should_be_review_required,
	    silver.classify_current(2::double precision, 80::double precision)    AS should_be_problematic,
	    silver.classify_current(90::double precision, 80::double precision)   AS should_be_critical,
	    silver.classify_current(50::double precision, NULL::double precision) AS should_be_invalid;
	
	SELECT
	    silver.classify_accumulated_energy(48.0::double precision, 47.5::double precision) AS should_be_acceptable,
	    silver.classify_accumulated_energy(47.0::double precision, 47.5::double precision) AS should_be_invalid_decrement,
	    silver.classify_accumulated_energy(46.5::double precision, NULL::double precision) AS should_be_acceptable_first_reading;

-- ==========================================================================
-- from postgresql-2026-08-10_000000.log
-- ==========================================================================
-- ============================================================
	-- Rebuild silver.fact_energy_readings_snapshot with corrected
	-- statuses. Also fixes the earlier oversight: this version
	-- includes voltage_line_average_v and voltage_neutral_average_v
	-- as real value columns (even though they're NULL for every
	-- meter, they belong in the raw data for completeness).
	-- ============================================================
	
	DROP TABLE IF EXISTS silver.fact_energy_readings_snapshot CASCADE;
	
	CREATE TABLE silver.fact_energy_readings_snapshot AS
	SELECT
	    s.energy_meter_key, s.facility_key, s.zone_key, s.grid_billing_account_key,
	    s.reading_timestamp_utc,
	
	    s.active_energy_cumulative_kwh,
	    s.reactive_energy_cumulative_kvarh,
	    s.apparent_energy_cumulative_kvah,
	
	    s.voltage_neutral_1_v, s.voltage_neutral_2_v, s.voltage_neutral_3_v, s.voltage_neutral_average_v,
	    s.voltage_line_1_v, s.voltage_line_2_v, s.voltage_line_3_v, s.voltage_line_average_v,
	
	    s.current_phase_1_a, s.current_phase_2_a, s.current_phase_3_a,
	
	    s.frequency_hz,
	
	    s.power_factor_phase_1, s.power_factor_phase_2, s.power_factor_phase_3, s.power_factor_average,
	
	    s.active_power_phase_1_kw, s.active_power_phase_2_kw, s.active_power_phase_3_kw, s.active_power_total_kw,
	    s.apparent_power_phase_1_kva, s.apparent_power_phase_2_kva, s.apparent_power_phase_3_kva, s.apparent_power_total_kva,
	    s.reactive_power_phase_1_kvar, s.reactive_power_phase_2_kvar, s.reactive_power_phase_3_kvar, s.reactive_power_total_kvar,
	
	    g.status_vn1, g.status_vn2, g.status_vn3,
	    g.status_v1, g.status_v2, g.status_v3,
	    g.status_amp1, g.status_amp2, g.status_amp3,
	    g.status_hz,
	    g.status_pf1, g.status_pf2, g.status_pf3, g.status_pfa,
	    g.status_kwh,
	    g.overall_status
	
	FROM silver.fact_energy_readings_staging s
	JOIN silver.fact_energy_readings_flagged g
	    ON g.energy_meter_key = s.energy_meter_key
	   AND g.reading_timestamp_utc = s.reading_timestamp_utc;
	
	ALTER TABLE silver.fact_energy_readings_snapshot
	    ADD CONSTRAINT pk_energy_readings_snapshot
	    PRIMARY KEY (energy_meter_key, reading_timestamp_utc);
	
	-- Quick check -- reference meter, one hour, should show real
	-- corrected statuses and no more constant Invalid
	SELECT reading_timestamp_utc, status_vn1, status_pf1, status_amp1, status_kwh, overall_status
	FROM silver.fact_energy_readings_snapshot
	WHERE energy_meter_key = 'a0396787-f0f9-4037-a5cd-232c3b6edde3'::uuid
	  AND reading_timestamp_utc >= '2025-07-01' AND reading_timestamp_utc < '2025-07-01 01:00:00'
	ORDER BY reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-08-10_000000.log
-- ==========================================================================
select cast("$Table"."energy_meter_key" as varchar) as "energy_meter_key",

	    cast("$Table"."facility_key" as varchar) as "facility_key",

	    cast("$Table"."zone_key" as varchar) as "zone_key",

	    cast("$Table"."grid_billing_account_key" as varchar) as "grid_billing_account_key",

	    "$Table"."reading_timestamp_utc" as "reading_timestamp_utc",

	    "$Table"."active_energy_cumulative_kwh" as "active_energy_cumulative_kwh",

	    "$Table"."reactive_energy_cumulative_kvarh" as "reactive_energy_cumulative_kvarh",

	    "$Table"."apparent_energy_cumulative_kvah" as "apparent_energy_cumulative_kvah",

	    "$Table"."voltage_neutral_1_v" as "voltage_neutral_1_v",

	    "$Table"."voltage_neutral_2_v" as "voltage_neutral_2_v",

	    "$Table"."voltage_neutral_3_v" as "voltage_neutral_3_v",

	    "$Table"."voltage_line_1_v" as "voltage_line_1_v",

	    "$Table"."voltage_line_2_v" as "voltage_line_2_v",

	    "$Table"."voltage_line_3_v" as "voltage_line_3_v",

	    "$Table"."current_phase_1_a" as "current_phase_1_a",

	    "$Table"."current_phase_2_a" as "current_phase_2_a",

	    "$Table"."current_phase_3_a" as "current_phase_3_a",

	    "$Table"."frequency_hz" as "frequency_hz",

	    "$Table"."power_factor_phase_1" as "power_factor_phase_1",

	    "$Table"."power_factor_phase_2" as "power_factor_phase_2",

	    "$Table"."power_factor_phase_3" as "power_factor_phase_3",

	    "$Table"."power_factor_average" as "power_factor_average",

	    "$Table"."active_power_phase_1_kw" as "active_power_phase_1_kw",

	    "$Table"."active_power_phase_2_kw" as "active_power_phase_2_kw",

	    "$Table"."active_power_phase_3_kw" as "active_power_phase_3_kw",

	    "$Table"."active_power_total_kw" as "active_power_total_kw",

	    "$Table"."apparent_power_phase_1_kva" as "apparent_power_phase_1_kva",

	    "$Table"."apparent_power_phase_2_kva" as "apparent_power_phase_2_kva",

	    "$Table"."apparent_power_phase_3_kva" as "apparent_power_phase_3_kva",

	    "$Table"."apparent_power_total_kva" as "apparent_power_total_kva",

	    "$Table"."reactive_power_phase_1_kvar" as "reactive_power_phase_1_kvar",

	    "$Table"."reactive_power_phase_2_kvar" as "reactive_power_phase_2_kvar",

	    "$Table"."reactive_power_phase_3_kvar" as "reactive_power_phase_3_kvar",

	    "$Table"."reactive_power_total_kvar" as "reactive_power_total_kvar",

	    "$Table"."status_vn1" as "status_vn1",

	    "$Table"."status_vn2" as "status_vn2",

	    "$Table"."status_vn3" as "status_vn3",

	    "$Table"."status_vna" as "status_vna",

	    "$Table"."status_v1" as "status_v1",

	    "$Table"."status_v2" as "status_v2",

	    "$Table"."status_v3" as "status_v3",

	    "$Table"."status_va" as "status_va",

	    "$Table"."status_amp1" as "status_amp1",

	    "$Table"."status_amp2" as "status_amp2",

	    "$Table"."status_amp3" as "status_amp3",

	    "$Table"."status_ampa" as "status_ampa",

	    "$Table"."status_hz" as "status_hz",

	    "$Table"."status_pf1" as "status_pf1",

	    "$Table"."status_pf2" as "status_pf2",

	    "$Table"."status_pf3" as "status_pf3",

	    "$Table"."status_pfa" as "status_pfa",

	    "$Table"."status_kw1" as "status_kw1",

	    "$Table"."status_kw2" as "status_kw2",

	    "$Table"."status_kw3" as "status_kw3",

	    "$Table"."status_tkw" as "status_tkw",

	    "$Table"."status_kva1" as "status_kva1",

	    "$Table"."status_kva2" as "status_kva2",

	    "$Table"."status_kva3" as "status_kva3",

	    "$Table"."status_tkva" as "status_tkva",

	    "$Table"."status_kvar1" as "status_kvar1",

	    "$Table"."status_kvar2" as "status_kvar2",

	    "$Table"."status_kvar3" as "status_kvar3",

	    "$Table"."status_tkvar" as "status_tkvar",

	    "$Table"."status_kwh" as "status_kwh",

	    "$Table"."status_kvah" as "status_kvah",

	    "$Table"."status_kvarh" as "status_kvarh",

	    "$Table"."overall_status" as "overall_status"

	from "gold"."energy_raw" "$Table"

	limit 200

-- ==========================================================================
-- from postgresql-2026-08-17_000000.log
-- ==========================================================================
SELECT
	    e.reading_timestamp_utc,
	    m.meter_label,
	    e.current_phase_1_a,
	    e.status_amp1
	FROM gold.energy_raw e
	LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
	WHERE m.meter_label = 'ZN.18-PB_child__1_ch3pm'
	ORDER BY e.reading_timestamp_utc ASC,sum(e.current_phase_1_a,);

-- ==========================================================================
-- from postgresql-2026-08-17_000000.log
-- ==========================================================================
SELECT
	    e.reading_timestamp_utc,
	    m.meter_label,
	    e.current_phase_1_a,
	    e.status_amp1
	FROM gold.energy_raw e
	LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
	WHERE m.meter_label = 'ZN.18-PB_child__1_ch3pm'
	ORDER BY e.reading_timestamp_utc ASC,sum(e.current_phase_1_a);

-- ==========================================================================
-- from postgresql-2026-08-17_000000.log
-- ==========================================================================
CREATE TABLE silver.fact_energy_consumption_validated AS
	
	WITH base AS (
	    SELECT
	        s.energy_meter_key,
	        s.source_energy_meter_id,
	        s.facility_key,
	        s.zone_key,
	        s.grid_billing_account_key,
	        s.source_timestamp_ms,
	        s.reading_timestamp_utc,
	        s.reading_timestamp_saudi,
	        s.reading_date_saudi,
	
	        s.active_energy_cumulative_kwh,
	
	        f.status_kwh,
	        m.meter_label
	
	    FROM silver.fact_energy_readings_staging s
	
	    LEFT JOIN silver.fact_energy_readings_flagged f
	        ON f.energy_meter_key = s.energy_meter_key
	       AND f.source_timestamp_ms = s.source_timestamp_ms
	
	    LEFT JOIN silver.dim_energy_meter_staging m
	        ON m.energy_meter_key = s.energy_meter_key
	),
	
	/* Get surrounding cumulative kWh readings */
	ordered AS (
	    SELECT
	        *,
	
	        LAG(active_energy_cumulative_kwh, 1) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS raw_previous_kwh,
	
	        LAG(active_energy_cumulative_kwh, 2) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS raw_previous_2_kwh,
	
	        LEAD(active_energy_cumulative_kwh, 1) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS raw_next_kwh
	
	    FROM base
	),
	
	/* Apply the consumption cleaning rules */
	classified AS (
	    SELECT
	        *,
	
	        CASE
	
	            /* -----------------------------------------
	               Zone 13:
	               completely excluded from consumption
	               ----------------------------------------- */
	            WHEN meter_label LIKE 'ZN.13-%'
	            THEN 'EXCLUDED_ZONE13'
	
	
	            WHEN active_energy_cumulative_kwh IS NULL
	            THEN 'MISSING_KWH'
	
	
	            /* -----------------------------------------
	               ZN.1-PB.1 installation/startup readings
	
	               Valid sequence begins at 46.5
	               ----------------------------------------- */
	            WHEN meter_label = 'ZN.1-PB.1_child__1_ch3pm'
	                 AND reading_timestamp_utc <
	                     TIMESTAMP '2024-12-10 17:16:15.655'
	            THEN 'STARTUP_EXCLUDED'
	
	
	            WHEN meter_label = 'ZN.1-PB.1_child__1_ch3pm'
	                 AND reading_timestamp_utc =
	                     TIMESTAMP '2024-12-10 17:16:15.655'
	            THEN 'STARTUP_BASELINE'
	
	
	            /* -----------------------------------------
	               ZN.4-PB.1 installation/startup readings
	
	               Valid sequence begins at 150.4
	               ----------------------------------------- */
	            WHEN meter_label = 'ZN.4-PB.1_child__1_ch3pm'
	                 AND reading_timestamp_utc <
	                     TIMESTAMP '2024-12-10 21:46:39.010'
	            THEN 'STARTUP_EXCLUDED'
	
	
	            WHEN meter_label = 'ZN.4-PB.1_child__1_ch3pm'
	                 AND reading_timestamp_utc =
	                     TIMESTAMP '2024-12-10 21:46:39.010'
	            THEN 'STARTUP_BASELINE'
	
	
	            /* -----------------------------------------
	               Single isolated LOW reading
	
	               1218.4 -> 30.5 -> 1218.8
	
	               30.5 is ignored
	               ----------------------------------------- */
	            WHEN raw_previous_kwh IS NOT NULL
	                 AND raw_next_kwh IS NOT NULL
	                 AND active_energy_cumulative_kwh < raw_previous_kwh
	                 AND raw_next_kwh >= raw_previous_kwh
	
	            THEN 'ISOLATED_LOW_BAD'
	
	
	            /* -----------------------------------------
	               Single isolated HIGH spike
	
	               35272.4 -> 94894 -> 35272.8
	
	               94894 is ignored
	               ----------------------------------------- */
	            WHEN raw_previous_kwh IS NOT NULL
	                 AND raw_next_kwh IS NOT NULL
	                 AND active_energy_cumulative_kwh > raw_previous_kwh
	                 AND active_energy_cumulative_kwh > raw_next_kwh
	                 AND raw_next_kwh >= raw_previous_kwh
	
	            THEN 'ISOLATED_HIGH_BAD'
	
	
	            /* -----------------------------------------
	               Recovery after isolated high spike
	
	               35272.4 -> 94894 -> 35272.8
	
	               35272.8 is a valid recovery reading
	               ----------------------------------------- */
	            WHEN raw_previous_2_kwh IS NOT NULL
	                 AND raw_previous_kwh IS NOT NULL
	                 AND raw_previous_kwh > raw_previous_2_kwh
	                 AND raw_previous_kwh > active_energy_cumulative_kwh
	                 AND active_energy_cumulative_kwh >= raw_previous_2_kwh
	
	            THEN 'HIGH_SPIKE_RECOVERY'
	
	
	            /* Any decrement we haven't explained */
	            WHEN raw_previous_kwh IS NOT NULL
	                 AND active_energy_cumulative_kwh < raw_previous_kwh
	
	            THEN 'UNRESOLVED_DECREMENT'
	
	
	            /* Normal increase or flat reading */
	            ELSE 'KEEP'
	
	        END AS consumption_cleaning_status
	
	    FROM ordered
	),
	
	/* Determine whether each meter can be used */
	meter_status AS (
	    SELECT
	        *,
	
	        CASE
	
	            WHEN meter_label LIKE 'ZN.13-%'
	            THEN 'EXCLUDED'
	
	            WHEN MAX(
	                CASE
	                    WHEN consumption_cleaning_status =
	                         'UNRESOLVED_DECREMENT'
	                    THEN 1
	                    ELSE 0
	                END
	            ) OVER (
	                PARTITION BY energy_meter_key
	            ) = 1
	            THEN 'REVIEW_REQUIRED'
	
	            ELSE 'ELIGIBLE'
	
	        END AS meter_consumption_status
	
	    FROM classified
	),
	
	/* Keep only trustworthy readings for the consumption sequence */
	valid_sequence AS (
	    SELECT
	        energy_meter_key,
	        reading_timestamp_utc,
	        active_energy_cumulative_kwh
	
	    FROM meter_status
	
	    WHERE meter_consumption_status = 'ELIGIBLE'
	
	      AND consumption_cleaning_status IN (
	          'KEEP',
	          'STARTUP_BASELINE',
	          'HIGH_SPIKE_RECOVERY'
	      )
	),
	
	/* Find previous VALID reading instead of previous raw reading */
	previous_valid AS (
	    SELECT
	        energy_meter_key,
	        reading_timestamp_utc,
	        active_energy_cumulative_kwh,
	
	        LAG(reading_timestamp_utc) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS previous_valid_timestamp,
	
	        LAG(active_energy_cumulative_kwh) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS previous_valid_kwh
	
	    FROM valid_sequence
	),
	
	/* Calculate actual validated consumption */
	calculated AS (
	    SELECT
	        *,
	
	        CASE
	            WHEN previous_valid_kwh IS NULL
	            THEN NULL
	
	            WHEN active_energy_cumulative_kwh >= previous_valid_kwh
	            THEN active_energy_cumulative_kwh - previous_valid_kwh
	
	            ELSE NULL
	        END AS validated_kwh_consumption,
	
	        EXTRACT(
	            EPOCH FROM (
	                reading_timestamp_utc - previous_valid_timestamp
	            )
	        ) / 60.0 AS gap_minutes
	
	    FROM previous_valid
	)
	
	SELECT
	    c.energy_meter_key,
	    c.source_energy_meter_id,
	    c.facility_key,
	    c.zone_key,
	    c.grid_billing_account_key,
	
	    c.meter_label,
	
	    c.source_timestamp_ms,
	    c.reading_timestamp_utc,
	    c.reading_timestamp_saudi,
	    c.reading_date_saudi,
	
	    /* Original cumulative meter value */
	    c.active_energy_cumulative_kwh,
	
	    c.status_kwh,
	
	    /* Raw surrounding readings for validation */
	    c.raw_previous_kwh,
	    c.raw_next_kwh,
	
	    /* Why a reading was kept/ignored */
	    c.consumption_cleaning_status,
	
	    /* Whether this meter contributes to consumption */
	    c.meter_consumption_status,
	
	    /* Previous trustworthy meter reading */
	    v.previous_valid_timestamp,
	    v.previous_valid_kwh,
	
	    /* VALUE WE WILL USE FOR CONSUMPTION */
	    v.validated_kwh_consumption,
	
	    ROUND(v.gap_minutes::numeric, 2) AS gap_minutes,
	
	    CASE
	        WHEN c.meter_consumption_status = 'EXCLUDED'
	        THEN 'EXCLUDED_METER'
	
	        WHEN c.meter_consumption_status = 'REVIEW_REQUIRED'
	        THEN 'REVIEW_REQUIRED'
	
	        WHEN c.consumption_cleaning_status IN (
	            'ISOLATED_LOW_BAD',
	            'ISOLATED_HIGH_BAD',
	            'STARTUP_EXCLUDED',
	            'MISSING_KWH'
	        )
	        THEN 'IGNORED_READING'
	
	        WHEN v.previous_valid_timestamp IS NULL
	        THEN 'FIRST_VALID_READING'
	
	        /* Gap is allowed when cumulative counter increases */
	        WHEN v.gap_minutes >= 15
	        THEN 'LONG_GAP'
	
	        ELSE 'NORMAL_INTERVAL'
	
	    END AS interval_quality
	
	FROM meter_status c
	
	LEFT JOIN calculated v
	    ON v.energy_meter_key = c.energy_meter_key
	   AND v.reading_timestamp_utc = c.reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-08-17_000000.log
-- ==========================================================================
WITH first_reading AS (
	    SELECT DISTINCT ON (energy_meter_key)
	        energy_meter_key,
	        meter_label,
	        reading_timestamp_utc AS first_timestamp,
	        active_energy_cumulative_kwh AS first_kwh
	    FROM silver.fact_energy_consumption_validated
	    WHERE consumption_cleaning_status = 'KEEP'
	    ORDER BY
	        energy_meter_key,
	        reading_timestamp_utc
	),
	
	last_reading AS (
	    SELECT DISTINCT ON (energy_meter_key)
	        energy_meter_key,
	        reading_timestamp_utc AS last_timestamp,
	        active_energy_cumulative_kwh AS last_kwh
	    FROM silver.fact_energy_consumption_validated
	    WHERE consumption_cleaning_status = 'KEEP'
	    ORDER BY
	        energy_meter_key,
	        reading_timestamp_utc DESC
	),
	
	meter_totals AS (
	    SELECT
	        energy_meter_key,
	        meter_label,
	
	        SUM(validated_kwh_consumption)
	            AS summed_validated_consumption,
	
	        COUNT(*) FILTER (
	            WHERE interval_quality = 'UNRESOLVED_DECREMENT'
	        ) AS unresolved_decrements,
	
	        COUNT(*) FILTER (
	            WHERE interval_quality = 'LONG_GAP'
	        ) AS long_gap_intervals
	
	    FROM silver.fact_energy_consumption_validated
	    GROUP BY
	        energy_meter_key,
	        meter_label
	)
	
	SELECT
	    t.meter_label,
	
	    f.first_timestamp,
	    f.first_kwh,
	
	    l.last_timestamp,
	    l.last_kwh,
	
	    ROUND(
	        t.summed_validated_consumption::numeric,
	        2
	    ) AS summed_consumption,
	
	    ROUND(
	        (l.last_kwh - f.first_kwh)::numeric,
	        2
	    ) AS first_to_last_change,
	
	    ROUND(
	        (
	            t.summed_validated_consumption
	            - (l.last_kwh - f.first_kwh)
	        )::numeric,
	        2
	    ) AS difference,
	
	    t.unresolved_decrements,
	    t.long_gap_intervals
	
	FROM meter_totals t
	
	JOIN first_reading f
	    ON f.energy_meter_key = t.energy_meter_key
	
	JOIN last_reading l
	    ON l.energy_meter_key = t.energy_meter_key
	
	ORDER BY
	    ABS(
	        t.summed_validated_consumption
	        - (l.last_kwh - f.first_kwh)
	    ) DESC;

-- ==========================================================================
-- from postgresql-2026-08-20_000000.log
-- ==========================================================================
WITH mismatch AS (
	    SELECT
	        energy_meter_key,
	        meter_label,
	
	        COUNT(*) FILTER (
	            WHERE status_amp1 IN ('Major Issue', 'Major Problem')
	        ) AS phase_1_mismatch,
	
	        COUNT(*) FILTER (
	            WHERE status_amp2 IN ('Major Issue', 'Major Problem')
	        ) AS phase_2_mismatch,
	
	        COUNT(*) FILTER (
	            WHERE status_amp3 IN ('Major Issue', 'Major Problem')
	        ) AS phase_3_mismatch
	
	    FROM gold.energy_raw
	
	    GROUP BY
	        energy_meter_key,
	        meter_label
	)
	
	SELECT
	    meter_label,
	    phase_1_mismatch,
	    phase_2_mismatch,
	    phase_3_mismatch,
	
	    phase_1_mismatch
	    + phase_2_mismatch
	    + phase_3_mismatch AS total_mismatch_events
	
	FROM mismatch
	
	WHERE GREATEST(
	    phase_1_mismatch,
	    phase_2_mismatch,
	    phase_3_mismatch
	) > 100
	
	ORDER BY total_mismatch_events DESC;

-- ==========================================================================
-- from postgresql-2026-08-20_000000.log
-- ==========================================================================
WITH meter_map AS (
	    -- Restrict Bronze to the meters that actually exist
	    -- in our analytical dataset
	    SELECT DISTINCT
	        em.meter_label,
	        em.device_id
	    FROM bronze.energy_meters em
	    JOIN silver.dim_energy_meter_staging m
	        ON m.meter_label = em.meter_label
	),
	
	pf_raw AS (
	    SELECT
	        mm.meter_label,
	        t.timestamp,
	
	        MAX(t.dbl) FILTER (
	            WHERE d.key = 'PF1'
	        ) AS pf1,
	
	        MAX(t.dbl) FILTER (
	            WHERE d.key = 'PF2'
	        ) AS pf2,
	
	        MAX(t.dbl) FILTER (
	            WHERE d.key = 'PF3'
	        ) AS pf3
	
	    FROM meter_map mm
	
	    JOIN bronze.telemetries t
	        ON t.device_id = mm.device_id
	
	    JOIN bronze.telemetries_dictionaries d
	        ON d.id = t.key_id
	
	    WHERE d.key IN ('PF1', 'PF2', 'PF3')
	
	    GROUP BY
	        mm.meter_label,
	        t.timestamp
	),
	
	pf_rates AS (
	    SELECT
	        meter_label,
	
	        COUNT(*) AS bronze_reading_rows,
	
	        COUNT(*) FILTER (
	            WHERE silver.classify_power_factor_v2(pf1) = 'Critical'
	        )::numeric
	        / NULLIF(COUNT(*), 0) AS pf1_critical_pct,
	
	        COUNT(*) FILTER (
	            WHERE silver.classify_power_factor_v2(pf2) = 'Critical'
	        )::numeric
	        / NULLIF(COUNT(*), 0) AS pf2_critical_pct,
	
	        COUNT(*) FILTER (
	            WHERE silver.classify_power_factor_v2(pf3) = 'Critical'
	        )::numeric
	        / NULLIF(COUNT(*), 0) AS pf3_critical_pct
	
	    FROM pf_raw
	
	    GROUP BY meter_label
	),
	
	final AS (
	    SELECT
	        meter_label,
	        bronze_reading_rows,
	        pf1_critical_pct,
	        pf2_critical_pct,
	        pf3_critical_pct,
	
	        GREATEST(
	            pf1_critical_pct,
	            pf2_critical_pct,
	            pf3_critical_pct
	        )
	        -
	        LEAST(
	            pf1_critical_pct,
	            pf2_critical_pct,
	            pf3_critical_pct
	        ) AS critical_spread
	
	    FROM pf_rates
	)
	
	SELECT
	    meter_label,
	    bronze_reading_rows,
	
	    ROUND(pf1_critical_pct * 100, 2) AS pf1_critical_pct,
	    ROUND(pf2_critical_pct * 100, 2) AS pf2_critical_pct,
	    ROUND(pf3_critical_pct * 100, 2) AS pf3_critical_pct,
	
	    ROUND(critical_spread * 100, 2) AS spread_percentage_points
	
	FROM final
	
	WHERE critical_spread > 0.65
	
	ORDER BY critical_spread DESC;

-- ==========================================================================
-- from postgresql-2026-08-20_000000.log
-- ==========================================================================
WITH pf_counts AS (
	    SELECT
	        m.meter_label,
	
	        COUNT(*) FILTER (
	            WHERE t.key_id = 19
	        ) AS pf1_total,
	
	        COUNT(*) FILTER (
	            WHERE t.key_id = 19
	              AND (t.dbl < 0.6 OR t.dbl > 1)
	        ) AS pf1_critical,
	
	        COUNT(*) FILTER (
	            WHERE t.key_id = 36
	        ) AS pf2_total,
	
	        COUNT(*) FILTER (
	            WHERE t.key_id = 36
	              AND (t.dbl < 0.6 OR t.dbl > 1)
	        ) AS pf2_critical,
	
	        COUNT(*) FILTER (
	            WHERE t.key_id = 37
	        ) AS pf3_total,
	
	        COUNT(*) FILTER (
	            WHERE t.key_id = 37
	              AND (t.dbl < 0.6 OR t.dbl > 1)
	        ) AS pf3_critical
	
	    FROM bronze.telemetries t
	
	    JOIN silver.dim_energy_meter_staging m
	        ON m.energy_meter_key = t.device_id
	
	    WHERE t.key_id IN (19, 36, 37)
	
	    GROUP BY m.meter_label
	),
	
	rates AS (
	    SELECT
	        meter_label,
	
	        pf1_total,
	        pf2_total,
	        pf3_total,
	
	        pf1_critical::numeric / NULLIF(pf1_total, 0)
	            AS pf1_critical_pct,
	
	        pf2_critical::numeric / NULLIF(pf2_total, 0)
	            AS pf2_critical_pct,
	
	        pf3_critical::numeric / NULLIF(pf3_total, 0)
	            AS pf3_critical_pct
	
	    FROM pf_counts
	),
	
	final AS (
	    SELECT
	        *,
	
	        GREATEST(
	            pf1_critical_pct,
	            pf2_critical_pct,
	            pf3_critical_pct
	        )
	        -
	        LEAST(
	            pf1_critical_pct,
	            pf2_critical_pct,
	            pf3_critical_pct
	        ) AS pf_critical_spread
	
	    FROM rates
	)
	
	SELECT
	    meter_label,
	
	    pf1_total,
	    pf2_total,
	    pf3_total,
	
	    ROUND(pf1_critical_pct * 100, 2) AS pf1_critical_pct,
	    ROUND(pf2_critical_pct * 100, 2) AS pf2_critical_pct,
	    ROUND(pf3_critical_pct * 100, 2) AS pf3_critical_pct,
	
	    ROUND(pf_critical_spread * 100, 2)
	        AS spread_percentage_points
	
	FROM final
	
	WHERE pf_critical_spread > 0.65
	
	ORDER BY pf_critical_spread DESC;

-- ==========================================================================
-- from postgresql-2026-09-02_000000.log
-- ==========================================================================
SELECT
	    interval_quality,
	    COUNT(*) AS interval_count,
	    ROUND(SUM(validated_kwh_consumption)::numeric, 2) AS consumption_kwh
	FROM silver.fact_energy_consumption_validated
	WHERE meter_label = 'ZN.17-PB_child__1_ch3pm'
	  AND validated_kwh_consumption IS NOT NULL
	GROUP BY interval_quality
	ORDER BY consumption_kwh DESCSELECT
	    reading_timestamp_utc,
	    gap_minutes,
	    previous_valid_kwh,
	    active_energy_cumulative_kwh,
	    validated_kwh_consumption,
	    interval_quality
	FROM silver.fact_energy_consumption_validated
	WHERE meter_label = 'ZN.17-PB_child__1_ch3pm'
	  AND interval_quality = 'LONG_GAP'
	ORDER BY validated_kwh_consumption DESC;

-- ==========================================================================
-- from postgresql-2026-09-02_000000.log
-- ==========================================================================
WITH readings AS (
	    SELECT
	        meter_label,
	        reading_timestamp_utc,
	        reading_timestamp_utc + INTERVAL '3 hours'
	            AS reading_timestamp_saudi,
	        active_energy_cumulative_kwh,
	
	        LAG(active_energy_cumulative_kwh) OVER (
	            PARTITION BY meter_label
	            ORDER BY reading_timestamp_utc
	        ) AS previous_kwh,
	
	        LAG(reading_timestamp_utc) OVER (
	            PARTITION BY meter_label
	            ORDER BY reading_timestamp_utc
	        ) AS previous_timestamp_utc
	
	    FROM silver.fact_energy_readings_snapshot
	
	    WHERE meter_label IN (
	        'ZN.13-PB.1_child__1_ch3pm',
	        'ZN.13-PB.2_child__1_ch3pm'
	    )
	
	      AND active_energy_cumulative_kwh IS NOT NULL
	)
	
	SELECT
	    meter_label,
	
	    previous_timestamp_utc,
	    reading_timestamp_utc,
	
	    reading_timestamp_saudi,
	
	    ROUND(previous_kwh::numeric, 2) AS previous_kwh,
	    ROUND(active_energy_cumulative_kwh::numeric, 2) AS current_kwh,
	
	    ROUND(
	        (active_energy_cumulative_kwh - previous_kwh)::numeric,
	        2
	    ) AS change_kwh
	
	FROM readings
	
	WHERE active_energy_cumulative_kwh < previous_kwh
	
	ORDER BY
	    meter_label,
	    reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-09-04_000000.log
-- ==========================================================================
select * 

	from 

	(

	    WITH readings AS (
	    SELECT
	        energy_meter_key,
	        reading_timestamp_utc,
	        active_energy_cumulative_kwh,
	
	        LAG(active_energy_cumulative_kwh, 1) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS previous_kwh,
	
	        LAG(active_energy_cumulative_kwh, 2) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS two_back_kwh,
	
	        LAG(reading_timestamp_utc, 1) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS previous_timestamp_utc,
	
	        LAG(reading_timestamp_utc, 2) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS two_back_timestamp_utc,
	
	        LEAD(active_energy_cumulative_kwh, 1) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS next_kwh,
	
	        LEAD(reading_timestamp_utc, 1) OVER (
	            PARTITION BY energy_meter_key
	            ORDER BY reading_timestamp_utc
	        ) AS next_timestamp_utc
	
	    FROM silver.fact_energy_readings_snapshot
	
	    WHERE energy_meter_key IN (
	        'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2',
	        '9fc6d98a-5c79-48df-abd5-c0a21e61f40c'
	    )
	
	    AND active_energy_cumulative_kwh IS NOT NULL
	),
	
	stats AS (
	    SELECT
	        energy_meter_key,
	
	        PERCENTILE_CONT(0.99)
	        WITHIN GROUP (
	            ORDER BY active_energy_cumulative_kwh - previous_kwh
	        ) FILTER (
	            WHERE active_energy_cumulative_kwh > previous_kwh
	        ) AS p99_positive_change
	
	    FROM readings
	    GROUP BY energy_meter_key
	),
	
	drops AS (
	    SELECT
	        r.*,
	        s.p99_positive_change,
	
	        previous_kwh - active_energy_cumulative_kwh
	            AS decrement_size_kwh
	
	    FROM readings r
	
	    JOIN stats s
	        ON s.energy_meter_key = r.energy_meter_key
	
	    WHERE active_energy_cumulative_kwh < previous_kwh
	),
	
	classified AS (
	    SELECT
	        d.*,
	
	        recovery.return_timestamp_utc,
	        recovery.return_from_kwh,
	        recovery.return_to_kwh
	
	    FROM drops d
	
	    LEFT JOIN LATERAL (
	        SELECT
	            r2.reading_timestamp_utc AS return_timestamp_utc,
	            r2.previous_kwh AS return_from_kwh,
	            r2.active_energy_cumulative_kwh AS return_to_kwh
	
	        FROM readings r2
	
	        WHERE r2.energy_meter_key = d.energy_meter_key
	
	          AND r2.reading_timestamp_utc >
	              d.reading_timestamp_utc
	
	          AND r2.active_energy_cumulative_kwh >=
	              d.previous_kwh
	
	          AND (
	              r2.active_energy_cumulative_kwh -
	              r2.previous_kwh
	          ) > (10 * d.p99_positive_change)
	
	          AND EXTRACT(
	              EPOCH FROM (
	                  r2.reading_timestamp_utc -
	                  r2.previous_timestamp_utc
	              )
	          ) / 60.0 <= 30
	
	        ORDER BY r2.reading_timestamp_utc
	        LIMIT 1
	
	    ) recovery ON TRUE
	)
	
	SELECT
	    CASE
	        WHEN c.energy_meter_key =
	            'ab6a3ed9-55ef-4e7a-ae8c-718e3f25fdf2'
	            THEN 'PB1'
	        ELSE 'PB2'
	    END AS meter,
	
	    c.reading_timestamp_utc + INTERVAL '3 hours'
	        AS decrement_timestamp_saudi,
	
	    c.previous_kwh,
	
	    c.active_energy_cumulative_kwh
	        AS current_kwh,
	
	    c.decrement_size_kwh,
	
	    c.next_kwh,
	
	    CASE
	        WHEN c.decrement_size_kwh
	            <= 10 * c.p99_positive_change
	        THEN 'Minor Decrement'
	
	        WHEN c.next_kwh >= c.previous_kwh
	         AND EXTRACT(
	             EPOCH FROM (
	                 c.next_timestamp_utc -
	                 c.reading_timestamp_utc
	             )
	         ) / 60.0 <= 30
	         AND (
	             c.next_kwh -
	             c.active_energy_cumulative_kwh
	         ) > 10 * c.p99_positive_change
	        THEN 'Isolated Low Sample'
	
	        WHEN c.two_back_kwh IS NOT NULL
	         AND (
	             c.previous_kwh -
	             c.two_back_kwh
	         ) > 10 * c.p99_positive_change
	         AND EXTRACT(
	             EPOCH FROM (
	                 c.previous_timestamp_utc -
	                 c.two_back_timestamp_utc
	             )
	         ) / 60.0 <= 30
	         AND ABS(
	             c.active_energy_cumulative_kwh -
	             c.two_back_kwh
	         ) <= 10 * c.p99_positive_change
	        THEN 'Return to Low After Upward Spike'
	
	        WHEN c.return_timestamp_utc IS NOT NULL
	        THEN 'Temporary Downward Switch'
	
	        ELSE 'Unresolved Downward Shift'
	
	    END AS problem_type
	
	FROM classified c
	
	ORDER BY
	    c.energy_meter_key,
	    c.reading_timestamp_utc;

	) "_"

	limit 0

-- ==========================================================================
-- from postgresql-2026-09-04_000000.log
-- ==========================================================================
-- ============================================================
	-- Sign mismatch between Power Factor and Active Power, per phase
	--
	-- Electrically, PF and active power should carry the same sign
	-- on a given phase (both flip together if current-transformer
	-- polarity is reversed). A mismatch -- one negative, the other
	-- not, on the same phase, same reading -- is a genuine
	-- inconsistency worth investigating.
	-- ============================================================
	
	WITH mismatches AS (
	    SELECT
	        e.reading_timestamp_utc,
	        m.meter_label,
	        1 AS phase,
	        e.power_factor_phase_1 AS pf,
	        e.active_power_phase_1_kw AS active_power_kw
	    FROM gold.energy_raw e
	    LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
	    WHERE (e.power_factor_phase_1 < 0 AND e.active_power_phase_1_kw >= 0)
	       OR (e.power_factor_phase_1 >= 0 AND e.active_power_phase_1_kw < 0)
	
	    UNION ALL
	
	    SELECT
	        e.reading_timestamp_utc,
	        m.meter_label,
	        2 AS phase,
	        e.power_factor_phase_2,
	        e.active_power_phase_2_kw
	    FROM gold.energy_raw e
	    LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
	    WHERE (e.power_factor_phase_2 < 0 AND e.active_power_phase_2_kw >= 0)
	       OR (e.power_factor_phase_2 >= 0 AND e.active_power_phase_2_kw < 0)
	
	    UNION ALL
	
	    SELECT
	        e.reading_timestamp_utc,
	        m.meter_label,
	        3 AS phase,
	        e.power_factor_phase_3,
	        e.active_power_phase_3_kw
	    FROM gold.energy_raw e
	    LEFT JOIN silver.dim_energy_meter_staging m ON m.energy_meter_key = e.energy_meter_key
	    WHERE (e.power_factor_phase_3 < 0 AND e.active_power_phase_3_kw >= 0)
	       OR (e.power_factor_phase_3 >= 0 AND e.active_power_phase_3_kw < 0)
	)
	
	-- Summary: how many mismatches per meter, per phase
	SELECT meter_label, phase, COUNT(*) AS mismatch_count
	FROM mismatches
	GROUP BY meter_label, phase
	ORDER BY mismatch_count DESC;
	
	-- Detail (comment the summary above out and use this instead if
	-- you want the actual rows, not just counts):
	-- SELECT * FROM mismatches ORDER BY meter_label, phase, reading_timestamp_utc;

-- ==========================================================================
-- from postgresql-2026-09-04_000000.log
-- ==========================================================================
SELECT DISTINCT
	    key_id,
	    key
	FROM keys
	WHERE LOWER(key) LIKE '%pf%'
	ORDER BY key;

-- ==========================================================================
-- from postgresql-2026-09-04_000000.log
-- ==========================================================================
SELECT
	    em.energy_meter_key,
	    em.meter_label,
	    em.device_id
	FROM gold.meter em
	WHERE em.meter_label = 'ZN.12-PB_child__1_ch3pm';

-- ==========================================================================
-- from postgresql-2026-09-04_000000.log
-- ==========================================================================
SELECT
	    COUNT(*) FILTER (WHERE value::double precision < 0)  AS pf3_lt_0,
	    COUNT(*) FILTER (WHERE value::double precision = 0)  AS pf3_eq_0,
	    COUNT(*) FILTER (WHERE value::double precision <= 0) AS pf3_le_0
	FROM bronze.telemetries
	WHERE device_id = 'f7715eeb-8c09-4a89-8d2c-74926eb78785'
	  AND key_id = 37;

-- ==========================================================================
-- from postgresql-2026-09-07_000000.log
-- ==========================================================================
WITH recovered AS (
	            WITH base AS (
	        SELECT
	            s.energy_meter_key,
	            s.source_energy_meter_id,
	            s.facility_key,
	            s.zone_key,
	            s.grid_billing_account_key,
	            s.source_timestamp_ms,
	            s.reading_timestamp_utc,
	            s.reading_timestamp_saudi,
	            s.reading_date_saudi,
	    
	            s.active_energy_cumulative_kwh,
	    
	            f.status_kwh,
	            m.meter_label
	    
	        FROM silver.fact_energy_readings_staging s
	    
	        LEFT JOIN silver.fact_energy_readings_flagged f
	            ON f.energy_meter_key = s.energy_meter_key
	           AND f.source_timestamp_ms = s.source_timestamp_ms
	    
	        LEFT JOIN silver.dim_energy_meter_staging m
	            ON m.energy_meter_key = s.energy_meter_key
	    ),
	    
	    /* Get surrounding cumulative kWh readings */
	    ordered AS (
	        SELECT
	            *,
	    
	            LAG(active_energy_cumulative_kwh, 1) OVER (
	                PARTITION BY energy_meter_key
	                ORDER BY reading_timestamp_utc
	            ) AS raw_previous_kwh,
	    
	            LAG(active_energy_cumulative_kwh, 2) OVER (
	                PARTITION BY energy_meter_key
	                ORDER BY reading_timestamp_utc
	            ) AS raw_previous_2_kwh,
	    
	            LEAD(active_energy_cumulative_kwh, 1) OVER (
	                PARTITION BY energy_meter_key
	                ORDER BY reading_timestamp_utc
	            ) AS raw_next_kwh
	    
	        FROM base
	    ),
	    
	    /* Apply the consumption cleaning rules */
	    classified AS (
	        SELECT
	            *,
	    
	            CASE
	    
	                /* -----------------------------------------
	                   Zone 13:
	                   completely excluded from consumption
	                   ----------------------------------------- */
	                WHEN meter_label LIKE 'ZN.13-%'
	                THEN 'EXCLUDED_ZONE13'
	    
	    
	                WHEN active_energy_cumulative_kwh IS NULL
	                THEN 'MISSING_KWH'
	    
	    
	                /* -----------------------------------------
	                   ZN.1-PB.1 installation/startup readings
	    
	                   Valid sequence begins at 46.5
	                   ----------------------------------------- */
	                WHEN meter_label = 'ZN.1-PB.1_child__1_ch3pm'
	                     AND reading_timestamp_utc <
	                         TIMESTAMP '2024-12-10 17:16:15.655'
	                THEN 'STARTUP_EXCLUDED'
	    
	    
	                WHEN meter_label = 'ZN.1-PB.1_child__1_ch3pm'
	                     AND reading_timestamp_utc =
	                         TIMESTAMP '2024-12-10 17:16:15.655'
	                THEN 'STARTUP_BASELINE'
	    
	    
	                /* -----------------------------------------
	                   ZN.4-PB.1 installation/startup readings
	    
	                   Valid sequence begins at 150.4
	                   ----------------------------------------- */
	                WHEN meter_label = 'ZN.4-PB.1_child__1_ch3pm'
	                     AND reading_timestamp_utc <
	                         TIMESTAMP '2024-12-10 21:46:39.010'
	                THEN 'STARTUP_EXCLUDED'
	    
	    
	                WHEN meter_label = 'ZN.4-PB.1_child__1_ch3pm'
	                     AND reading_timestamp_utc =
	                         TIMESTAMP '2024-12-10 21:46:39.010'
	                THEN 'STARTUP_BASELINE'
	    
	    
	                /* -----------------------------------------
	                   Single isolated LOW reading
	    
	                   1218.4 -> 30.5 -> 1218.8
	    
	                   30.5 is ignored
	                   ----------------------------------------- */
	                WHEN raw_previous_kwh IS NOT NULL
	                     AND raw_next_kwh IS NOT NULL
	                     AND active_energy_cumulative_kwh < raw_previous_kwh
	                     AND raw_next_kwh >= raw_previous_kwh
	    
	                THEN 'ISOLATED_LOW_BAD'
	    
	    
	                /* -----------------------------------------
	                   Single isolated HIGH spike
	    
	                   35272.4 -> 94894 -> 35272.8
	    
	                   94894 is ignored
	                   ----------------------------------------- */
	                WHEN raw_previous_kwh IS NOT NULL
	                     AND raw_next_kwh IS NOT NULL
	                     AND active_energy_cumulative_kwh > raw_previous_kwh
	                     AND active_energy_cumulative_kwh > raw_next_kwh
	                     AND raw_next_kwh >= raw_previous_kwh
	    
	                THEN 'ISOLATED_HIGH_BAD'
	    
	    
	                /* -----------------------------------------
	                   Recovery after isolated high spike
	    
	                   35272.4 -> 94894 -> 35272.8
	    
	                   35272.8 is a valid recovery reading
	                   ----------------------------------------- */
	                WHEN raw_previous_2_kwh IS NOT NULL
	                     AND raw_previous_kwh IS NOT NULL
	                     AND raw_previous_kwh > raw_previous_2_kwh
	                     AND raw_previous_kwh > active_energy_cumulative_kwh
	                     AND active_energy_cumulative_kwh >= raw_previous_2_kwh
	    
	                THEN 'HIGH_SPIKE_RECOVERY'
	    
	    
	                /* Any decrement we haven't explained */
	                WHEN raw_previous_kwh IS NOT NULL
	                     AND active_energy_cumulative_kwh < raw_previous_kwh
	    
	                THEN 'UNRESOLVED_DECREMENT'
	    
	    
	                /* Normal increase or flat reading */
	                ELSE 'KEEP'
	    
	            END AS consumption_cleaning_status
	    
	        FROM ordered
	    ),
	    
	    /* Determine whether each meter can be used */
	    meter_status AS (
	        SELECT
	            *,
	    
	            CASE
	    
	                WHEN meter_label LIKE 'ZN.13-%'
	                THEN 'EXCLUDED'
	    
	                WHEN MAX(
	                    CASE
	                        WHEN consumption_cleaning_status =
	                             'UNRESOLVED_DECREMENT'
	                        THEN 1
	                        ELSE 0
	                    END
	                ) OVER (
	                    PARTITION BY energy_meter_key
	                ) = 1
	                THEN 'REVIEW_REQUIRED'
	    
	                ELSE 'ELIGIBLE'
	    
	            END AS meter_consumption_status
	    
	        FROM classified
	    ),
	    
	    /* Keep only trustworthy readings for the consumption sequence */
	    valid_sequence AS (
	        SELECT
	            energy_meter_key,
	            reading_timestamp_utc,
	            active_energy_cumulative_kwh
	    
	        FROM meter_status
	    
	        WHERE meter_consumption_status = 'ELIGIBLE'
	    
	          AND consumption_cleaning_status IN (
	              'KEEP',
	              'STARTUP_BASELINE',
	              'HIGH_SPIKE_RECOVERY'
	          )
	    ),
	    
	    /* Find previous VALID reading instead of previous raw reading */
	    previous_valid AS (
	        SELECT
	            energy_meter_key,
	            reading_timestamp_utc,
	            active_energy_cumulative_kwh,
	    
	            LAG(reading_timestamp_utc) OVER (
	                PARTITION BY energy_meter_key
	                ORDER BY reading_timestamp_utc
	            ) AS previous_valid_timestamp,
	    
	            LAG(active_energy_cumulative_kwh) OVER (
	                PARTITION BY energy_meter_key
	                ORDER BY reading_timestamp_utc
	            ) AS previous_valid_kwh
	    
	        FROM valid_sequence
	    ),
	    
	    /* Calculate actual validated consumption */
	    calculated AS (
	        SELECT
	            *,
	    
	            CASE
	                WHEN previous_valid_kwh IS NULL
	                THEN NULL
	    
	                WHEN active_energy_cumulative_kwh >= previous_valid_kwh
	                THEN active_energy_cumulative_kwh - previous_valid_kwh
	    
	                ELSE NULL
	            END AS validated_kwh_consumption,
	    
	            EXTRACT(
	                EPOCH FROM (
	                    reading_timestamp_utc - previous_valid_timestamp
	                )
	            ) / 60.0 AS gap_minutes
	    
	        FROM previous_valid
	    )
	    
	    SELECT
	        c.energy_meter_key,
	        c.source_energy_meter_id,
	        c.facility_key,
	        c.zone_key,
	        c.grid_billing_account_key,
	    
	        c.meter_label,
	    
	        c.source_timestamp_ms,
	        c.reading_timestamp_utc,
	        c.reading_timestamp_saudi,
	        c.reading_date_saudi,
	    
	        /* Original cumulative meter value */
	        c.active_energy_cumulative_kwh,
	    
	        c.status_kwh,
	    
	        /* Raw surrounding readings for validation */
	        c.raw_previous_kwh,
	        c.raw_next_kwh,
	    
	        /* Why a reading was kept/ignored */
	        c.consumption_cleaning_status,
	    
	        /* Whether this meter contributes to consumption */
	        c.meter_consumption_status,
	    
	        /* Previous trustworthy meter reading */
	        v.previous_valid_timestamp,
	        v.previous_valid_kwh,
	    
	        /* VALUE WE WILL USE FOR CONSUMPTION */
	        v.validated_kwh_consumption,
	    
	        ROUND(v.gap_minutes::numeric, 2) AS gap_minutes,
	    
	        CASE
	            WHEN c.meter_consumption_status = 'EXCLUDED'
	            THEN 'EXCLUDED_METER'
	    
	            WHEN c.meter_consumption_status = 'REVIEW_REQUIRED'
	            THEN 'REVIEW_REQUIRED'
	    
	            WHEN c.consumption_cleaning_status IN (
	                'ISOLATED_LOW_BAD',
	                'ISOLATED_HIGH_BAD',
	                'STARTUP_EXCLUDED',
	                'MISSING_KWH'
	            )
	            THEN 'IGNORED_READING'
	    
	            WHEN v.previous_valid_timestamp IS NULL
	            THEN 'FIRST_VALID_READING'
	    
	            /* Gap is allowed when cumulative counter increases */
	            WHEN v.gap_minutes >= 15
	            THEN 'LONG_GAP'
	    
	            ELSE 'NORMAL_INTERVAL'
	    
	        END AS interval_quality
	    
	    FROM meter_status c
	    
	    LEFT JOIN calculated v
	        ON v.energy_meter_key = c.energy_meter_key
	       AND v.reading_timestamp_utc = c.reading_timestamp_utc
	            )
	            SELECT * FROM recovered
	            WHERE energy_meter_key = ANY($1)

-- ==========================================================================
-- from postgresql-2026-09-07_000000.log
-- ==========================================================================
select fact_energy_readings_flagged from silver
