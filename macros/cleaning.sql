{#- ============================================================================
    Cleaning macros: ONE definition of each rule, used by every staging model.
    All of them are null-safe and never fail a run on bad input (TRY_ functions):
    a bad value becomes NULL, and a test on the column makes sure we still notice.
============================================================================ -#}


{#- Money: '250,000' -> 250000.00 | '$85,000 ' -> 85000.00 | '' -> NULL | NULL -> NULL | 'abc' -> NULL
    Deliberately NOT coalesced to 0: an unpriced deal is a fact the business must see. -#}
{% macro clean_amount(column_name) -%}
    try_to_number(
        nullif(regexp_replace(trim({{ column_name }}::varchar), '[$,[:space:]]', ''), ''),
        18, 2
    )
{%- endmacro %}


{#- Removes stray whitespace around date separators: '2026- 06-10' -> '2026-06-10'.
    Keeps the space between date and time in '2026-06-10 14:00:00'. -#}
{% macro clean_date_string(column_name) -%}
    regexp_replace(trim({{ column_name }}::varchar), '\\s*([-/])\\s*', '\\1')
{%- endmacro %}


{#- Calendar dates (Salesforce Date fields: CloseDate, ActivityDate). No timezone shift.
    Accepts ISO, US m/d/yyyy, or a timestamp (keeps its date part). -#}
{% macro safe_to_date(column_name) -%}
    coalesce(
        try_to_date({{ clean_date_string(column_name) }}, 'YYYY-MM-DD'),
        try_to_date({{ clean_date_string(column_name) }}, 'MM/DD/YYYY'),
        try_to_timestamp_ntz({{ clean_date_string(column_name) }})::date
    )
{%- endmacro %}


{#- Salesforce DateTime fields are UTC. -#}
{% macro safe_to_timestamp_utc(column_name) -%}
    try_to_timestamp_ntz({{ clean_date_string(column_name) }})
{%- endmacro %}


{#- Business date of a UTC DateTime (CreatedDate 2026-06-15 02:00 UTC is 14 June in New York).
    A value with no time part is already a date, so it is not shifted. -#}
{% macro to_business_date(column_name) -%}
    iff(
        length({{ clean_date_string(column_name) }}) <= 10,
        {{ safe_to_date(column_name) }},
        convert_timezone('UTC', '{{ var("business_timezone") }}', {{ safe_to_timestamp_utc(column_name) }})::date
    )
{%- endmacro %}


{#- Join key for free-text picklists: '  Closed   Won ' -> 'closed won'. NULL -> 'unknown'. -#}
{% macro normalize_key(column_name) -%}
    coalesce(lower(regexp_replace(trim({{ column_name }}), '\\s+', ' ')), 'unknown')
{%- endmacro %}


{#- Salesforce soft delete (IsDeleted, recycle bin) OR Fivetran delete marker (row gone from source). -#}
{% macro is_deleted_flag(is_deleted_column='is_deleted') -%}
    (coalesce(try_to_boolean({{ is_deleted_column }}::varchar), false)
     or coalesce(_fivetran_deleted, false))
{%- endmacro %}
