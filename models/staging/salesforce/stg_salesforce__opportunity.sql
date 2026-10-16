-- Grain : one row per live (non-deleted) Salesforce opportunity, current state.
-- Rules : rename, cast, clean, de-duplicate, drop deletes. No joins, no business aggregation.
-- Mock  : 8 rows in -> 7 rows out (006G is soft-deleted).

with source as (
    select
     *
    from
        {{ source('salesforce', 'opportunity') }}
),

-- 1. De-duplicate FIRST, then filter deletes. If Fivetran re-delivered a row and the newest
--    version is deleted, filtering first would resurrect the older, non-deleted copy.
latest as (
    select
        *
    from
        source
    qualify row_number() over (
        partition by trim(opp_id)
        order by _fivetran_synced desc
    ) = 1
),

renamed as (
    select
        nullif(trim(opp_id), '') as opportunity_id,
        nullif(trim(account_id), '') as account_id,
        nullif(trim(owner_id), '') as opportunity_owner_id,
        trim(regexp_replace(stage_name, '\\s+', ' ')) as stage_name,
        {{ normalize_key('stage_name') }} as stage_key,
        {{ clean_amount('amount') }} as amount,

        {% if var('salesforce__multicurrency_enabled') -%}
        nullif(upper(trim(currency_iso_code)), '') as currency_code,
        {%- else -%}
        '{{ var("corporate_currency", "USD") }}' as currency_code,
        {%- endif %}

        {{ safe_to_date('close_date') }} as close_date,
        coalesce(nullif(trim(type), ''), 'Unknown') as opportunity_type,
        {{ safe_to_timestamp_utc('created_date') }} as created_at_utc,
        {{ to_business_date('created_date') }} as created_date,
        {{ is_deleted_flag('is_deleted') }} as is_deleted,
        _fivetran_synced
    from latest

)

select
    opportunity_id,
    account_id,
    opportunity_owner_id,
    stage_name,
    stage_key,
    amount,
    amount is null as is_amount_missing,   -- 006D: kept + flagged, never $0
    currency_code,
    close_date,
    opportunity_type,
    created_at_utc,
    created_date,

    -- Production: prefer Salesforce IsClosed / IsWon. The extract only has StageName.
    stage_key not in ('closed won', 'closed lost') as is_open,
    stage_key = 'closed won' as is_won,
    stage_key = 'closed lost' as is_lost,

    -- data-quality flags: surfaced to analysts and tests, never silently "fixed"
    close_date < created_date as dq_close_before_created,
    coalesce(amount < 0, false) as dq_negative_amount,
    _fivetran_synced

from renamed
where not is_deleted -- 006G stops here
  and opportunity_id is not null
