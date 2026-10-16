-- Staging: Olist products
-- Source: raw.olist_products_dataset
-- Grain: product_id
-- Numeric dimensions cast to integers; invalid values become NULL.

{{ config(materialized='view') }}

SELECT
    product_id,
    product_category_name,
    NULLIF(TRIM(product_name_length), '')::int AS product_name_length,
    NULLIF(TRIM(product_description_length), '')::int AS product_description_length,
    NULLIF(TRIM(product_photos_qty), '')::int AS product_photos_qty,
    NULLIF(TRIM(product_weight_g), '')::int AS product_weight_g,
    NULLIF(TRIM(product_length_cm), '')::int AS product_length_cm,
    NULLIF(TRIM(product_height_cm), '')::int AS product_height_cm,
    NULLIF(TRIM(product_width_cm), '')::int AS product_width_cm
FROM {{ source('retailpulse_raw', 'olist_products_dataset') }}
WHERE product_id IS NOT NULL
