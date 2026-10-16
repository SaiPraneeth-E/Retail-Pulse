-- Mart: fact_order_items
-- Grain: (order_id, order_item_id) (item-level)

{{ config(
    materialized='incremental',
    unique_key=['order_id', 'order_item_id'],
    incremental_strategy='delete+insert'
) }}

SELECT
    oi.order_id,
    oi.order_item_id,
    dp.product_key,
    ds.seller_key,
    oi.price,
    oi.freight_value
FROM {{ ref('stg_olist_order_items') }} oi
LEFT JOIN {{ ref('dim_product') }} dp
  ON dp.product_id = oi.product_id
LEFT JOIN {{ ref('dim_seller') }} ds
  ON ds.seller_id = oi.seller_id
