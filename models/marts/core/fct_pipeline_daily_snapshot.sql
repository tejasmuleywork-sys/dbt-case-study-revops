-- Grain: one row per open opportunity per business day.
-- Two kinds of rows, labelled in snapshot_source:
--   observed               written by the daily run from fct_opportunities: what the pipeline really was that day
--   reconstructed          rebuilt for past days from int_opportunity_state__events (Salesforce OpportunityHistory,
--                          or the dbt snapshot where history is missing): stage / amount / close date as of that day
--   reconstructed_assumed  a day BEFORE a deal's first known state, filled with that first state
--                          (only when var backfill_anchor_first_known_state = true)
-- Observed rows are never overwritten by a backfill: an observed day is the source of truth for that day.
-- What a run writes (today, a date range, or both) is decided by macros/pipeline_snapshot_window.sql.
-- Writes go through the observed_daily_pipeline MERGE: one atomic statement per run, idempotent,
-- and deals that are no longer open on a re-run day are removed (tombstones), so zero-deal days are correct.
{{
    config(
        alias='fct_pipeline_daily_observed',
        materialized='incremental',
        incremental_strategy='observed_daily_pipeline',
        unique_key=['snapshot_date', 'opportunity_id'],
        tmp_relation_type='table',
        full_refresh=false,
        on_schema_change='append_new_columns',
        cluster_by=['snapshot_date']
    )
}}

{%- set w = pipeline_snapshot_window() -%}
{%- set anchor = var('backfill_anchor_first_known_state', false) -%}

{#- Older tables were created before snapshot_source existed: treat their rows as observed. -#}
{%- set has_source_col = false -%}
{%- if is_incremental() and execute -%}
    {%- set existing_cols = adapter.get_columns_in_relation(this) | map(attribute='name') | map('lower') | list -%}
    {%- set has_source_col = 'snapshot_source' in existing_cols -%}
{%- endif %}

with live_deals as (

    -- Live (not deleted) opportunities. Deleted deals drop out of reconstructed history too;
    -- observed rows written before the deletion are kept.
    select *
    from {{ ref('fct_opportunities') }}

),

observed as (

    select
        {{ as_of_date() }}          as snapshot_date,
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
        'observed'                  as snapshot_source
    from live_deals
    where is_open
      {% if not w.observe_today %} and false {% endif %}

),

spine as (

    select date_day as snapshot_date
    from {{ ref('dim_date') }}
    {% if w.has_rec %}
    where date_day between '{{ w.rec_start }}'::date and '{{ w.rec_end }}'::date
      {% if is_incremental() %}
      -- never overwrite a day that was actually observed
      and date_day not in (
          select distinct snapshot_date
          from {{ this }}
          where {{ "coalesce(snapshot_source, 'observed') = 'observed'" if has_source_col else "true" }}
      )
      {% endif %}
    {% else %}
    where false
    {% endif %}

),

-- Each state is valid from its event_date until the next event's date (exclusive).
-- Several changes on one day: only the last one of the day survives (earlier ones get an empty interval).
state_intervals as (

    select
        e.opportunity_id,
        e.event_sequence,
        e.event_date,
        {% if anchor -%}
        iff(e.event_sequence = 1, least(o.created_date, e.event_date), e.event_date)
        {%- else -%}
        e.event_date
        {%- endif %}                                                    as valid_from_date,
        coalesce(
            lead(e.event_date) over (partition by e.opportunity_id order by e.event_sequence),
            '9999-12-31'::date
        )                                                               as valid_to_date,
        e.stage_name,
        e.stage_order,
        e.stage_probability,
        e.is_closed,
        e.amount,
        e.close_date
    from {{ ref('int_opportunity_state__events') }} as e
    inner join live_deals as o
        on e.opportunity_id = o.opportunity_id

),

-- Attributes that OpportunityHistory does NOT track, taken as of the day where we have SCD2 versions
-- (dbt snapshots, from their go-live), otherwise today's value.
opp_versions as (

    select
        opportunity_id,
        opportunity_owner_id,
        opportunity_type,
        convert_timezone('UTC', '{{ var("business_timezone") }}', dbt_valid_from)::date             as valid_from_date,
        coalesce(convert_timezone('UTC', '{{ var("business_timezone") }}', dbt_valid_to)::date,
                 '9999-12-31'::date)                                                                as valid_to_date
    from {{ ref('snap_salesforce__opportunities') }}

),

reconstructed as (

    select
        d.snapshot_date,
        o.opportunity_id,
        o.account_id,
        coalesce(ov.opportunity_owner_id, o.opportunity_owner_id)      as opportunity_owner_id,
        coalesce(a.segment, o.segment)                                  as segment,
        coalesce(ov.opportunity_type, o.opportunity_type)              as opportunity_type,
        s.stage_name,
        s.stage_order,
        s.amount * o.fx_rate_to_corporate                               as amount_usd,     -- today's FX rate
        s.amount * o.fx_rate_to_corporate * s.stage_probability         as weighted_amount_usd,
        s.amount is null                                                as is_amount_missing,
        s.close_date,
        iff(d.snapshot_date < s.event_date, 'reconstructed_assumed', 'reconstructed') as snapshot_source
    from spine as d
    inner join state_intervals as s
        on  d.snapshot_date >= s.valid_from_date
        and d.snapshot_date <  s.valid_to_date
    inner join live_deals as o
        on  s.opportunity_id = o.opportunity_id
        and o.created_date <= d.snapshot_date                          -- not yet created -> not in pipeline
    left join {{ ref('dim_account') }} as a
        on  o.account_id = a.account_id
        and d.snapshot_date >= a.valid_from_date
        and d.snapshot_date <  a.valid_to_date
    left join opp_versions as ov
        on  o.opportunity_id = ov.opportunity_id
        and d.snapshot_date >= ov.valid_from_date
        and d.snapshot_date <  ov.valid_to_date
    where not s.is_closed

),

unioned as (

    select * from observed
    union all
    select * from reconstructed

)

select
    snapshot_date,
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
    datediff('day', snapshot_date, close_date)                         as days_to_close,
    close_date < snapshot_date                                          as is_past_close_date,
    '{{ invocation_id }}'                                               as dbt_invocation_id,
    sysdate()                                                           as loaded_at_utc,
    snapshot_source
from unioned