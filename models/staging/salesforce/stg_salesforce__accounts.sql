-- Grain: one row per live account (current state).

with source as (
    select
        *
    from
        {{ source('salesforce', 'account') }}
),

latest as (
    select
        *
    from
        source
    qualify row_number() over (
        partition by trim(account_id) 
        order by _fivetran_synced desc) = 1
)

select
    nullif(trim(account_id), '') as account_id,
    trim(account_name) as account_name,
    trim(industry) as industry,
    coalesce(nullif(trim(segment), ''), 'Unassigned') as segment,
    {{ clean_amount('arr') }} as arr, -- '250,000' -> 250000.00
    upper(trim(state)) as state_code,
    trim(owner_id) as account_owner_id, -- Account.OwnerId
    {{ safe_to_timestamp_utc('created_date') }} as created_at_utc,
    _fivetran_synced
from latest
where not {{ is_deleted_flag('is_deleted') }}
  and account_id is not null
