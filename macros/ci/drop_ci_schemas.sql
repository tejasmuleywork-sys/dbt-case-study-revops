{#-
  Drops every schema a PR's CI run created (CI_PR_42, CI_PR_42_STAGING, CI_PR_42_REVOPS, ...).
  Called by .github/workflows/dbt_ci_cleanup.yml when the PR is closed or merged.
      dbt run-operation drop_ci_schemas --args '{prefix: CI_PR_42}' --target ci
  Guard rails: refuses to run on the prod target and refuses any prefix that is not CI_PR_<n>.
-#}
{% macro drop_ci_schemas(prefix) %}
    {%- if target.name == 'prod' -%}
        {{ exceptions.raise_compiler_error("drop_ci_schemas must never run against prod") }}
    {%- endif -%}
    {%- set prefix = prefix | upper -%}
    {%- if not modules.re.match('^CI_PR_[0-9]+$', prefix) -%}
        {{ exceptions.raise_compiler_error("Refusing to drop schemas for prefix '" ~ prefix ~ "' (expected CI_PR_<number>)") }}
    {%- endif -%}

    {%- set schemas = run_query("show terse schemas like '" ~ prefix ~ "%' in database " ~ target.database) -%}
    {%- for row in schemas -%}
        {%- set name = row['name'] -%}
        {#- 'CI_PR_4%' also matches CI_PR_42: keep only this PR's schemas -#}
        {%- if name == prefix or name.startswith(prefix ~ '_') -%}
            {%- do run_query('drop schema if exists ' ~ target.database ~ '."' ~ name ~ '" cascade') -%}
            {{ log('Dropped ' ~ target.database ~ '.' ~ name, info=true) }}
        {%- endif -%}
    {%- endfor -%}
{% endmacro %}
