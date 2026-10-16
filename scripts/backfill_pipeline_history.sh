#!/usr/bin/env bash
# Rebuild fct_pipeline_daily_snapshot one month at a time.
# Why chunks: each chunk is a small, retryable unit; a failure in month 7 does not redo months 1-6,
# and every chunk is idempotent (delete+insert by snapshot_date), so re-running is always safe.
#
# Usage: ./scripts/backfill_pipeline_history.sh 2024-01-01 2026-10-15 [target]
set -euo pipefail

start="${1:?start date YYYY-MM-DD}"
end="${2:?end date YYYY-MM-DD}"
target="${3:-prod}"

chunk_start="$start"
while [[ "$chunk_start" < "$end" || "$chunk_start" == "$end" ]]; do
  chunk_end=$(date -d "$chunk_start +1 month -1 day" +%F)
  [[ "$chunk_end" > "$end" ]] && chunk_end="$end"

  echo ">> backfilling $chunk_start .. $chunk_end"
  dbt build --target "$target" \
    --selector pipeline_history_backfill \
    --vars "{backfill_start_date: '$chunk_start', backfill_end_date: '$chunk_end'}"

  chunk_start=$(date -d "$chunk_end +1 day" +%F)
done

echo ">> done. Check: select snapshot_date, count(*) from fct_pipeline_daily_snapshot group by 1 order by 1;"
