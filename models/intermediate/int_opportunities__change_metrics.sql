-- One row per opportunity. Stage timing remains NULL when the latest entry is unverified.
with events as (
    select * from {{ ref('int_opportunity_state__events') }}
    where event_date <= {{ as_of_date() }}
),
metrics as (
    select
        opportunity_id,
        count_if(is_close_date_pushed) as close_date_push_count,
        count_if(is_close_date_pushed and event_date > dateadd('day', -30, {{ as_of_date() }}))
            as close_date_pushes_last_30d,
        count_if(is_stage_regression) as stage_regression_count,
        count_if(is_reopened) as reopen_count,
        count_if(is_amount_decrease) as amount_decrease_count,
        min(event_date) as first_event_date
    from events
    group by opportunity_id
),
latest_stage_entry as (
    select
        opportunity_id,
        -- Native history provides stage entry; a snapshot only provides first observation.
        -- Do not mix these two clocks in the confirmed stalled-stage metric.
        iff(event_source = 'history', event_date, null) as current_stage_entered_date
    from events
    where is_stage_entry
    qualify row_number() over (partition by opportunity_id order by event_sequence desc) = 1
)
select m.*, s.current_stage_entered_date
from metrics as m
left join latest_stage_entry as s on m.opportunity_id = s.opportunity_id
