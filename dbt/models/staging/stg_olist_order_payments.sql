-- Staging: Olist order payments
-- Source: raw.olist_order_payments_dataset
-- Grain: (order_id, payment_sequential)

{{ config(materialized='view') }}

SELECT
    order_id,
    payment_sequential::int AS payment_sequential,
    payment_type,
    payment_installments::int AS payment_installments,
    NULLIF(TRIM(payment_value), '')::numeric AS payment_value
FROM {{ source('retailpulse_raw', 'olist_order_payments_dataset') }}
WHERE order_id IS NOT NULL
  AND payment_sequential IS NOT NULL
