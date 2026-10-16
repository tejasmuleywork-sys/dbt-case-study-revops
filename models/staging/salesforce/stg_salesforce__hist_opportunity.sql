-- Grain: one row per logged change to an opportunity (Salesforce OpportunityHistory).
-- Salesforce writes a row when an opportunity is created and whenever stage, amount,
-- close date, probability or forecast category changes. This is what makes deal velocity,
-- slippage and a backfilled daily pipeline history possible.

{{ config(enabled=var('salesforce__opportunity_history_enabled', true)) }}

with source as (
    select
        *
    from
        {{ source('salesforce', 'opportunity_history') }}
),

latest as (
    select
        *
    from
        source
    qualify row_number() over (
        partition by trim(id)
        order by _fivetran_synced desc) = 1
)

select
    nullif(trim(id), '') as opportunity_history_id,
    nullif(trim(opportunity_id), '') as opportunity_id,
    {{ safe_to_timestamp_utc('created_date') }} as changed_at_utc,
    {{ to_business_date('created_date') }} as changed_date,
    trim(regexp_replace(stage_name, '\\s+', ' ')) as stage_name,
    {{ normalize_key('stage_name') }} as stage_key,
    {{ clean_amount('amount') }} as amount,
    {{ safe_to_date('close_date') }} as close_date,
    _fivetran_synced
from latest
where not {{ is_deleted_flag('is_deleted') }}
  and opportunity_id is not null
