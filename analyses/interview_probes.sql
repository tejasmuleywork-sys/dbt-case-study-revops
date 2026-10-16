-- The panel's probe questions as queries against the built marts.
-- Compile with: dbt compile -s interview_probes --vars '{as_of_date: 2026-10-16}'
-- Expected answers on the case-study mock data are in the comments.

-- 1. Negotiation stage: total and weighted pipeline              -> 85,000 and 63,750
select stage_name, total_pipeline, weighted_pipeline
from {{ ref('mart_revops__pipeline') }}
where stage_name = 'Negotiation';

-- 2. Open opportunities for Austin ISD (001B)                     -> 1 (006B; 006H is Closed Won)
select count(*) as open_opportunities
from {{ ref('fct_opportunities') }}
where account_id = '001B' and is_open;

-- 3. days_open for 006D (NULL amount, still open)                 -> 123 on 2026-10-16
select opportunity_id, amount, is_amount_missing, days_open
from {{ ref('fct_opportunities') }}
where opportunity_id = '006D';

-- 4. activity_count on the enriched opportunity                   -> 006B 2, 006E 2, 006C 1, 006D 1, others 0
select opportunity_id, activity_count, call_count, email_count, meeting_count
from {{ ref('fct_opportunities') }}
order by opportunity_id;

-- 5. Rows filtered in staging                                     -> 8 raw, 7 staged, 006G removed
select metric_name, metric_value
from {{ ref('audit_pipeline_reconciliation') }}
where as_of_date = {{ as_of_date() }}
  and metric_name in ('opportunity_rows', 'opportunity_deleted_rows', 'live_opportunities');

-- 6. Contact fan-out proof: joining contacts on account doubles 003B; via activities it does not
select 'join on account (wrong)' as method, count(*) as rows_for_003b
from {{ ref('stg_salesforce__contacts') }} c
join {{ ref('fct_opportunities') }} o on c.account_id = o.account_id
where c.contact_id = '003B'
union all
select 'via activities (right)', count(distinct a.opportunity_id)
from {{ ref('fct_activities') }} a
where a.contact_id = '003B';

-- 7. Velocity by segment (proxy until history is synced)          -> Enterprise 181, Mid-Market 195
select segment, deals_won, avg_days_to_win, median_days_to_win
from {{ ref('mart_revops__deal_velocity') }}
where grouping_level = 'segment';
