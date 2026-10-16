-- Staging: product category name translation
-- Source: raw.olist_product_category_name_translation
-- Grain: product_category_name

{{ config(materialized='view') }}

SELECT
    product_category_name,
    product_category_name_english
FROM {{ source('retailpulse_raw', 'olist_product_category_name_translation') }}
WHERE product_category_name IS NOT NULL
