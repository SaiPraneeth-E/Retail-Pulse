-- Mart: dim_product
-- Grain: product_id
-- Category name translated to English where available.

{{ config(materialized='table') }}

WITH products AS (
    SELECT * FROM {{ ref('stg_olist_products') }}
),
translation AS (
    SELECT * FROM {{ ref('stg_olist_category_translation') }}
)
SELECT
    ROW_NUMBER() OVER (ORDER BY p.product_id) AS product_key,
    p.product_id,
    p.product_category_name,
    t.product_category_name_english,
    p.product_name_length,
    p.product_description_length,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM products p
LEFT JOIN translation t
  ON t.product_category_name = p.product_category_name
