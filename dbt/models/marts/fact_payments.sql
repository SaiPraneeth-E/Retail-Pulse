-- Mart: fact_payments
-- Grain: (order_id, payment_sequential) (payment-level)
-- Kept separate from fact_orders to prevent revenue double-counting.

{{ config(
    materialized='incremental',
    unique_key=['order_id', 'payment_sequential'],
    incremental_strategy='delete+insert'
) }}

SELECT
    op.order_id,
    op.payment_sequential,
    op.payment_type,
    op.payment_installments,
    op.payment_value
FROM {{ ref('stg_olist_order_payments') }} op
