-- Recovered from PostgreSQL server log postgresql-2026-07-23_103051.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
