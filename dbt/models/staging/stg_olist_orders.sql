-- Staging: Olist orders
-- Source: raw.olist_orders_dataset
-- Grain: order_id
-- Invalid dates are normalized to NULL rather than failing the load.

{{ config(materialized='view') }}

SELECT
    order_id,
    customer_id,
    order_status,
    {{ parse_timestamp('order_purchase_timestamp') }} AS order_purchase_timestamp,
    {{ parse_timestamp('order_approved_at') }} AS order_approved_at,
    {{ parse_timestamp('order_delivered_carrier_date') }} AS order_delivered_carrier_date,
    {{ parse_timestamp('order_delivered_customer_date') }} AS order_delivered_customer_date,
    {{ parse_timestamp('order_estimated_delivery_date') }} AS order_estimated_delivery_date
FROM {{ source('retailpulse_raw', 'olist_orders_dataset') }}
WHERE order_id IS NOT NULL
