-- Intermediate: reviews joined to orders
-- Grain: review_id (one review per order, deduplicated on review_id)

{{ config(materialized='table') }}

WITH ranked_reviews AS (
    SELECT
        review_id,
        order_id,
        review_score,
        review_creation_date,
        review_answer_timestamp,
        (review_comment_message IS NOT NULL) AS has_comment,
        ROW_NUMBER() OVER (
            PARTITION BY review_id
            ORDER BY review_answer_timestamp DESC NULLS LAST
        ) AS rn
    FROM {{ ref('stg_olist_order_reviews') }}
)
SELECT
    review_id,
    order_id,
    review_score,
    review_creation_date,
    review_answer_timestamp,
    has_comment
FROM ranked_reviews
WHERE rn = 1
