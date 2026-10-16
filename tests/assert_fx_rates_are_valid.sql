{{ config(enabled=var('salesforce__multicurrency_enabled', false)) }}
select * from {{ ref('stg_salesforce__dated_conversion_rates') }}
where currency_code is null or trim(currency_code) = ''
   or conversion_rate is null or conversion_rate <= 0
   or valid_from_date is null or valid_to_date <= valid_from_date
