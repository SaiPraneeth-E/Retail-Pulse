-- Staging: Olist customers
-- Source: raw.olist_customers_dataset
-- Grain: customer_id

{{ config(materialized='view') }}

SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM {{ source('retailpulse_raw', 'olist_customers_dataset') }}
WHERE customer_id IS NOT NULL
