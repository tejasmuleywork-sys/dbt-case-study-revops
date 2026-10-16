-- Grain: one row per opportunity per stage ENTERED (a "stage visit").
-- Answers the role-play ask: "average days from Prospecting to Closed Won by segment".
-- A deal that goes Negotiation -> Discovery -> Negotiation has two Negotiation visits
-- (stage_visit_number 1 and 2), so re-entries are counted, never double-timed.

with entries as (
    select
        opportunity_id,
        event_sequence,
        event_source,
        stage_key,
        stage_name,
        stage_order,
        is_closed,
        event_date as entered_date,
        lead(event_date) over (partition by opportunity_id order by event_sequence) as exited_date
    from {{ ref('int_opportunity_state__events') }}
    where is_stage_entry
      and event_date <= {{ as_of_date() }}
)

select
    {{ dbt_utils.generate_surrogate_key(['e.opportunity_id', 'e.event_sequence']) }} as stage_visit_key,
    e.opportunity_id,
    o.segment,
    o.opportunity_type,
    o.opportunity_owner_id,
    e.event_source,
    e.stage_key,
    e.stage_name,
    e.stage_order,
    e.entered_date,
    e.exited_date,
    datediff('day', e.entered_date, coalesce(e.exited_date, {{ as_of_date() }})) as days_in_stage,
    e.exited_date is null as is_current_stage,
    row_number() over (
        partition by e.opportunity_id, e.stage_key
        order by e.event_sequence
    ) as stage_visit_number

from entries as e
inner join {{ ref('fct_opportunities') }} as o
    on e.opportunity_id = o.opportunity_id
