-- Mart: dim_geography
-- Grain: (zip_code_prefix, city, state)

{{ config(materialized='table') }}

WITH geo AS (
    SELECT DISTINCT zip_code_prefix, city, state
    FROM {{ ref('stg_olist_geolocation') }}
    WHERE zip_code_prefix IS NOT NULL
)
SELECT
    ROW_NUMBER() OVER (ORDER BY zip_code_prefix, city, state) AS geography_key,
    zip_code_prefix,
    city,
    state
FROM geo
