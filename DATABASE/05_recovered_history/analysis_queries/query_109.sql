-- Recovered from PostgreSQL server log postgresql-2026-08-04_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
