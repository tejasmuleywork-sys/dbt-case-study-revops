{#-
  Reconciliation test: the total of a column in one model must equal the total in another.
  Used to prove an aggregate mart ties exactly to its detail fact, so a join or filter
  that silently drops or duplicates deals fails the build.
-#}
{% test sums_match(model, column_name, compare_model, compare_column, model_filter='true', compare_filter='true', tolerance=0.01) %}

with model_total as (
    select coalesce(sum({{ column_name }}), 0) as total
    from {{ model }}
    where {{ model_filter }}
),

compare_total as (
    select coalesce(sum({{ compare_column }}), 0) as total
    from {{ compare_model }}
    where {{ compare_filter }}
)

select
    m.total as model_total,
    c.total as compare_total,
    m.total - c.total as difference
from model_total as m
cross join compare_total as c
where abs(m.total - c.total) > {{ tolerance }}

{% endtest %}
