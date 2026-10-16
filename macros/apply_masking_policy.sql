{#-
  Attach a Snowflake masking policy to a column after the view/table is (re)built.
  Prod only: dev and CI targets get a no-op so they never need the governance schema.
  The policy itself lives in scripts/snowflake_setup.sql (owned by the platform team).
-#}
{% macro apply_masking_policy(column_name, policy_name) -%}
    {%- if target.name == 'prod' -%}
        alter {{ 'view' if model.config.materialized == 'view' else 'table' }} {{ this }}
            modify column {{ column_name }}
            set masking policy {{ target.database }}.governance.{{ policy_name }}
    {%- else -%}
        select 1  -- masking applied in prod only
    {%- endif -%}
{%- endmacro %}
