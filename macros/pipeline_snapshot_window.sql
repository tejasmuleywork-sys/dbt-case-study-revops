{# Retired compatibility guard. Historical reconstruction requires validated source coverage. #}
{% macro pipeline_snapshot_window() %}
  {% do exceptions.raise_compiler_error(
      'pipeline_snapshot_window is retired. Observed daily capture does not support backfill.'
  ) %}
{% endmacro %}
