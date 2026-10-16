-- Grain: one row per activity (deleted ones kept as tombstones with is_deleted = true).
-- The highest-volume Salesforce object, so this is the model that is incremental:
--   * only rows Fivetran synced since the last load (minus a lookback) are read
--     -> the filter on _fivetran_synced prunes RAW micro-partitions (Fivetran loads in sync order)
--   * MERGE on activity_id: edits and deletes overwrite the previous version (idempotent)
--   * the lookback re-merges late or re-synced rows; merging the same row twice is harmless
-- Lives in intermediate so the activity rollup never has to read a mart.
-- Analysts read it through the fct_activities view (marts/core), which stores nothing extra.

{{
    config(
        materialized='incremental',
        unique_key='activity_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns'
    )
}}

select
    activity_id,
    opportunity_id,
    contact_id,
    activity_type,
    subject,
    activity_date,
    created_at_utc,
    is_deleted,
    _fivetran_synced,
    '{{ invocation_id }}' as dbt_invocation_id     -- which run last wrote this row (audit)
from {{ ref('stg_salesforce__activities') }}

{% if is_incremental() %}

where _fivetran_synced >= (
    select coalesce(
        dateadd(
            'hour',
            -{{ var('incremental_lookback_hours', 72) }},
            max(_fivetran_synced)
        ),
        -- An existing but empty target has a NULL watermark.
        -- Without this fallback, every incoming row is rejected.
        '1900-01-01'::timestamp_ntz
    )
    from {{ this }}
)

{% endif %}
