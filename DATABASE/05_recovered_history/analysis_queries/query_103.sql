-- Recovered from PostgreSQL server log postgresql-2026-07-31_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
