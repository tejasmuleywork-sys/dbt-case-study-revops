{# A single atomic MERGE replaces today's observation without deleting other dates.
   The incoming relation is a materialized temp TABLE, not a re-evaluated view.
   Explicit column lists avoid positional mistakes when generating tombstone rows. #}
{% macro get_incremental_observed_daily_pipeline_sql(arg_dict) %}
    {% set target_relation = arg_dict['target_relation'] %}
    {% set temp_relation = arg_dict['temp_relation'] %}
    {% set dest_columns = arg_dict['dest_columns'] %}
    {% set insert_columns = [] %}
    {% set source_values = [] %}
    {% set incoming_columns = [] %}
    {% set existing_columns = [] %}
    {% set updates = [] %}
    {% for column in dest_columns %}
        {% set quoted = adapter.quote(column.name) %}
        {% do insert_columns.append(quoted) %}
        {% do source_values.append('s.' ~ quoted) %}
        {% do incoming_columns.append('incoming.' ~ quoted) %}
        {% do existing_columns.append('existing.' ~ quoted) %}
        {% do updates.append(quoted ~ ' = s.' ~ quoted) %}
    {% endfor %}

    merge into {{ target_relation }} as d
    using (
        select {{ incoming_columns | join(', ') }}, false as _delete_row
        from {{ temp_relation }} as incoming
        union all
        select {{ existing_columns | join(', ') }}, true as _delete_row
        from {{ target_relation }} as existing
        where existing.snapshot_date = {{ as_of_date() }}
          and not exists (
              select 1 from {{ temp_relation }} as incoming
              where incoming.snapshot_date = existing.snapshot_date
                and incoming.opportunity_id = existing.opportunity_id
          )
    ) as s
    on d.snapshot_date = s.snapshot_date and d.opportunity_id = s.opportunity_id
    when matched and s._delete_row then delete
    when matched then update set {{ updates | join(', ') }}
    when not matched and not s._delete_row then
        insert ({{ insert_columns | join(', ') }})
        values ({{ source_values | join(', ') }})
{% endmacro %}
