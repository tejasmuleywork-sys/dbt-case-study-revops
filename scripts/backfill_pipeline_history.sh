#!/usr/bin/env bash
# Backfill fct_pipeline_daily_snapshot one month at a time (reconstructed rows only).
#
#   ./scripts/backfill_pipeline_history.sh <start YYYY-MM-DD> [end YYYY-MM-DD, default yesterday] [target, default dev]
#   ./scripts/backfill_pipeline_history.sh 2024-01-01                      # dev, up to yesterday
#   ./scripts/backfill_pipeline_history.sh 2024-01-01 2026-10-15 prod
#
# Why monthly chunks: each chunk is one small MERGE that is retryable on its own. A failure in month 7
# does not redo months 1-6, and re-running any chunk gives the same result (idempotent).
# Observed days inside the range are skipped automatically, never overwritten.
# Works on macOS and Linux (date math in Python, not GNU/BSD `date`).
set -euo pipefail

start="${1:?usage: $0 <start YYYY-MM-DD> [end YYYY-MM-DD] [target]}"
end="${2:-$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=1))')}"
target="${3:-dev}"

chunks=$(python3 - "$start" "$end" <<'PY'
import sys, datetime as dt
s, e = (dt.date.fromisoformat(x) for x in sys.argv[1:3])
if s > e:
    sys.exit(f"start {s} is after end {e}")
while s <= e:
    nxt = (s.replace(day=1) + dt.timedelta(days=32)).replace(day=1)   # first day of next month
    ce = min(nxt - dt.timedelta(days=1), e)
    print(s, ce)
    s = ce + dt.timedelta(days=1)
PY
)

echo "Backfilling ${start} .. ${end} on target '${target}'"
while read -r cs ce; do
  echo ">> ${cs} .. ${ce}"
  dbt build --target "${target}" \
    --selector pipeline_history_backfill \
    --vars "{backfill_start_date: '${cs}', backfill_end_date: '${ce}'}"
done <<< "${chunks}"

cat <<'SQL'
>> done. Check coverage:
   select snapshot_source, min(snapshot_date), max(snapshot_date), count(distinct snapshot_date) as days, count(*) as rows
   from <db>.<core schema>.fct_pipeline_daily_observed group by 1 order by 1;
SQL