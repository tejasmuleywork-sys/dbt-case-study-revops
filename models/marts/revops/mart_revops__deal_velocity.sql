-- Role-play ask: "average days from Prospecting to Closed Won by segment".
-- Grain: one row per (segment x opportunity_type x close quarter) PLUS roll-up rows, because
-- medians and averages are NOT additive: a BI tool cannot correctly average quarterly averages.
-- grouping_level tells analysts which rows to use: 'segment' answers the VP's question directly.
-- avg_days_to_win is a blended proxy where history is missing; use the observed-only metric
-- and its coverage count for supported Prospecting-to-current-booking-close comparisons.
-- Reopened bookings and first-vs-final win policy still require discovery.

with won as (

    select
        opportunity_id,
        segment,
        opportunity_type,
        close_fiscal_quarter_label,
        created_date,
        close_date,
        amount_usd
    from {{ ref('fct_opportunities') }}
    where is_won
      and close_date <= {{ as_of_date() }}

),

first_prospecting as (

    select opportunity_id, min(entered_date) as first_prospecting_date
    from {{ ref('fct_opportunity_stage_history') }}
    where stage_order = 1
      and event_source = 'history' -- snapshots establish observation, not true stage-entry time
    group by opportunity_id

),

per_deal as (

    select
        w.*,
        coalesce(p.first_prospecting_date, w.created_date)              as clock_start_date,
        p.first_prospecting_date is null                                as is_start_imputed_from_created,  -- deal skipped Prospecting
        datediff('day', coalesce(p.first_prospecting_date, w.created_date), w.close_date) as days_to_win
    from won as w
    left join first_prospecting as p
        on w.opportunity_id = p.opportunity_id

)

select
    case
        when grouping(segment) = 1                         then 'all'
        when grouping(opportunity_type) = 1                then 'segment'
        when grouping(close_fiscal_quarter_label) = 1      then 'segment_type'
        else 'segment_type_quarter'
    end                                                     as grouping_level,
    coalesce(segment, 'All segments')                       as segment,
    coalesce(opportunity_type, 'All types')                 as opportunity_type,
    coalesce(close_fiscal_quarter_label, 'All quarters')    as close_fiscal_quarter_label,
    count(*)                                                as deals_won,
    round(avg(days_to_win), 1)                              as avg_days_to_win,
    median(days_to_win)                                     as median_days_to_win,
    min(days_to_win)                                        as min_days_to_win,
    max(days_to_win)                                        as max_days_to_win,
    count_if(is_start_imputed_from_created)                 as deals_without_prospecting_stage,
    count_if(not is_start_imputed_from_created)              as observed_prospecting_deals,
    round(avg(iff(not is_start_imputed_from_created, days_to_win, null)), 1)
                                                            as avg_observed_prospecting_to_close_days,
    sum(amount_usd)                                         as won_amount_usd,
    {{ as_of_date() }}                                      as as_of_date

from per_deal
group by grouping sets (
    (segment, opportunity_type, close_fiscal_quarter_label),
    (segment, opportunity_type),
    (segment),
    ()
)
