-- Q3: "How does this quarter's bookings compare to last quarter?"
-- Grain: one row per fiscal quarter x booking type, plus an 'All types' roll-up row per quarter
-- (is_rollup = true; filter it out before summing across types).
--
-- Three traps this handles:
--   1. Quarter spine: a quarter with no wins still has a row with 0, so LAG() compares to the
--      true previous quarter (without it, Q2 2026 would be compared with Q1 2025).
--   2. Like-for-like: mid-quarter, "this quarter so far" is compared with the previous quarter
--      up to the SAME day of quarter, not with the whole previous quarter.
--   3. Prior = 0: % change is NULL (undefined), not 0% and not infinity.
-- Bookings = Closed Won amount (corporate currency) by close date. Won deals dated in the
-- future are excluded and flagged by a test: they are a data-entry problem, not bookings.

with as_of as (

    select fiscal_quarter_start_date as current_quarter_start, day_of_fiscal_quarter as current_day_of_quarter
    from {{ ref('dim_date') }}
    where date_day = {{ as_of_date() }}

),

won as (

    select
        close_fiscal_quarter_start_date                         as quarter_start_date,
        opportunity_type,
        close_day_of_fiscal_quarter,
        coalesce(amount_usd, 0)                                 as amount_usd
    from {{ ref('fct_opportunities') }}
    where is_won
      and close_date <= {{ as_of_date() }}

),

bounds as (

    select
        least(
            coalesce((select min(quarter_start_date) from won), current_quarter_start),
            dateadd('month', -3, current_quarter_start)::date
        ) as first_quarter_start, -- include prior quarter even when it had zero wins
        current_quarter_start
    from as_of

),

quarters as (

    select distinct d.fiscal_quarter_start_date as quarter_start_date, d.fiscal_quarter_label
    from {{ ref('dim_date') }} as d
    cross join bounds as b
    where d.fiscal_quarter_start_date between b.first_quarter_start and b.current_quarter_start

),

types as (

    select distinct opportunity_type, false as is_rollup from {{ ref('fct_opportunities') }}
    union all
    select 'All types', true

),

aggregated as (

    select
        w.quarter_start_date,
        iff(grouping(w.opportunity_type) = 1, 'All types', w.opportunity_type)      as opportunity_type,
        sum(w.amount_usd)                                                           as bookings_usd,
        count(*)                                                                    as deals_won,
        sum(iff(w.close_day_of_fiscal_quarter <= a.current_day_of_quarter, w.amount_usd, 0))
                                                                                    as bookings_to_same_day_usd
    from won as w
    cross join as_of as a
    group by grouping sets ((w.quarter_start_date, w.opportunity_type), (w.quarter_start_date))

),

spine as (

    select
        q.quarter_start_date,
        q.fiscal_quarter_label,
        t.opportunity_type,
        t.is_rollup,
        coalesce(a.bookings_usd, 0)                             as bookings_usd,
        coalesce(a.deals_won, 0)                                as deals_won,
        coalesce(a.bookings_to_same_day_usd, 0)                 as bookings_to_same_day_usd
    from quarters as q
    cross join types as t
    left join aggregated as a
        on  q.quarter_start_date = a.quarter_start_date
        and t.opportunity_type   = a.opportunity_type

),

with_prior as (

    select
        s.*,
        s.quarter_start_date = a.current_quarter_start                          as is_current_quarter,
        lag(s.bookings_usd) over (partition by s.opportunity_type order by s.quarter_start_date)
                                                                                as prior_quarter_bookings_usd,
        lag(s.bookings_to_same_day_usd) over (partition by s.opportunity_type order by s.quarter_start_date)
                                                                                as prior_quarter_same_point_bookings_usd
    from spine as s
    cross join as_of as a

)

select
    quarter_start_date,
    fiscal_quarter_label,
    opportunity_type,
    is_rollup,
    is_current_quarter,
    bookings_usd,
    deals_won,
    prior_quarter_bookings_usd,
    prior_quarter_same_point_bookings_usd,
    -- the fair comparison: QTD vs prior-QTD for the current quarter, full vs full otherwise
    iff(is_current_quarter, prior_quarter_same_point_bookings_usd, prior_quarter_bookings_usd)
                                                                                as comparable_prior_bookings_usd,
    bookings_usd - comparable_prior_bookings_usd                                as qoq_change_usd,
    (bookings_usd - comparable_prior_bookings_usd)
        / nullif(comparable_prior_bookings_usd, 0)                              as qoq_change_pct,
    {{ as_of_date() }}                                                          as as_of_date

from with_prior
