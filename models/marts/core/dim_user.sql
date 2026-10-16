-- Grain: one row per Salesforce user (current state), with their manager's name for team roll-ups.

{{ config(enabled=var('salesforce__user_enabled', true)) }}

select
    u.user_id,
    u.user_name,
    u.user_email,
    u.is_active,
    u.manager_id,
    m.user_name         as manager_name
from {{ ref('stg_salesforce__users') }} as u
left join {{ ref('stg_salesforce__users') }} as m
    on u.manager_id = m.user_id
