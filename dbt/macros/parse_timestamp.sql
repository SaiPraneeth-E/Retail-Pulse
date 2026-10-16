{% macro parse_timestamp(column) %}
  (CASE
     WHEN {{ column }} IS NOT NULL
          AND trim({{ column }}) ~ '^\d{4}-\d{2}-\d{2}'
     THEN {{ column }}::timestamp
     ELSE NULL
   END)
{% endmacro %}
