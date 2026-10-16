-- Consistency test: today's slice of the reconstructed daily snapshot must equal the live fact.
-- If OPPORTUNITY_HISTORY and the current opportunity table ever disagree, this fails,
-- instead of the trend chart and the pipeline mart quietly showing different numbers.

with snapshot_today as (
    select count(*) as deals, coalesce(sum(amount_usd), 0) as value
    from {{ ref('fct_pipeline_daily_snapshot') }}
    where snapshot_date = {{ as_of_date() }}
),

fact as (
    select count(*) as deals, coalesce(sum(amount_usd), 0) as value
    from {{ ref('fct_opportunities') }}
    where is_open
      and created_date <= {{ as_of_date() }}
)

select s.deals as snapshot_deals, f.deals as fact_deals, s.value as snapshot_value, f.value as fact_value
from snapshot_today as s
cross join fact as f
where s.deals <> f.deals
   or abs(s.value - f.value) > 0.01
