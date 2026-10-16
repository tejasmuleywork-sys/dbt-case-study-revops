-- Grain: one row per live contact.
-- A contact belongs to an ACCOUNT, not an opportunity. Never join contacts to opportunities on
-- account_id: account 001B has two opportunities (006B, 006H), so contact 003B would fan out to 2 rows.
-- Contact <-> opportunity links come only from activities (or OpportunityContactRole).

{{ config(post_hook="{{ apply_masking_policy('email', 'mask_pii_email') }}") }}

with source as (
    select
        *
    from
        {{ source('salesforce', 'contact') }}
),

latest as (
    select
        *
    from
        source
    qualify row_number() over (
        partition by trim(contact_id) 
        order by _fivetran_synced desc) = 1
)

select
    nullif(trim(contact_id), '') as contact_id,
    nullif(trim(account_id), '') as account_id,
    trim(full_name) as full_name,
    trim(title) as title,     -- 'Chief Information Off' is truncated at source: raised with the SF admin
    lower(trim(email)) as email,     -- PII: masked for non-RevOps roles in prod
    {{ safe_to_timestamp_utc('created_date') }} as created_at_utc,
    _fivetran_synced
from latest
where not {{ is_deleted_flag('is_deleted') }}
  and contact_id is not null
