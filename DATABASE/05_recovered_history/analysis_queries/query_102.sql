-- Recovered from PostgreSQL server log postgresql-2026-07-31_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
