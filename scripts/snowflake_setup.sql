-- One-time platform setup for the RevOps data product (run by a Snowflake admin).
-- Principles: least privilege, separate compute per workload, cost guardrails, PII masked by policy.

use role securityadmin;

-- ---------- roles ----------
create role if not exists transformer;            -- dbt in prod (service user, key-pair auth)
create role if not exists transformer_dev;        -- engineers + CI, writes only to ANALYTICS_DEV
create role if not exists revops_analyst;         -- reads REVOPS marts, emails masked
create role if not exists revops_admin;           -- reads everything incl. PII
grant role transformer to role sysadmin;
grant role transformer_dev to role sysadmin;

use role sysadmin;

-- ---------- compute: one warehouse per workload, so a heavy dashboard never slows the build ----------
create warehouse if not exists transforming_xs_wh
    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
    comment = 'dbt builds. Scale UP (size) for a big backfill, not out.';
create warehouse if not exists reporting_wh
    warehouse_size = xsmall auto_suspend = 60 auto_resume = true initially_suspended = true
    min_cluster_count = 1 max_cluster_count = 3 scaling_policy = standard   -- multi-cluster: Monday 9 AM concurrency
    comment = 'BI / analysts. Scales OUT for many concurrent users.';

-- ---------- databases ----------
create database if not exists analytics;
create database if not exists analytics_dev;
create schema if not exists analytics.governance;

grant usage on database raw to role transformer;
grant usage on all schemas in database raw to role transformer;
grant select on all tables in database raw to role transformer;
grant select on future tables in database raw to role transformer;
grant usage on database raw to role transformer_dev;
grant usage on all schemas in database raw to role transformer_dev;
grant select on future tables in database raw to role transformer_dev;
grant all on database analytics to role transformer;
grant all on database analytics_dev to role transformer_dev;
grant usage on warehouse transforming_xs_wh to role transformer;
grant usage on warehouse transforming_xs_wh to role transformer_dev;
grant usage on warehouse reporting_wh to role revops_analyst;

-- analysts get every future mart automatically (no grant step in each dbt run)
grant usage on database analytics to role revops_analyst;
grant usage on schema analytics.revops to role revops_analyst;
grant select on future tables in schema analytics.revops to role revops_analyst;
grant select on future views  in schema analytics.revops to role revops_analyst;

-- ---------- cost guardrail ----------
use role accountadmin;
create resource monitor if not exists revops_dbt_monitor
    with credit_quota = 30 frequency = monthly start_timestamp = immediately
    triggers on 80 percent do notify
             on 100 percent do suspend;
alter warehouse transforming_xs_wh set resource_monitor = revops_dbt_monitor;

-- ---------- PII: contact emails visible only to RevOps admins ----------
use role sysadmin;
create masking policy if not exists analytics.governance.mask_pii_email as (val string) returns string ->
    case when is_role_in_session('REVOPS_ADMIN') then val
         else regexp_replace(val, '^[^@]+', '*****')          -- s.chen@austinisd.org -> *****@austinisd.org
    end;
grant apply on masking policy analytics.governance.mask_pii_email to role transformer;
