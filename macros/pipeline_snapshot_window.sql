{#-
  Decides WHAT a run of fct_pipeline_daily_snapshot writes. Returns a dict:

    mode          daily | initial | backfill | replay
    observe_today true  -> write today's OBSERVED rows (from fct_opportunities, the live truth)
    has_rec       true  -> write RECONSTRUCTED rows for rec_start..rec_end (from state history)
    rec_start / rec_end   ISO dates of the reconstructed window
    today         the real business "today" (run start in business_timezone)

  daily    normal scheduled run on an existing table         -> today observed only
  initial  first ever build (table does not exist yet)       -> pipeline_history_start..yesterday reconstructed + today observed
  backfill --vars '{backfill_start_date: X, backfill_end_date: Y}' -> X..Y reconstructed, nothing observed
  replay   --vars '{as_of_date: D}' with D in the past       -> D reconstructed (used for case-study replays)

  Rules enforced here, at compile time, so a bad command fails before touching data:
    * backfill needs both dates, start <= end, and end < today (today belongs to the observed run)
    * as_of_date in the future is rejected
-#}
{% macro pipeline_snapshot_window() %}
    {%- set dt = modules.datetime -%}
    {%- set today = run_started_at.astimezone(modules.pytz.timezone(var('business_timezone'))).date() -%}
    {%- set yesterday = today - dt.timedelta(days=1) -%}
    {%- set bf_start = var('backfill_start_date', none) -%}
    {%- set bf_end = var('backfill_end_date', none) -%}
    {%- set override = var('as_of_date', none) -%}

    {%- if bf_start or bf_end -%}
        {%- if not (bf_start and bf_end) -%}
            {{ exceptions.raise_compiler_error("Backfill needs BOTH backfill_start_date and backfill_end_date.") }}
        {%- endif -%}
        {%- set s = dt.date.fromisoformat(bf_start | string) -%}
        {%- set e = dt.date.fromisoformat(bf_end | string) -%}
        {%- if s > e -%}
            {{ exceptions.raise_compiler_error("backfill_start_date (" ~ s ~ ") is after backfill_end_date (" ~ e ~ ").") }}
        {%- endif -%}
        {%- if e >= today -%}
            {{ exceptions.raise_compiler_error("backfill_end_date must be before today (" ~ today ~ "): today is written by the daily observed run.") }}
        {%- endif -%}
        {{ return({'mode': 'backfill', 'observe_today': false, 'has_rec': true,
                   'rec_start': s | string, 'rec_end': e | string, 'today': today | string}) }}
    {%- endif -%}

    {%- if override -%}
        {%- set d = dt.date.fromisoformat(override | string) -%}
        {%- if d > today -%}
            {{ exceptions.raise_compiler_error("as_of_date " ~ d ~ " is in the future.") }}
        {%- endif -%}
        {%- if d < today -%}
            {{ return({'mode': 'replay', 'observe_today': false, 'has_rec': true,
                       'rec_start': d | string, 'rec_end': d | string, 'today': today | string}) }}
        {%- endif -%}
    {%- endif -%}

    {%- if not is_incremental() -%}
        {%- set start = dt.date.fromisoformat(var('pipeline_history_start') | string) -%}
        {{ return({'mode': 'initial', 'observe_today': true, 'has_rec': start <= yesterday,
                   'rec_start': start | string, 'rec_end': yesterday | string, 'today': today | string}) }}
    {%- endif -%}

    {{ return({'mode': 'daily', 'observe_today': true, 'has_rec': false,
               'rec_start': none, 'rec_end': none, 'today': today | string}) }}
{% endmacro %}