-- Mart: fact_delivery_performance
-- Grain: order_id
-- delivery_delay_days > 0 indicates a late delivery.

{{ config(materialized='table') }}

WITH delivery AS (
    SELECT
        d.*,
        c.customer_unique_id
    FROM {{ ref('int_order_delivery') }} d
    LEFT JOIN {{ ref('stg_olist_customers') }} c
      ON c.customer_id = d.customer_id
)
SELECT
    d.order_id,
    dc.customer_key,
    TO_CHAR(d.order_purchase_timestamp::date, 'YYYYMMDD')::int AS order_date_key,
    CASE WHEN d.delivered_at IS NOT NULL
         THEN TO_CHAR(d.delivered_at::date, 'YYYYMMDD')::int END AS delivered_date_key,
    CASE WHEN d.estimated_delivery_at IS NOT NULL
         THEN TO_CHAR(d.estimated_delivery_at::date, 'YYYYMMDD')::int END AS estimated_delivery_date_key,
    d.delivery_days,
    d.estimated_delivery_days,
    d.delivery_delay_days,
    d.is_late,
    d.is_delivered
FROM delivery d
LEFT JOIN {{ ref('dim_customer') }} dc
  ON dc.customer_unique_id = d.customer_unique_id
