-- Consistency test: today's OBSERVED slice of the daily pipeline must equal the live fact.
-- If the snapshot logic and fct_opportunities ever disagree, this fails,
-- instead of the trend chart and the pipeline mart quietly showing different numbers.
-- Skipped on a replay (as_of_date in the past): that day is reconstructed, not observed,
-- and is allowed to differ from today's fact (deals have moved since).
{%- set w = pipeline_snapshot_window() %}
{% if w.mode == 'replay' %}

select 1 as skipped where false

{% else %}

with snapshot_today as (
    select count(*) as deals, coalesce(sum(amount_usd), 0) as value
    from {{ ref('fct_pipeline_daily_snapshot') }}
    where snapshot_date = {{ as_of_date() }}
      and coalesce(snapshot_source, 'observed') = 'observed'
),

fact as (
    select count(*) as deals, coalesce(sum(amount_usd), 0) as value
    from {{ ref('fct_opportunities') }}
    where is_open
)

select s.deals as snapshot_deals, f.deals as fact_deals, s.value as snapshot_value, f.value as fact_value
from snapshot_today as s
cross join fact as f
where s.deals <> f.deals
   or abs(s.value - f.value) > 0.01

{% endif %}