-- Recovered from PostgreSQL server log postgresql-2026-08-03_000000.log.
-- This is the statement text as originally submitted, including
-- its comments. It is in the log because that execution raised an
-- error, usually a user cancellation, so confirm it against the
-- catalog version before relying on it.

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
