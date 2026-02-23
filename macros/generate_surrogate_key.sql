{% macro generate_surrogate_key(column_list) %}
    {{ dbt_utils.generate_surrogate_key(column_list) }}
{% endmacro %}
