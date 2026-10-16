-- Mart: fact_orders
-- Grain: order_id (order-level)
-- Revenue is item-based (sum of item prices) to avoid duplicating payment
-- amounts via one-to-many joins. Payments live in fact_payments.

{{ config(
    materialized='incremental',
    unique_key='order_id',
    incremental_strategy='delete+insert'
) }}

WITH orders AS (
    SELECT
        o.*,
        c.customer_unique_id
    FROM {{ ref('stg_olist_orders') }} o
    LEFT JOIN {{ ref('stg_olist_customers') }} c
      ON c.customer_id = o.customer_id
),
order_items AS (
    SELECT * FROM {{ ref('int_orders__order_items') }}
)
SELECT
    o.order_id,
    dc.customer_key,
    TO_CHAR(o.order_purchase_timestamp::date, 'YYYYMMDD')::int AS order_date_key,
    o.order_status,
    o.order_purchase_timestamp,
    COALESCE(oi.order_revenue, 0) AS order_revenue,
    COALESCE(oi.order_freight, 0) AS order_freight,
    COALESCE(oi.item_count, 0) AS item_count
FROM orders o
LEFT JOIN {{ ref('dim_customer') }} dc
  ON dc.customer_unique_id = o.customer_unique_id
LEFT JOIN order_items oi
  ON oi.order_id = o.order_id

{% if is_incremental() %}
  WHERE o.order_purchase_timestamp::date > (
      SELECT MAX(order_purchase_timestamp)::date FROM {{ this }}
  )
{% endif %}
