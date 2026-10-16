-- Mart: dim_customer
-- Grain: customer_unique_id (one row per real unique customer)

{{ config(materialized='table') }}

WITH ranked_customers AS (
    SELECT
        customer_unique_id,
        customer_id,
        customer_city,
        customer_state,
        customer_zip_code_prefix,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY customer_id
        ) AS rn
    FROM {{ ref('stg_olist_customers') }}
    WHERE customer_unique_id IS NOT NULL
)
SELECT
    ROW_NUMBER() OVER (ORDER BY customer_unique_id) AS customer_key,
    customer_unique_id,
    customer_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix
FROM ranked_customers
WHERE rn = 1
