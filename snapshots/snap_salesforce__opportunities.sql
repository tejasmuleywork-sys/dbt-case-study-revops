{% snapshot snap_salesforce__opportunities %}

{{
    config(
        unique_key='opportunity_id',
        strategy='check',
        check_cols=['account_id', 'stage_key', 'stage_name', 'amount', 'currency_code', 'close_date', 'opportunity_owner_id', 'opportunity_type'],
        invalidate_hard_deletes=true
    )
}}

-- SCD Type 2 versions of each opportunity, captured by dbt every run.
-- Why keep this even though OPPORTUNITY_HISTORY exists:
--   1. OpportunityHistory does not log OWNER or TYPE changes; this captures observed OWNER/TYPE versions, not guaranteed owner-at-close history.
--   2. It is the fallback source for int_opportunity_state__events if history is ever not synced.
--   3. A soft-deleted or hard-deleted deal gets its version closed (invalidate_hard_deletes),
--      so we know WHEN it disappeared — useful when a closed quarter's bookings change.

select
    opportunity_id,
    account_id,
    opportunity_owner_id,
    stage_key,
    stage_name,
    amount,
    currency_code,
    close_date,
    opportunity_type
from {{ ref('stg_salesforce__opportunity') }}

{% endsnapshot %}
