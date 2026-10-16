-- Q1: "What is our open pipeline by stage?"
-- Grain: one row per stage that has open deals. Contracted: the BI dashboard depends on these
-- exact column names and types, so explicit casts make the contract deterministic.
-- Mock answer (as of 2026-10-16): Negotiation total 85,000 / weighted 63,750; all stages 500,000 / 242,750.

select
    stage_order::number(3,0)                                    as stage_order,
    stage_name::varchar                                         as stage_name,
    forecast_category::varchar                                  as forecast_category,
    count(*)::number(18,0)                                      as open_opportunity_count,
    count_if(is_amount_missing)::number(18,0)                   as unpriced_opportunity_count,   -- 006D shows here, not as $0
    coalesce(sum(amount_usd), 0)::number(38,2)                  as total_pipeline,
    coalesce(sum(weighted_amount_usd), 0)::number(38,2)         as weighted_pipeline,
    {{ as_of_date() }}                                          as as_of_date

from {{ ref('fct_opportunities') }}
where is_open
group by stage_order, stage_name, forecast_category
