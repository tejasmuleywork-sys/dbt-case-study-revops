-- Grain: one row per live activity. The analyst-facing activity fact.
-- A view over the incremental int_activities__deduped: no second copy of the data,
-- and deleted activities (tombstones) are filtered out here, not exposed to BI.

{{ config(materialized='view') }}

select
    activity_id,
    opportunity_id,
    contact_id,
    activity_type,
    subject,
    activity_date,
    created_at_utc,
    _fivetran_synced
from {{ ref('int_activities__deduped') }}
where not is_deleted
