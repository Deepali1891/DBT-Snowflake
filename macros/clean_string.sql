{% macro clean_string(column_name) %}
    initcap(trim({{ column_name }}))
{% endmacro %}
