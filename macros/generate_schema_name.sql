{#-
  prod : models land in exactly the schema they ask for (ANALYTICS.REVOPS, ANALYTICS.CORE ...)
  dev/CI: models land in <your schema>_<custom schema> (ANALYTICS_DEV.DBT_TEJAS_REVOPS ...)
  so engineers and CI runs never overwrite production or each other.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- set default_schema = target.schema -%}
    {%- if custom_schema_name is none -%}
        {{ default_schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ default_schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
