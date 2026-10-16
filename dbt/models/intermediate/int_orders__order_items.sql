-- Intermediate: order-level aggregation of items
-- Grain: order_id
-- Revenue here is item-based (sum of price), kept separate from payments.

{{ config(materialized='table') }}

WITH items AS (
    SELECT *
    FROM {{ ref('stg_olist_order_items') }}
)
SELECT
    order_id,
    COUNT(*) AS item_count,
    ROUND(SUM(price)::numeric, 2) AS order_revenue,
    ROUND(SUM(freight_value)::numeric, 2) AS order_freight
FROM items
GROUP BY order_id
