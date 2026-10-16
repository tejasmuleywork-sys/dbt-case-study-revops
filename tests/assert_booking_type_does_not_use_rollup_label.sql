-- Reserved aggregate label: reject collision with an actual Salesforce type.
select opportunity_id, opportunity_type
from {{ ref('fct_opportunities') }}
where opportunity_type = 'All types'
