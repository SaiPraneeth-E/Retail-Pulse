-- RetailPulse raw tables (source landing layer)
-- Loaded by ingestion/ingest.py from Olist CSV files.
-- Idempotent: ingestion truncates + reloads raw tables per run (safe to rerun).

CREATE SCHEMA IF NOT EXISTS raw;

DROP TABLE IF EXISTS raw.olist_customers_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_orders_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_order_items_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_order_payments_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_order_reviews_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_products_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_sellers_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_geolocation_dataset CASCADE;
DROP TABLE IF EXISTS raw.olist_product_category_name_translation CASCADE;

CREATE TABLE raw.olist_customers_dataset (
    customer_id               TEXT PRIMARY KEY,
    customer_unique_id        TEXT,
    customer_zip_code_prefix  TEXT,
    customer_city             TEXT,
    customer_state            TEXT
);

CREATE TABLE raw.olist_orders_dataset (
    order_id                 TEXT PRIMARY KEY,
    customer_id              TEXT,
    order_status             TEXT,
    order_purchase_timestamp TEXT,
    order_approved_at        TEXT,
    order_delivered_carrier_date TEXT,
    order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT
);

CREATE TABLE raw.olist_order_items_dataset (
    order_id                 TEXT,
    order_item_id            INTEGER,
    product_id               TEXT,
    seller_id                TEXT,
    shipping_limit_date      TEXT,
    price                    TEXT,
    freight_value            TEXT,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE raw.olist_order_payments_dataset (
    order_id                 TEXT,
    payment_sequential       INTEGER,
    payment_type             TEXT,
    payment_installments     INTEGER,
    payment_value            TEXT,
    PRIMARY KEY (order_id, payment_sequential)
);

-- Note: Olist dataset contains multiple orders evaluated under identical review_ids.
-- Using (review_id, order_id) composite PK guarantees zero row rejection during raw ingest.
CREATE TABLE raw.olist_order_reviews_dataset (
    review_id                TEXT,
    order_id                 TEXT,
    review_score             INTEGER,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TEXT,
    review_answer_timestamp  TEXT,
    PRIMARY KEY (review_id, order_id)
);

CREATE TABLE raw.olist_products_dataset (
    product_id               TEXT PRIMARY KEY,
    product_category_name    TEXT,
    product_name_length      TEXT,
    product_description_length TEXT,
    product_photos_qty       TEXT,
    product_weight_g         TEXT,
    product_length_cm        TEXT,
    product_height_cm        TEXT,
    product_width_cm         TEXT
);

CREATE TABLE raw.olist_sellers_dataset (
    seller_id                TEXT PRIMARY KEY,
    seller_zip_code_prefix   TEXT,
    seller_city              TEXT,
    seller_state             TEXT
);

-- Note: Raw geolocation is a GPS coordinates log (~1M rows). Multiple points exist
-- for the same zip prefix and city. Deduplication is performed in staging/marts.
CREATE TABLE raw.olist_geolocation_dataset (
    geolocation_id           BIGSERIAL PRIMARY KEY,
    geolocation_zip_code_prefix TEXT,
    geolocation_lat          TEXT,
    geolocation_lng          TEXT,
    geolocation_city         TEXT,
    geolocation_state        TEXT
);

CREATE TABLE raw.olist_product_category_name_translation (
    product_category_name    TEXT PRIMARY KEY,
    product_category_name_english TEXT
);

-- Ingestion audit log (one row per source file per run)
CREATE SCHEMA IF NOT EXISTS audit;
CREATE TABLE IF NOT EXISTS audit.ingestion_log (
    ingestion_id             BIGSERIAL PRIMARY KEY,
    source_file              TEXT NOT NULL,
    target_table             TEXT NOT NULL,
    started_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at              TIMESTAMPTZ,
    rows_read                INTEGER,
    rows_loaded              INTEGER,
    rows_rejected            INTEGER,
    status                   TEXT NOT NULL, -- STARTED, COMPLETED, FAILED
    error_message            TEXT,
    file_checksum            TEXT
);

COMMENT ON TABLE raw.olist_customers_dataset IS 'Raw Olist customers dataset.';
COMMENT ON TABLE raw.olist_orders_dataset IS 'Raw Olist orders dataset.';
COMMENT ON TABLE raw.olist_order_items_dataset IS 'Raw Olist order items dataset (grain: order + item).';
COMMENT ON TABLE raw.olist_order_payments_dataset IS 'Raw Olist payments dataset (grain: order + payment sequence).';
COMMENT ON TABLE raw.olist_order_reviews_dataset IS 'Raw Olist reviews dataset (grain: review + order).';
COMMENT ON TABLE raw.olist_products_dataset IS 'Raw Olist products dataset.';
COMMENT ON TABLE raw.olist_sellers_dataset IS 'Raw Olist sellers dataset.';
COMMENT ON TABLE raw.olist_geolocation_dataset IS 'Raw Olist geolocation coordinate measurements.';
COMMENT ON TABLE raw.olist_product_category_name_translation IS 'Raw Olist product category name translation.';
