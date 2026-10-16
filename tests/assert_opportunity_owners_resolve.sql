{{ config(enabled=var('salesforce__user_enabled', true), severity='warn') }}
-- Optional source coverage warning: the supplied USER mock is empty.
select opportunity_id, opportunity_owner_id
from {{ ref('int_opportunities__enriched') }}
where opportunity_owner_name = 'Unknown owner'
