-- Staging: Olist order items
-- Source: raw.olist_order_items_dataset
-- Grain: (order_id, order_item_id)
-- price and freight_value are cast to numeric; invalid rows yield NULL.

{{ config(materialized='view') }}

SELECT
    order_id,
    order_item_id::int AS order_item_id,
    product_id,
    seller_id,
    {{ parse_timestamp('shipping_limit_date') }} AS shipping_limit_date,
    NULLIF(TRIM(price), '')::numeric AS price,
    NULLIF(TRIM(freight_value), '')::numeric AS freight_value
FROM {{ source('retailpulse_raw', 'olist_order_items_dataset') }}
WHERE order_id IS NOT NULL
  AND order_item_id IS NOT NULL
