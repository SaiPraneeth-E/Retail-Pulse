-- Intermediate: order-level payment aggregation
-- Grain: order_id
-- Payments are aggregated at order grain so they never duplicate order revenue
-- when joined to fact_orders.

{{ config(materialized='table') }}

WITH payments AS (
    SELECT *
    FROM {{ ref('stg_olist_order_payments') }}
)
SELECT
    order_id,
    COUNT(*) AS payment_count,
    ROUND(SUM(payment_value)::numeric, 2) AS order_payment_value,
    STRING_AGG(DISTINCT payment_type, ', ') AS payment_types
FROM payments
GROUP BY order_id
