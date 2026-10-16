#!/usr/bin/env bash
# Downloads the manifest.json of the last SUCCESSFUL production deploy into prod-state/.
# That manifest is "what prod looks like now". With it, CI can:
#   * build only what the PR changed  (--select state:modified+)
#   * read everything else from prod  (--defer), instead of rebuilding the whole project.
# Without it (first deploy ever, or the artifact expired) CI falls back to a full build. Never fails.
set -uo pipefail

dest="${1:-prod-state}"
found=false

run_id=$(gh run list --repo "${GITHUB_REPOSITORY:-}" --workflow dbt_deploy.yml --branch main --status success --limit 1 \
           --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true)

if [ -n "${run_id}" ] && gh run download "${run_id}" --repo "${GITHUB_REPOSITORY:-}" --name prod-manifest --dir "${dest}" 2>/dev/null \
   && [ -f "${dest}/manifest.json" ]; then
  found=true
  echo "Using prod manifest from deploy run ${run_id}"
else
  echo "::warning title=No prod manifest::No successful deploy artifact found. Building the full project instead of only changed models."
fi

echo "found=${found}" >> "${GITHUB_OUTPUT:-/dev/null}"
