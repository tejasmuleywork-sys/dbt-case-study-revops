-- Grain: one row per currency per rate period (Salesforce advanced currency management).
-- conversion_rate = units of this currency per 1 unit of the corporate currency.

{{ config(enabled=var('salesforce__multicurrency_enabled', false)) }}

select
    upper(trim(iso_code)) as currency_code,
    try_to_number(conversion_rate::varchar, 38, 9) as conversion_rate,
    {{ safe_to_date('start_date') }} as valid_from_date,
    coalesce({{ safe_to_date('next_start_date') }}, '9999-12-31'::date) as valid_to_date
from {{ source('salesforce', 'dated_conversion_rate') }}
where not coalesce(_fivetran_deleted, false)
