{#-
  Impact report for a PR: for each changed mart, compare the CI-built table with the prod table.
      dbt --quiet run-operation ci_compare_to_prod --target ci \
          --args '{models: [fct_opportunities, mart_revops__pipeline], prod_database: GOLD}'
  Prints one line per model, prefixed CI_DIFF|, which the workflow turns into a PR comment:
      rows in prod, rows in CI, rows only in prod, rows only in CI, columns added, columns removed.
  Informational, not a gate: prod was built earlier today and CI just now, so a few rows can differ
  legitimately. A reviewer reading "fct_opportunities: 40,000 rows only in prod" knows a filter broke.
-#}
{% macro ci_compare_to_prod(models, prod_database) %}
    {%- if target.name == 'prod' -%}
        {{ exceptions.raise_compiler_error("ci_compare_to_prod compares CI with prod; run it with --target ci") }}
    {%- endif -%}

    {%- for model_name in models -%}
        {%- set matches = graph.nodes.values() | selectattr('resource_type', 'equalto', 'model')
                                               | selectattr('name', 'equalto', model_name) | list -%}
        {%- set node = matches[0] if matches else none -%}
        {%- set alias = (node.alias or node.name) if node else model_name -%}
        {%- set ci_rel   = adapter.get_relation(target.database, generate_schema_name(node.config.schema, node) | trim, alias) if node else none -%}
        {%- set prod_rel = adapter.get_relation(prod_database, node.config.schema or target.schema, alias) if node else none -%}

        {%- if node is none -%}
            {%- do print('CI_DIFF|' ~ model_name ~ '|not found in project||||||') -%}
        {%- elif ci_rel is none -%}
            {%- do print('CI_DIFF|' ~ model_name ~ '|not built in CI (ephemeral or failed)||||||') -%}
        {%- elif prod_rel is none -%}
            {%- set n = run_query('select count(*) from ' ~ ci_rel).columns[0].values()[0] -%}
            {%- do print('CI_DIFF|' ~ model_name ~ '|new model|0|' ~ n ~ '|||all|') -%}
        {%- else -%}
            {%- set ci_cols   = adapter.get_columns_in_relation(ci_rel)   | map(attribute='name') | map('lower') | list -%}
            {%- set prod_cols = adapter.get_columns_in_relation(prod_rel) | map(attribute='name') | map('lower') | list -%}
            {%- set common  = ci_cols  | select('in', prod_cols) | list -%}
            {%- set added   = ci_cols  | reject('in', prod_cols) | list -%}
            {%- set removed = prod_cols | reject('in', ci_cols)  | list -%}
            {%- set cols = common | join(', ') -%}

            {%- set sql -%}
                select
                    (select count(*) from {{ prod_rel }}),
                    (select count(*) from {{ ci_rel }}),
                    (select count(*) from (select {{ cols }} from {{ prod_rel }} except select {{ cols }} from {{ ci_rel }})),
                    (select count(*) from (select {{ cols }} from {{ ci_rel }} except select {{ cols }} from {{ prod_rel }}))
            {%- endset -%}
            {%- set r = run_query(sql).rows[0] -%}
            {%- set status = 'identical' if (r[2] == 0 and r[3] == 0 and not added and not removed) else 'changed' -%}
            {%- do print('CI_DIFF|' ~ model_name ~ '|' ~ status ~ '|' ~ r[0] ~ '|' ~ r[1] ~ '|' ~ r[2] ~ '|' ~ r[3]
                          ~ '|' ~ (added | join(' ')) ~ '|' ~ (removed | join(' '))) -%}
        {%- endif -%}
    {%- endfor -%}
{% endmacro %}
