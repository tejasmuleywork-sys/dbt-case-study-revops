# OpenGov RevOps: Salesforce pipeline data product (dbt + Snowflake), v2

Automates the RevOps VP's three Monday questions and the velocity follow-up, with trust,
audit and backfill built in.

| Question | Model | Grain |
|---|---|---|
| Open pipeline by stage | `mart_revops__pipeline` (contracted) | one row per stage with open deals |
| Deals at risk of slipping | `mart_revops__at_risk_deals` | one row per flagged open deal, with reasons |
| This quarter vs last quarter bookings | `mart_revops__bookings_qoq` | fiscal quarter x type (+ 'All types' roll-up) |
| Deal velocity by segment | `mart_revops__deal_velocity` | segment x type x quarter + roll-ups |

## DAG

```
RAW.SALESFORCE (Fivetran)
  opportunity ─────────► stg_salesforce__opportunity ─┬─► snap_salesforce__opportunities (SCD2)
  opportunity_history ─► stg_salesforce__hist_opportunity ─┐
                                                        ├─► int_opportunity_state__events (table) ─┬─► int_opportunities__change_metrics
  account ─► stg_salesforce__accounts ─► snap_salesforce__accounts ─► dim_account                   ├─► fct_pipeline_daily_snapshot (incremental)
  user ────► stg_salesforce__users ─► dim_user                                                      └─► fct_opportunity_stage_history ─► mart_revops__deal_velocity
  activity ► stg_salesforce__activities ─► fct_activities (incremental) ─► int_activities__by_opportunity
  contact ─► stg_salesforce__contacts (masked email)
  seed stage_mapping, dim_date
        all of the above ─► int_opportunities__enriched ─► fct_opportunities ─┬─► mart_revops__pipeline
                                                                               ├─► mart_revops__at_risk_deals
                                                                               └─► mart_revops__bookings_qoq
  everything ─► audit_pipeline_reconciliation (incremental log)   + on-run-end ─► audit.dbt_run_results
```

## Layers

| Layer | Materialization | Rule |
|---|---|---|
| staging | view | rename, cast, clean, de-dup (then) drop deletes; 1:1 with source; no joins |
| intermediate | ephemeral, or table when reused/heavy | joins + business logic; aggregate children before joining |
| marts/core | table; incremental for activities and the daily snapshot | conformed facts and dimensions |
| marts/revops | table | the answers; contract on the BI-facing mart |
| audit | incremental, `full_refresh=false` | business numbers per day, never wiped |

## Run it

```bash
# 0. one-time: scripts/snowflake_setup.sql (admin), scripts/load_mock_raw_data.sql (mock rows)
dbt deps
dbt seed
dbt snapshot
dbt source freshness
dbt build                                   # selector 'daily' is the default: models + tests + unit tests

# reproduce the case-study numbers exactly
dbt build --vars '{as_of_date: 2026-10-16}'

# backfill / rebuild a range of pipeline history (idempotent)
dbt build --selector pipeline_history_backfill --vars '{backfill_start_date: 2025-01-01, backfill_end_date: 2025-03-31}'
./scripts/backfill_pipeline_history.sh 2024-01-01 2026-10-15

# CI on every pull request: only what changed, compared with prod
dbt build --select state:modified+ --defer --state ./prod-artifacts
```

Unit tests read column types from the warehouse, so load the mock RAW tables before `dbt build`.

## Results on the case-study mock data (as of 2026-10-16)

| Stage | Open deals | Unpriced | Total pipeline | Weighted |
|---|---|---|---|---|
| Prospecting | 1 | 1 | 0 | 0 |
| Discovery | 1 | 0 | 95,000 | 19,000 |
| Proposal | 1 | 0 | 320,000 | 160,000 |
| Negotiation | 1 | 0 | 85,000 | 63,750 |
| **Total** | **4** | **1** | **500,000** | **242,750** |

- Staging: 8 rows in, 7 out (006G soft-deleted). 006D kept with NULL amount and `is_amount_missing = true`.
- Austin ISD (001B): 1 open opportunity (006B). 006H is Closed Won.
- `days_open` 006D = 123, 006B = 244.
- `activity_count`: 006B 2, 006E 2, 006C 1, 006D 1, others 0.
- At risk: all 4 open deals (past close date, no activity for 100+ days, stalled in stage).
- Bookings: Q1 2025 250,000 (006A); Q2 2026 85,000 (006H, renewal); Q3 and Q4 2026 0.
- Velocity proxy (no history synced): Enterprise 181 days, Mid-Market 195 days.

Stage probabilities (`seeds/stage_mapping.csv`, 10/20/50/75%) are placeholders to confirm with RevOps.
