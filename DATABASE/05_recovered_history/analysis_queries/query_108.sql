-- Recovered from PostgreSQL server log postgresql-2026-08-04_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
