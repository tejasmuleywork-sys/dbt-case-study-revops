-- Grain: one row per activity (call / email / meeting), de-duplicated.
-- Deletes are KEPT as tombstones (is_deleted = true) instead of filtered: fct_activities is
-- incremental, and a merge can only retract an activity it is told was deleted.
-- Small current-state objects filter deletes in staging; high-volume event objects keep tombstones.

with source as (
    select
     *
    from {{ source('salesforce', 'activity') }}
),

latest as (
    select
        *
    from
        source
    qualify row_number() over (
        partition by trim(activity_id)
        order by _fivetran_synced desc) = 1
)

select
    nullif(trim(activity_id), '') as activity_id,
    nullif(trim(opp_id), '') as opportunity_id,     -- NULL = account-level activity
    nullif(trim(contact_id), '') as contact_id,
    initcap(trim(type)) as activity_type,
    trim(subject) as subject,
    {{ safe_to_date('activity_date') }} as activity_date,      -- '2026- 06-10' -> 2026-06-10
    {{ safe_to_timestamp_utc('created_date') }} as created_at_utc,
    {{ is_deleted_flag('is_deleted') }} as is_deleted,
    _fivetran_synced
from latest
where activity_id is not null
