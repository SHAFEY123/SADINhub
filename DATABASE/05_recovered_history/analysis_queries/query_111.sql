-- Recovered from PostgreSQL server log postgresql-2026-08-04_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
