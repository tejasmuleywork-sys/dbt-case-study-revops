-- Grain: one row per Salesforce user (rep / owner / manager).

{{ config(enabled=var('salesforce__user_enabled', true)) }}

with source as (
    select
        *
    from
        {{ source('salesforce', 'user') }}
)

select
    nullif(trim(id), '') as user_id,
    trim(name) as user_name,
    lower(trim(email)) as user_email,
    nullif(trim(manager_id), '') as manager_id,
    nullif(trim(user_role_id), '') as user_role_id,
    coalesce(try_to_boolean(is_active::varchar), true)  as is_active,
    _fivetran_synced
from source
where id is not null
qualify row_number() over (partition by trim(id) order by _fivetran_synced desc) = 1
