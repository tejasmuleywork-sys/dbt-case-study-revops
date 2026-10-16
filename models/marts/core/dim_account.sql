-- Grain: one row per account per version (SCD Type 2, from the dbt snapshot).
-- Join patterns for analysts:
--   current attributes            -> where is_current
--   historical attribution -> use an agreed event timestamp and [valid_from, valid_to).
-- Date-only boundaries lose within-day changes. Pre-capture attributes are unknown.
-- Current marts deliberately use current attributes, not this historical join.
-- The account owner comes from Account.OwnerId. It is never inferred from opportunities:
-- 001C can have deals owned by 005B and 005C at the same time; those are opportunity facts.

select
    {{ dbt_utils.generate_surrogate_key(['account_id', 'dbt_valid_from']) }} as account_key,
    account_id,
    account_name,
    industry,
    segment,
    state_code,
    arr,
    account_owner_id,
    dbt_valid_from as valid_from,
    coalesce(dbt_valid_to, '9999-12-31'::timestamp_ntz) as valid_to,
    convert_timezone('UTC', '{{ var("business_timezone") }}', dbt_valid_from)::date as valid_from_date,
    coalesce(convert_timezone('UTC', '{{ var("business_timezone") }}', dbt_valid_to)::date,
             '9999-12-31'::date) as valid_to_date,
    dbt_valid_to is null as is_current
from {{ ref('snap_salesforce__accounts') }}
