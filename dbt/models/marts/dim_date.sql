-- Mart: dim_date
-- Grain: calendar date (date_key = YYYYMMDD)
-- Generated from the min/max dates present in the orders data.

{{ config(materialized='table') }}

WITH bounds AS (
    SELECT
        COALESCE(
            (SELECT MIN(order_purchase_timestamp)::date FROM {{ ref('stg_olist_orders') }}),
            '2016-01-01'::date
        ) AS min_dt,
        COALESCE(
            (SELECT GREATEST(
                MAX(order_delivered_customer_date),
                MAX(order_estimated_delivery_date)
            )::date FROM {{ ref('stg_olist_orders') }}),
            '2018-12-31'::date
        ) AS max_dt
),
dates AS (
    SELECT generate_series(min_dt, max_dt, interval '1 day')::date AS full_date
    FROM bounds
)
SELECT
    TO_CHAR(full_date, 'YYYYMMDD')::int AS date_key,
    full_date,
    EXTRACT(year FROM full_date)::int AS year,
    EXTRACT(month FROM full_date)::int AS month,
    TRIM(TO_CHAR(full_date, 'Month')) AS month_name,
    EXTRACT(day FROM full_date)::int AS day,
    EXTRACT(dow FROM full_date)::int AS day_of_week,
    TRIM(TO_CHAR(full_date, 'Day')) AS day_name,
    EXTRACT(quarter FROM full_date)::int AS quarter,
    (EXTRACT(dow FROM full_date)::int IN (0, 6)) AS is_weekend
FROM dates
