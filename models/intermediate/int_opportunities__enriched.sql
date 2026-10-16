-- Grain: one row per live opportunity (same as staging; proven by unique + equal_rowcount tests).
-- Adds account, owner, stage reference data, currency conversion, activity rollups and
-- slippage metrics. Every join is many-to-one: children were aggregated before this model.

with opportunities as (
    select * from {{ ref('stg_salesforce__opportunity') }}
),

-- Current-state attribution. Historical reports require a separately agreed as-of join.
accounts as (
    select * from {{ ref('stg_salesforce__accounts') }}
),

{% if var('salesforce__user_enabled') -%}
users as (
    select * from {{ ref('stg_salesforce__users') }}
),
{%- endif %}

stages as (
    select * from {{ ref('stage_mapping') }}
),

activity as (
    select * from {{ ref('int_activities__by_opportunity') }}
),

changes as (
    select * from {{ ref('int_opportunities__change_metrics') }}
),

{% if var('salesforce__multicurrency_enabled') -%}
fx as (
    select * from {{ ref('stg_salesforce__dated_conversion_rates') }}
),
{%- endif %}

joined as (
    select
        o.opportunity_id,
        o.account_id,
        coalesce(a.account_name, 'Unknown account') as account_name,
        coalesce(a.segment, 'Unassigned') as segment,
        a.industry,
        a.state_code,
        a.account_owner_id,

        o.opportunity_owner_id,
        {% if var('salesforce__user_enabled') -%}
        coalesce(u.user_name, 'Unknown owner') as opportunity_owner_name,
        {%- else -%}
        'Unknown owner' as opportunity_owner_name,
        {%- endif %}

        coalesce(s.stage_name, 'Unmapped') as stage_name,
        coalesce(s.stage_order, 99) as stage_order,
        coalesce(s.stage_probability, 0) as stage_probability,
        coalesce(s.forecast_category, 'Unmapped') as forecast_category,
        s.stage_key is null as is_stage_unmapped,
        o.opportunity_type,
        o.is_open,
        o.is_won,
        o.is_lost,

        o.amount,
        o.currency_code,
        {% if var('salesforce__multicurrency_enabled') -%}
        case
            when o.currency_code = '{{ var("corporate_currency") }}' then 1
            when fx.conversion_rate > 0 then 1 / fx.conversion_rate
            else null
        end
        {%- else -%}
        1
        {%- endif %} as fx_rate_to_corporate,
        {% if var('salesforce__multicurrency_enabled') -%}
        (
            o.currency_code is null
            or (o.currency_code <> '{{ var("corporate_currency") }}'
                and (fx.conversion_rate is null or fx.conversion_rate <= 0))
        ) as is_fx_rate_missing,
        {%- else -%}
        false as is_fx_rate_missing,
        {%- endif %}
        o.is_amount_missing,
        o.dq_close_before_created,
        o.dq_negative_amount,

        o.created_date,
        o.close_date,
        o.created_at_utc,

        coalesce(act.activity_count, 0) as activity_count,
        coalesce(act.call_count, 0) as call_count,
        coalesce(act.email_count, 0) as email_count,
        coalesce(act.meeting_count, 0) as meeting_count,
        coalesce(act.upcoming_activity_count, 0) as upcoming_activity_count,
        coalesce(act.contacts_engaged_count, 0) as contacts_engaged_count,
        act.last_activity_date,
        act.next_activity_date,

        coalesce(ch.close_date_push_count, 0) as close_date_push_count,
        coalesce(ch.close_date_pushes_last_30d, 0) as close_date_pushes_last_30d,
        coalesce(ch.stage_regression_count, 0) as stage_regression_count,
        coalesce(ch.reopen_count, 0) as reopen_count,
        ch.current_stage_entered_date as current_stage_entered_date -- unknown is not creation

    from opportunities as o
    left join accounts as a
        on o.account_id = a.account_id
    {% if var('salesforce__user_enabled') -%}
    left join users as u
        on o.opportunity_owner_id = u.user_id
    {%- endif %}
    left join stages as s
        on o.stage_key = s.stage_key
    left join activity as act
        on o.opportunity_id = act.opportunity_id
    left join changes as ch
        on o.opportunity_id = ch.opportunity_id
    {% if var('salesforce__multicurrency_enabled') -%}
    left join fx                                                    -- rate in force on the close date
        on  o.currency_code = fx.currency_code
        and o.currency_code <> '{{ var("corporate_currency") }}' 
        and o.close_date >= fx.valid_from_date
        and o.close_date <  fx.valid_to_date
    {%- endif %}

)

select
    *,
    amount * fx_rate_to_corporate as amount_usd,
    amount * fx_rate_to_corporate * stage_probability as weighted_amount_usd,   -- NULL in, NULL out
    -- Age of the deal: to "today" while open, to the close date once closed. Dates only,
    -- so 006D (NULL amount) still gets a value: 123 days on 2026-10-16.
    greatest(0, datediff('day', created_date, iff(is_open, {{ as_of_date() }}, close_date))) as days_open,
    datediff('day', last_activity_date, {{ as_of_date() }}) as days_since_last_activity,
    datediff('day', current_stage_entered_date, {{ as_of_date() }})  as days_in_current_stage,
    amount * fx_rate_to_corporate > {{ var('max_reasonable_amount') }} as dq_amount_outlier,
    {{ as_of_date() }} as as_of_date

from joined
