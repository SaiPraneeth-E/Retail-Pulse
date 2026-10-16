-- Intermediate: delivery performance per order
-- Grain: order_id
-- delivery_delay_days > 0 means the order was delivered after the estimate.

{{ config(materialized='table') }}

WITH orders AS (
    SELECT *
    FROM {{ ref('stg_olist_orders') }}
)
SELECT
    order_id,
    customer_id,
    order_purchase_timestamp,
    order_delivered_customer_date AS delivered_at,
    order_estimated_delivery_date AS estimated_delivery_at,
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
             AND order_purchase_timestamp IS NOT NULL
        THEN (order_delivered_customer_date::date - order_purchase_timestamp::date)::int
    END AS delivery_days,
    CASE
        WHEN order_estimated_delivery_date IS NOT NULL
             AND order_purchase_timestamp IS NOT NULL
        THEN (order_estimated_delivery_date::date - order_purchase_timestamp::date)::int
    END AS estimated_delivery_days,
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
             AND order_estimated_delivery_date IS NOT NULL
        THEN (order_delivered_customer_date::date - order_estimated_delivery_date::date)::int
    END AS delivery_delay_days,
    CASE
        WHEN order_delivered_customer_date IS NOT NULL
             AND order_estimated_delivery_date IS NOT NULL
             AND order_delivered_customer_date > order_estimated_delivery_date
        THEN TRUE ELSE FALSE
    END AS is_late,
    (order_delivered_customer_date IS NOT NULL) AS is_delivered
FROM orders
