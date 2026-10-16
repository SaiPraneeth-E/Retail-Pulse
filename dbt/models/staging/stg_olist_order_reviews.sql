-- Staging: Olist order reviews
-- Source: raw.olist_order_reviews_dataset
-- Grain: review_id (one review per order)

{{ config(materialized='view') }}

SELECT
    review_id,
    order_id,
    review_score::int AS review_score,
    review_comment_title,
    review_comment_message,
    {{ parse_timestamp('review_creation_date') }} AS review_creation_date,
    {{ parse_timestamp('review_answer_timestamp') }} AS review_answer_timestamp
FROM {{ source('retailpulse_raw', 'olist_order_reviews_dataset') }}
WHERE review_id IS NOT NULL
  AND order_id IS NOT NULL
