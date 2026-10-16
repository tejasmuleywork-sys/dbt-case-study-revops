-- Grain: one row per opportunity that has at least one activity.
-- Aggregate BEFORE joining to opportunities, so the opportunity grain can never fan out.
--
-- Why a full-rebuild table on top of an incremental fact (and not incremental itself):
-- "past vs upcoming" depends on as_of_date. A meeting scheduled for next Tuesday becomes a past
-- activity on Wednesday without its row changing, so an incremental aggregate would go stale.
-- Re-aggregating only 3 columns of a columnar table is cheap even at 100M activities.

{{ config(materialized='table') }}

with activities as (
    select
        opportunity_id,
        contact_id,
        activity_type,
        activity_date,
        -- undated activities count as done (they were logged); future-dated ones are scheduled
        not is_deleted and (activity_date <= {{ as_of_date() }} or activity_date is null)  as is_completed,
        not is_deleted
        and activity_date > {{ as_of_date() }}
        and activity_date <= dateadd(
            'day', {{ var('upcoming_activity_horizon_days', 14) }}, {{ as_of_date() }}
        ) as is_upcoming  -- only near-term planned activity affects stale risk
    from {{ ref('int_activities__deduped') }}
    where opportunity_id is not null

)

select
    opportunity_id,
    count_if(is_completed) as activity_count,
    count_if(is_completed and activity_type = 'Call') as call_count,
    count_if(is_completed and activity_type = 'Email') as email_count,
    count_if(is_completed and activity_type = 'Meeting') as meeting_count,
    count_if(is_upcoming) as upcoming_activity_count,
    count(distinct iff(is_completed, contact_id, null)) as contacts_engaged_count,
    min(iff(is_completed, activity_date, null)) as first_activity_date,
    max(iff(is_completed, activity_date, null)) as last_activity_date,
    min(iff(is_upcoming, activity_date, null)) as next_activity_date
from activities
group by opportunity_id
