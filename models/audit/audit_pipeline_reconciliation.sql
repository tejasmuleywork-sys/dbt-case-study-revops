-- Business audit log. Grain: one row per as_of_date x layer x metric (x period).
-- Every run records the headline numbers at each layer (raw -> staging -> core -> mart).
-- What it answers that nothing else can:
--   * "What did the dashboard say last Monday, and why is it different now?"
--   * "How many rows did we drop in staging, and why?" (deleted, duplicate, unmapped)
--   * "Did last quarter's bookings change after the quarter closed?" (restatement alarm test)
-- Re-running a day replaces that day's rows (delete+insert): reruns never double count.
-- full_refresh=false: the log is history, it must survive a careless --full-refresh.

{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='as_of_date',
        full_refresh=false,
        on_schema_change='append_new_columns'
    )
}}

with raw_opportunities as (
    select
        count(*) as raw_rows,
        count(distinct trim(opp_id)) as raw_distinct_ids,
        count_if({{ is_deleted_flag('is_deleted') }}) as raw_deleted_rows
    from {{ source('salesforce', 'opportunity') }}
),

fct as (
    select
        count(*) as live_opportunities,
        count_if(is_open) as open_opportunities,
        coalesce(sum(iff(is_open, amount_usd, 0)), 0) as open_pipeline_usd,
        coalesce(sum(iff(is_open, weighted_amount_usd, 0)), 0) as weighted_pipeline_usd,
        count_if(is_open and is_amount_missing) as unpriced_open_opportunities,
        count_if(is_stage_unmapped) as unmapped_stage_opportunities,
        count_if(account_name = 'Unknown account') as orphan_account_opportunities,
        count_if(opportunity_owner_name = 'Unknown owner') as unknown_owner_opportunities,
        count_if(dq_close_before_created) as close_before_created_opportunities
    from {{ ref('fct_opportunities') }}

),

bookings as (
    select
        max(iff(is_current_quarter, fiscal_quarter_label, null)) as current_quarter_label,
        max(iff(is_current_quarter, bookings_usd, null)) as bookings_current_quarter_usd,
        max(iff(is_current_quarter, prior_quarter_bookings_usd, null)) as bookings_prior_quarter_usd
    from {{ ref('mart_revops__bookings_qoq') }}
    where is_rollup
),

prior_quarter_label as (
    select fiscal_quarter_label
    from {{ ref('mart_revops__bookings_qoq') }}
    where is_rollup
    qualify row_number() over (order by quarter_start_date desc) = 2
),

at_risk as (
    select count(*) as at_risk_opportunities, coalesce(sum(amount_usd), 0) as at_risk_pipeline_usd
    from {{ ref('mart_revops__at_risk_deals') }}
),

activities as (
    select
        count(*) as activity_rows,
        count_if(is_deleted) as deleted_activity_rows,
        count_if(not is_deleted and activity_date > {{ as_of_date() }}) as future_dated_activities,
        count_if(not is_deleted and activity_date is null) as undated_activities
    from {{ ref('int_activities__deduped') }}
),

metrics as (

    select 'raw' as layer,
    'opportunity_rows' as metric_name,
    null as metric_period,
    raw_rows::number(38,2) as metric_value
    from raw_opportunities
    union all select 'raw',  'opportunity_deleted_rows', null, raw_deleted_rows  from raw_opportunities
    union all select 'raw',  'opportunity_duplicate_rows', null, raw_rows - raw_distinct_ids from raw_opportunities
    union all select 'core', 'live_opportunities', null, live_opportunities from fct
    union all select 'core', 'open_opportunities', null, open_opportunities from fct
    union all select 'core', 'open_pipeline_usd', null, open_pipeline_usd from fct
    union all select 'core', 'weighted_pipeline_usd', null, weighted_pipeline_usd from fct
    union all select 'core', 'unpriced_open_opportunities', null, unpriced_open_opportunities from fct
    union all select 'core', 'unmapped_stage_opportunities', null, unmapped_stage_opportunities from fct
    union all select 'core', 'orphan_account_opportunities', null, orphan_account_opportunities from fct
    union all select 'core', 'unknown_owner_opportunities', null, unknown_owner_opportunities from fct
    union all select 'core', 'close_before_created_opportunities',null, close_before_created_opportunities from fct
    union all select 'core', 'activity_rows', null, activity_rows from activities
    union all select 'core', 'deleted_activity_rows', null, deleted_activity_rows from activities
    union all select 'core', 'future_dated_activities', null, future_dated_activities from activities
    union all select 'core', 'undated_activities', null, undated_activities from activities
    union all select 'mart', 'bookings_current_quarter_usd', current_quarter_label, bookings_current_quarter_usd from bookings
    union all select 'mart', 'bookings_prior_quarter_usd', (select fiscal_quarter_label from prior_quarter_label), bookings_prior_quarter_usd from bookings
    union all select 'mart', 'at_risk_opportunities', null, at_risk_opportunities from at_risk
    union all select 'mart', 'at_risk_pipeline_usd', null, at_risk_pipeline_usd  from at_risk

)

select
    {{ as_of_date() }} as as_of_date,
    layer,
    metric_name,
    metric_period::varchar as metric_period,
    metric_value::number(38,2) as metric_value,
    '{{ invocation_id }}' as dbt_invocation_id,
    sysdate() as loaded_at_utc
from metrics
