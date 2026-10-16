{% snapshot snap_salesforce__accounts %}

{{
    config(
        unique_key='account_id',
        strategy='check',
        check_cols=['account_name', 'account_owner_id', 'segment', 'industry', 'state_code', 'arr'],
        invalidate_hard_deletes=true
    )
}}

-- SCD Type 2 for accounts: when an account is reassigned mid-quarter, the old row is closed
-- (dbt_valid_to) and a new one opens. All selected business attributes are tracked.
-- If ARR is high-frequency at production scale, design a separate account-metrics fact.
-- With a reliable last-modified column (Salesforce SystemModstamp) use strategy='timestamp':
-- cheaper (no column comparison) and records the true change time.
-- dbt 1.9+: invalidate_hard_deletes is spelled hard_deletes='invalidate'.

select
    account_id,
    account_name,
    industry,
    segment,
    state_code,
    arr,
    account_owner_id
from {{ ref('stg_salesforce__accounts') }}

{% endsnapshot %}
