-- Restatement alarm (warn). Last quarter's bookings should not change once the quarter is over.
-- If yesterday's audit row and today's disagree for the SAME closed quarter, someone back-dated a
-- close date, re-opened or deleted a won deal, or edited its amount. RevOps hears about it from
-- us, before Finance notices a different number in a board deck.

{{ config(severity='warn') }}

with history as (

    select
        as_of_date,
        metric_period,
        metric_value,
        lag(metric_value) over (partition by metric_period order by as_of_date) as previous_value,
        lag(as_of_date)   over (partition by metric_period order by as_of_date) as previous_as_of_date
    from {{ ref('audit_pipeline_reconciliation') }}
    where metric_name = 'bookings_prior_quarter_usd'

)

select *
from history
where as_of_date = {{ as_of_date() }}
  and previous_value is not null
  and abs(metric_value - previous_value) > 0.01
