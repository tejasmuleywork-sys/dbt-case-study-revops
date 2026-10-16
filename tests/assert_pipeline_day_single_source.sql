-- A business day is either observed or reconstructed, never a mix.
-- A mix would mean a backfill overwrote part of an observed day: the trend chart would double count.
select
    snapshot_date,
    count(distinct coalesce(snapshot_source, 'observed') = 'observed') as kinds
from {{ ref('fct_pipeline_daily_snapshot') }}
group by snapshot_date
having count(distinct coalesce(snapshot_source, 'observed') = 'observed') > 1