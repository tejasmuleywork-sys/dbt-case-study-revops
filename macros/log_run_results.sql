{#-
  Operational audit (on-run-end hook): one row per node per invocation in <audit schema>.DBT_RUN_RESULTS.
  Answers "did last night's run succeed, how long did it take, how many rows, which test failed?"
  for anyone, in SQL, without dbt Cloud access. (dbt_artifacts or the dbt Cloud Discovery API are
  heavier alternatives that also capture the manifest.)
-#}
{% macro log_run_results(results) %}
    {%- if execute and results and flags.WHICH in ['run', 'build', 'test', 'snapshot', 'seed'] -%}

        {%- set audit_schema = generate_schema_name('audit', none) -%}
        {%- set audit_table = target.database ~ '.' ~ audit_schema ~ '.dbt_run_results' -%}

        {%- do run_query('create schema if not exists ' ~ target.database ~ '.' ~ audit_schema) -%}
        {%- do run_query(
            'create table if not exists ' ~ audit_table ~ ' (
                invocation_id     varchar,
                run_started_at    timestamp_ntz,
                as_of_date        date,
                target_name       varchar,
                node_id           varchar,
                resource_type     varchar,
                status            varchar,
                rows_affected     number,
                failures          number,
                execution_seconds float,
                message           varchar,
                logged_at         timestamp_ntz
            )'
        ) -%}

        {%- set rows = [] -%}
        {%- for r in results -%}
            {%- set rows_affected = r.adapter_response.get('rows_affected') if r.adapter_response else none -%}
            {%- set message = (r.message or '') | string | replace("'", "''") | truncate(1000, true, '') -%}
            {%- do rows.append(
                "('" ~ r.node.unique_id ~ "', '" ~ r.node.resource_type ~ "', '" ~ r.status ~ "', "
                ~ (rows_affected if rows_affected is not none else 'null') ~ ", "
                ~ (r.failures if r.failures is not none else 'null') ~ ", "
                ~ (r.execution_time | round(3)) ~ ", '" ~ message ~ "')"
            ) -%}
        {%- endfor -%}

        {%- set insert_sql -%}
            insert into {{ audit_table }}
            select
                '{{ invocation_id }}',
                '{{ run_started_at.strftime("%Y-%m-%d %H:%M:%S") }}'::timestamp_ntz,
                {{ as_of_date() }},
                '{{ target.name }}',
                column1, column2, column3,
                column4::number, column5::number, column6::float, column7,
                sysdate()
            from values {{ rows | join(',\n') }}
        {%- endset -%}
        {%- do run_query(insert_sql) -%}
        {{ log("Audit: wrote " ~ rows | length ~ " rows to " ~ audit_table, info=true) }}

    {%- endif -%}
{% endmacro %}
