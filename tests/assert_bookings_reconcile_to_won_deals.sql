-- Trust test: the bookings mart (per-type rows, roll-ups excluded) must add up to every
-- Closed Won deal dated up to today. Catches a broken quarter spine or a type that vanished.

with mart as (
    select coalesce(sum(bookings_usd), 0) as value,
    coalesce(sum(deals_won), 0) as deals
    from {{ ref('mart_revops__bookings_qoq') }}
    where not is_rollup
),

rollup_rows as (
    select coalesce(sum(bookings_usd), 0) as value
    from {{ ref('mart_revops__bookings_qoq') }}
    where is_rollup
),

fact as (
    select coalesce(sum(amount_usd), 0) as value, count(*) as deals
    from {{ ref('fct_opportunities') }}
    where is_won
      and close_date <= {{ as_of_date() }}
)

select
    mart.value as mart_value, rollup_rows.value as rollup_value, fact.value as fact_value,
    mart.deals as mart_deals, fact.deals as fact_deals
from mart
cross join rollup_rows
cross join fact
where abs(mart.value - fact.value) > 0.01
   or abs(rollup_rows.value - fact.value) > 0.01
   or mart.deals <> fact.deals
