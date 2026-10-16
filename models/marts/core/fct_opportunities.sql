-- Grain: one row per live opportunity (current state). The central fact for pipeline,
-- bookings, risk and velocity. Full rebuild every run: Salesforce opportunity volume
-- should be benchmarked at representative volume; a full rebuild does not depend on a watermark for a
-- late update or a delete. Incremental is used only where volume demands it.

-- No explicit clustering at case-study scale; add only after measuring pruning and cost.

select
    e.opportunity_id,
    e.account_id,
    e.account_name,
    e.segment,
    e.industry,
    e.state_code,
    e.account_owner_id,
    e.opportunity_owner_id,
    e.opportunity_owner_name,

    e.stage_name,
    e.stage_order,
    e.stage_probability,
    e.forecast_category,
    e.is_stage_unmapped,
    e.opportunity_type,
    e.is_open,
    e.is_won,
    e.is_lost,

    e.amount,
    e.currency_code,
    e.fx_rate_to_corporate,
    e.is_fx_rate_missing,
    e.amount_usd,
    e.weighted_amount_usd,
    e.is_amount_missing,

    e.created_date,
    e.close_date,
    d.fiscal_quarter_start_date as close_fiscal_quarter_start_date,
    d.fiscal_quarter_label as close_fiscal_quarter_label,
    d.day_of_fiscal_quarter as close_day_of_fiscal_quarter,
    e.days_open,
    e.current_stage_entered_date,
    e.days_in_current_stage,

    e.activity_count,
    e.call_count,
    e.email_count,
    e.meeting_count,
    e.upcoming_activity_count,
    e.contacts_engaged_count,
    e.last_activity_date,
    e.next_activity_date,
    e.days_since_last_activity,

    e.close_date_push_count,
    e.close_date_pushes_last_30d,
    e.stage_regression_count,
    e.reopen_count,

    e.dq_close_before_created,
    e.dq_negative_amount,
    e.dq_amount_outlier,
    e.as_of_date

from {{ ref('int_opportunities__enriched') }} as e
left join {{ ref('dim_date') }} as d
    on e.close_date = d.date_day
