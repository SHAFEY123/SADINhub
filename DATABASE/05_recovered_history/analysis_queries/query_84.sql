-- Recovered from PostgreSQL server log postgresql-2026-07-30_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
