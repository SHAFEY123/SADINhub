-- Recovered from PostgreSQL server log postgresql-2026-07-23_103051.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
