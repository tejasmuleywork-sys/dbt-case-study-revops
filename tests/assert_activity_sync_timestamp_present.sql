-- A NULL watermark would be silently skipped by subsequent incremental loads.
select activity_id from {{ ref('stg_salesforce__activities') }}
where _fivetran_synced is null
