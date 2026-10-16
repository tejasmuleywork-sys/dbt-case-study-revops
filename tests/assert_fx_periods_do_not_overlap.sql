{{ config(enabled=var('salesforce__multicurrency_enabled', false)) }}
-- A deal date must resolve to at most one FX rate.
select currency_code, valid_from_date, valid_to_date
from {{ ref('stg_salesforce__dated_conversion_rates') }}
qualify valid_from_date < max(valid_to_date) over (
    partition by currency_code
    order by valid_from_date, valid_to_date
    rows between unbounded preceding and 1 preceding
)
