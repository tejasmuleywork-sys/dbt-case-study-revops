-- Trust test: the stage mart must match the opportunity fact on BOTH deal count and value.
-- (sums_match on the model checks value; this also catches a dropped zero-value deal.)

with mart as (
    select coalesce(sum(open_opportunity_count), 0) as deals, coalesce(sum(total_pipeline), 0) as value
    from {{ ref('mart_revops__pipeline') }}
),

fact as (
    select count(*) as deals, coalesce(sum(amount_usd), 0) as value
    from {{ ref('fct_opportunities') }}
    where is_open
)

select
    mart.deals as mart_deals, fact.deals as fact_deals,
    mart.value as mart_value, fact.value as fact_value
from mart
cross join fact
where mart.deals <> fact.deals
   or abs(mart.value - fact.value) > 0.01
