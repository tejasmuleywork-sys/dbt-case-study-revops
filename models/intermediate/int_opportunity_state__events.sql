-- Grain : one row per opportunity per CHANGE of state (stage, amount or close date).
-- Source: Salesforce OPPORTUNITY_HISTORY (or the dbt snapshot when history is not synced)
--         + the opportunity's CURRENT state as a final event.
-- Current rows provide a final observation when native history is missing or delayed.
-- They do not establish when the business change occurred.
-- Feeds: stage history and change metrics; daily pipeline is captured independently.

{{ config(materialized='table') }}   -- shared window calculations

with current_state as (
    select
        opportunity_id,
        stage_key,
        amount,
        close_date,
        coalesce(created_at_utc, created_date::timestamp_ntz)   as created_at_utc,
        created_date,
        _fivetran_synced
    from {{ ref('stg_salesforce__opportunity') }}
),

native_history as (
    {% if var('salesforce__opportunity_history_enabled') -%}
    select
        opportunity_id,
        changed_at_utc as event_at_utc,
        changed_date as event_date,
        stage_key,
        amount,
        close_date,
        'history' as event_source,
        opportunity_history_id as event_source_id
    from {{ ref('stg_salesforce__hist_opportunity') }}
    where changed_at_utc is not null
    {%- else -%}
    select
        null::varchar as opportunity_id,
        null::timestamp_ntz as event_at_utc,
        null::date as event_date,
        null::varchar as stage_key,
        null::number(18,2) as amount,
        null::date as close_date,
        null::varchar as event_source,
        null::varchar as event_source_id
    where false
    {%- endif %}
),

history as (
    select * from native_history
    union all
    select
        s.opportunity_id,
        s.dbt_valid_from::timestamp_ntz as event_at_utc,
        convert_timezone('UTC', '{{ var("business_timezone") }}',
                         s.dbt_valid_from::timestamp_ntz)::date as event_date,
        s.stage_key,
        s.amount,
        s.close_date,
        'snapshot' as event_source,
        s.dbt_scd_id::varchar as event_source_id
    from {{ ref('snap_salesforce__opportunities') }} as s
    where not exists (
        select 1 from native_history as h
        where h.opportunity_id = s.opportunity_id
    )
),

last_history as (
    select opportunity_id, max(event_at_utc) as last_event_at_utc
    from history
    group by opportunity_id
),

current_event as (
    select
        c.opportunity_id,
        -- Observation time is not the business stage-change time.
        -- Never backdate an unobserved current state to creation.
        greatest(
            coalesce(c._fivetran_synced::timestamp_ntz,
                '{{ run_started_at.strftime("%Y-%m-%d %H:%M:%S") }}'::timestamp_ntz),
            coalesce(lh.last_event_at_utc, '1900-01-01'::timestamp_ntz)
        ) as event_at_utc,
        convert_timezone('UTC', '{{ var("business_timezone") }}', event_at_utc)::date as event_date,
        c.stage_key,
        c.amount,
        c.close_date,
        'current' as event_source,
        'current:' || c.opportunity_id as event_source_id
    from current_state as c
    left join last_history as lh on c.opportunity_id = lh.opportunity_id
),

unioned as (
    select * from history
    union all
    select * from current_event
),

with_previous as (
    select
        u.*,
        coalesce(s.stage_order, 99)                             as stage_order,
        coalesce(s.stage_name, 'Unmapped')                      as stage_name,
        coalesce(s.stage_probability, 0)                        as stage_probability,
        coalesce(s.is_closed, u.stage_key in ('closed won', 'closed lost')) as is_closed,
        lag(u.stage_key)  over (partition by u.opportunity_id order by u.event_at_utc, iff(u.event_source = 'current', 1, 0), u.event_source_id) as prev_stage_key,
        lag(u.amount)     over (partition by u.opportunity_id order by u.event_at_utc, iff(u.event_source = 'current', 1, 0), u.event_source_id) as prev_amount,
        lag(u.close_date) over (partition by u.opportunity_id order by u.event_at_utc, iff(u.event_source = 'current', 1, 0), u.event_source_id) as prev_close_date,
        row_number()      over (partition by u.opportunity_id order by u.event_at_utc, iff(u.event_source = 'current', 1, 0), u.event_source_id) as raw_sequence
    from unioned as u
    left join {{ ref('stage_mapping') }} as s
        on u.stage_key = s.stage_key
),

-- Keep only real changes. History also logs probability / forecast-category edits, and the
-- appended current event usually repeats the last history row: both collapse here.
changes as (
    select *
    from with_previous
    where raw_sequence = 1
       or stage_key  is distinct from prev_stage_key
       or amount     is distinct from prev_amount
       or close_date is distinct from prev_close_date
),

sequenced as (
    select
        c.*,
        row_number() over (partition by opportunity_id order by raw_sequence) as event_sequence,
        lag(stage_order) over (partition by opportunity_id order by raw_sequence) as prev_stage_order,
        lag(is_closed)   over (partition by opportunity_id order by raw_sequence) as prev_is_closed,
        lead(event_at_utc) over (partition by opportunity_id order by raw_sequence) as next_event_at_utc
    from changes as c
)

select
    {{ dbt_utils.generate_surrogate_key(['opportunity_id', 'event_sequence']) }}  as opportunity_event_key,
    opportunity_id,
    event_sequence,
    event_source,
    event_source_id,
    event_at_utc,
    event_date,
    next_event_at_utc,
    stage_key,
    stage_name,
    stage_order,
    stage_probability,
    is_closed,
    amount,
    close_date,
    prev_stage_key,
    prev_amount,
    prev_close_date,
    event_sequence = 1 or stage_key is distinct from prev_stage_key as is_stage_entry,
    coalesce(close_date > prev_close_date, false) as is_close_date_pushed,    -- slippage
    coalesce(close_date < prev_close_date, false) as is_close_date_pulled_in,
    coalesce(prev_is_closed and not is_closed, false) as is_reopened,             -- e.g. Closed Lost -> Negotiation
    coalesce(not prev_is_closed and not is_closed
             and stage_order < prev_stage_order, false) as is_stage_regression,     -- Negotiation -> Discovery
    coalesce(amount < prev_amount, false) as is_amount_decrease
from sequenced
