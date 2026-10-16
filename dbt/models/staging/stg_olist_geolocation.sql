-- Staging: Olist geolocation
-- Source: raw.olist_geolocation_dataset
-- Grain: (zip_code_prefix, city, state)

{{ config(materialized='view') }}

SELECT
    geolocation_zip_code_prefix AS zip_code_prefix,
    NULLIF(TRIM(geolocation_lat), '')::numeric AS lat,
    NULLIF(TRIM(geolocation_lng), '')::numeric AS lng,
    geolocation_city AS city,
    geolocation_state AS state
FROM {{ source('retailpulse_raw', 'olist_geolocation_dataset') }}
WHERE geolocation_zip_code_prefix IS NOT NULL
