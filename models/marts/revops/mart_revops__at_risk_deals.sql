-- Q2: "Which deals are at risk of slipping?"
-- Grain: one row per open opportunity that trips at least one rule.
-- Rule-based and transparent on purpose: a rep must be able to see WHY a deal is flagged.
-- Thresholds are dbt vars agreed with the RevOps VP (dbt_project.yml), not hard-coded.
-- Mock answer on 2026-10-16: all four are past close and idle; stage age is unknown without native history.

with open_deals as (
    select * from {{ ref('fct_opportunities') }}
    where is_open
),

flagged as (
    select
        *,
        close_date < {{ as_of_date() }} as is_past_close_date,
        close_date is null as is_missing_close_date,
        (
            (last_activity_date is not null
             and days_since_last_activity > {{ var('stale_activity_days') }})
            or
            (last_activity_date is null
             and days_open > {{ var('new_deal_activity_grace_days', 7) }})
        ) and upcoming_activity_count = 0 as is_stale,       -- a booked meeting next week is not "idle"
        is_amount_missing and stage_order >= 3 as is_unpriced_late_stage,
        datediff('day', {{ as_of_date() }}, close_date)
            between 0 and {{ var('closing_soon_days') }}
            and stage_order <= 2 as is_early_stage_closing_soon,
        close_date_push_count >= {{ var('close_date_push_threshold') }} as is_repeatedly_pushed,
        stage_regression_count > 0 as is_stage_regressed,
        coalesce(days_in_current_stage > {{ var('stalled_stage_days') }}, false) as is_stalled_in_stage
    from open_deals

),

scored as (
    select
        *,
        array_construct_compact(
            iff(is_past_close_date, 'PAST_CLOSE_DATE', null),
            iff(is_missing_close_date, 'NO_CLOSE_DATE', null),
            iff(is_stale, 'NO_RECENT_ACTIVITY', null),
            iff(is_unpriced_late_stage, 'NO_AMOUNT_LATE_STAGE', null),
            iff(is_early_stage_closing_soon, 'EARLY_STAGE_CLOSING_SOON', null),
            iff(is_repeatedly_pushed, 'CLOSE_DATE_PUSHED_REPEATEDLY', null),
            iff(is_stage_regressed, 'STAGE_MOVED_BACKWARDS', null),
            iff(is_stalled_in_stage, 'STALLED_IN_STAGE', null)
        ) as risk_reasons
    from flagged

)

select
    opportunity_id,
    account_name,
    segment,
    opportunity_owner_name,
    stage_name,
    stage_order,
    amount_usd,
    weighted_amount_usd,
    close_date,
    days_open,
    days_in_current_stage,
    activity_count,
    last_activity_date,
    days_since_last_activity,
    next_activity_date,
    close_date_push_count,
    is_past_close_date,
    is_missing_close_date,
    is_stale,
    is_unpriced_late_stage,
    is_early_stage_closing_soon,
    is_repeatedly_pushed,
    is_stage_regressed,
    is_stalled_in_stage,
    risk_reasons,
    array_to_string(risk_reasons, ', ') as risk_reasons_text,  -- for BI tools without arrays
    array_size(risk_reasons) as risk_score,
    {{ as_of_date() }} as as_of_date
from scored
where array_size(risk_reasons) > 0
