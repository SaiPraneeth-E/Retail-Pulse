-- Mart: dim_seller
-- Grain: seller_id

{{ config(materialized='table') }}

WITH sellers AS (
    SELECT * FROM {{ ref('stg_olist_sellers') }}
)
SELECT
    ROW_NUMBER() OVER (ORDER BY seller_id) AS seller_key,
    seller_id,
    seller_city,
    seller_state,
    seller_zip_code_prefix
FROM sellers
