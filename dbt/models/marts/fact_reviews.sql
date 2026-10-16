-- Mart: fact_reviews
-- Grain: review_id (one review per order)

{{ config(materialized='table') }}

WITH reviews AS (
    SELECT * FROM {{ ref('int_orders__reviews') }}
)
SELECT
    r.review_id,
    r.order_id,
    r.review_score,
    TO_CHAR(r.review_creation_date::date, 'YYYYMMDD')::int AS review_date_key,
    r.has_comment
FROM reviews r
