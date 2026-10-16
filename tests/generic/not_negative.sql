{% test not_negative(model, column_name) %}

-- Fails on any row where the column is below zero. NULLs pass (use not_null for that).
select {{ column_name }}
from {{ model }}
where {{ column_name }} < 0

{% endtest %}
