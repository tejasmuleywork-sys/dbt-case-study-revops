{#-
  One business "today" for the whole dbt invocation.

  Default: the run's start time (run_started_at, UTC) converted to the business timezone.
  Every model in the run gets the SAME date, even if the run crosses midnight, so the
  pipeline mart, the at-risk mart and the daily snapshot can never disagree about "today".

  Override to replay or reproduce a past Monday:
      dbt build --vars '{as_of_date: 2026-10-16}'
-#}
{% macro as_of_date() -%}
    {%- set override = var('as_of_date', none) -%}
    {%- if override -%}
        '{{ override }}'::date
    {%- else -%}
        convert_timezone(
            'UTC',
            '{{ var("business_timezone") }}',
            '{{ run_started_at.strftime("%Y-%m-%d %H:%M:%S") }}'::timestamp_ntz
        )::date
    {%- endif -%}
{%- endmacro %}
