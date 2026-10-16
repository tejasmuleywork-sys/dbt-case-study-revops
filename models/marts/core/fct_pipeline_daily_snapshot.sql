-- Observed daily pipeline, not reconstructed history.
-- Model name stays stable for ref(); a NEW physical alias isolates legacy reconstructed rows.
-- Re-running today replaces today's observation, including a zero-open-deal day.
-- Historical observations are retained after later opportunity deletion.
{{
    config(
        alias='fct_pipeline_daily_observed',
        materialized='incremental',
        incremental_strategy='observed_daily_pipeline',
        unique_key=['snapshot_date', 'opportunity_id'],
        tmp_relation_type='table',
        full_refresh=false,
        on_schema_change='fail'
    )
}}

{% if var('as_of_date', none) %}
    {% do exceptions.raise_compiler_error(
        'Observed daily capture rejects as_of_date overrides. Select current-state marts only for dated examples.'
    ) %}
{% endif %}
{% if var('backfill_start_date', none) or var('backfill_end_date', none) %}
    {% do exceptions.raise_compiler_error('Observed daily capture cannot backfill unobserved history.') %}
{% endif %}

select
    {{ as_of_date() }} as snapshot_date,
    opportunity_id,
    account_id,
    opportunity_owner_id,
    segment,
    opportunity_type,
    stage_name,
    stage_order,
    amount_usd,
    weighted_amount_usd,
    is_amount_missing,
    close_date,
    datediff('day', {{ as_of_date() }}, close_date) as days_to_close,
    close_date < {{ as_of_date() }} as is_past_close_date,
    '{{ invocation_id }}' as dbt_invocation_id,
    sysdate() as loaded_at_utc
from {{ ref('fct_opportunities') }}
where is_open
