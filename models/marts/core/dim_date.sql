-- Grain: one row per calendar day. Calendar AND fiscal attributes in one place, so
-- "quarter" means the same thing in every mart. Change fiscal_year_start_month once,
-- every quarter-based number follows.

{%- set fy_start = var('fiscal_year_start_month') | int -%}
{%- set shift = (13 - fy_start) % 12 -%}   {#- months to add so the fiscal year lines up with a calendar year #}

with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="'" ~ var('date_spine_start') ~ "'::date",
        end_date="dateadd('year', 3, current_date())"
    ) }}
),

days as (
    select
        date_day::date as date_day,
        dateadd('month', {{ shift }}, date_day::date) as shifted_day
    from spine
)

select
    date_day,
    year(date_day) as calendar_year,
    quarter(date_day) as calendar_quarter,
    date_trunc('quarter', date_day)::date as calendar_quarter_start_date,
    month(date_day) as calendar_month,
    dayofweekiso(date_day) as day_of_week_iso,
    dayofweekiso(date_day) <= 5 as is_weekday,

    -- Fiscal year named by the calendar year it ENDS in (FY27 = Feb 2026 - Jan 2027 when it starts in Feb)
    year(shifted_day)                                               as fiscal_year,
    quarter(shifted_day)                                            as fiscal_quarter,
    'FY' || right(year(shifted_day)::varchar, 2) || '-Q' || quarter(shifted_day)  as fiscal_quarter_label,
    dateadd('month', -{{ shift }}, date_trunc('quarter', shifted_day))::date      as fiscal_quarter_start_date,
    dateadd('day', -1, dateadd('month', 3,
        dateadd('month', -{{ shift }}, date_trunc('quarter', shifted_day))))::date as fiscal_quarter_end_date,
    datediff('day',
        dateadd('month', -{{ shift }}, date_trunc('quarter', shifted_day))::date,
        date_day) + 1                                               as day_of_fiscal_quarter

from days
