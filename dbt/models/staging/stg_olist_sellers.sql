-- Staging: Olist sellers
-- Source: raw.olist_sellers_dataset
-- Grain: seller_id

{{ config(materialized='view') }}

SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM {{ source('retailpulse_raw', 'olist_sellers_dataset') }}
WHERE seller_id IS NOT NULL
