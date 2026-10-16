-- RetailPulse dimensional model in the analytics schema.
-- Grains:
--   dim_customer        : one row per customer_unique_id
--   dim_product         : one row per product_id
--   dim_seller          : one row per seller_id
--   dim_date            : one row per calendar date
--   dim_geography       : one row per zip_code_prefix + city + state
--   fact_orders         : one row per order_id (order-level grain)
--   fact_order_items    : one row per (order_id, order_item_id) (item-level grain)
--   fact_payments       : one row per (order_id, payment_sequential) (payment-level grain)
--   fact_reviews        : one row per review_id (one review per order)
--   fact_delivery_performance: one row per order_id with delivery info
--
-- Payments and order items are NEVER joined at fact grain in a way that
-- duplicates revenue: each fact table keeps its own native grain.

-- Dimensions ----------------------------------------------------------------

DROP TABLE IF EXISTS analytics.fact_delivery_performance CASCADE;
DROP TABLE IF EXISTS analytics.fact_reviews CASCADE;
DROP TABLE IF EXISTS analytics.fact_payments CASCADE;
DROP TABLE IF EXISTS analytics.fact_order_items CASCADE;
DROP TABLE IF EXISTS analytics.fact_orders CASCADE;
DROP TABLE IF EXISTS analytics.dim_geography CASCADE;
DROP TABLE IF EXISTS analytics.dim_date CASCADE;
DROP TABLE IF EXISTS analytics.dim_seller CASCADE;
DROP TABLE IF EXISTS analytics.dim_product CASCADE;
DROP TABLE IF EXISTS analytics.dim_customer CASCADE;

CREATE TABLE analytics.dim_customer (
    customer_key           SERIAL PRIMARY KEY,
    customer_unique_id     TEXT NOT NULL UNIQUE,
    customer_id            TEXT NOT NULL,
    customer_city          TEXT,
    customer_state         TEXT,
    customer_zip_code_prefix TEXT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analytics.dim_product (
    product_key            SERIAL PRIMARY KEY,
    product_id             TEXT NOT NULL UNIQUE,
    product_category_name  TEXT,
    product_category_name_english TEXT,
    product_name_length    INTEGER,
    product_description_length INTEGER,
    product_photos_qty     INTEGER,
    product_weight_g       INTEGER,
    product_length_cm      INTEGER,
    product_height_cm      INTEGER,
    product_width_cm       INTEGER,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analytics.dim_seller (
    seller_key             SERIAL PRIMARY KEY,
    seller_id              TEXT NOT NULL UNIQUE,
    seller_city            TEXT,
    seller_state           TEXT,
    seller_zip_code_prefix TEXT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analytics.dim_geography (
    geography_key          SERIAL PRIMARY KEY,
    zip_code_prefix        TEXT NOT NULL,
    city                   TEXT,
    state                  TEXT,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (zip_code_prefix, city, state)
);

CREATE TABLE analytics.dim_date (
    date_key               INTEGER PRIMARY KEY, -- YYYYMMDD
    full_date              DATE NOT NULL UNIQUE,
    year                   INTEGER NOT NULL,
    month                  INTEGER NOT NULL,
    month_name             TEXT NOT NULL,
    day                    INTEGER NOT NULL,
    day_of_week            INTEGER NOT NULL,
    day_name               TEXT NOT NULL,
    quarter                INTEGER NOT NULL,
    is_weekend             BOOLEAN NOT NULL,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Facts ---------------------------------------------------------------------

-- Order-level grain: one row per order. Revenue here is the SUM of item prices
-- for the order (single source of truth for order revenue). Payment amounts are
-- kept in fact_payments to avoid double-counting via one-to-many joins.
CREATE TABLE analytics.fact_orders (
    order_key              SERIAL PRIMARY KEY,
    order_id               TEXT NOT NULL UNIQUE,
    customer_key           INTEGER REFERENCES analytics.dim_customer(customer_key),
    order_date_key         INTEGER REFERENCES analytics.dim_date(date_key),
    order_status           TEXT NOT NULL,
    order_revenue          NUMERIC(12,2) NOT NULL, -- sum of item prices for the order
    order_freight          NUMERIC(12,2) NOT NULL,
    item_count             INTEGER NOT NULL,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Item-level grain: one row per (order_id, order_item_id).
CREATE TABLE analytics.fact_order_items (
    order_item_key         SERIAL PRIMARY KEY,
    order_id               TEXT NOT NULL,
    order_item_id          INTEGER NOT NULL,
    product_key            INTEGER REFERENCES analytics.dim_product(product_key),
    seller_key             INTEGER REFERENCES analytics.dim_seller(seller_key),
    price                  NUMERIC(12,2) NOT NULL,
    freight_value          NUMERIC(12,2) NOT NULL,
    UNIQUE (order_id, order_item_id)
);

-- Payment-level grain: one row per (order_id, payment_sequential).
-- Joining this to fact_orders at order grain must aggregate payments first.
CREATE TABLE analytics.fact_payments (
    payment_key            SERIAL PRIMARY KEY,
    order_id               TEXT NOT NULL,
    payment_sequential     INTEGER NOT NULL,
    payment_type           TEXT NOT NULL,
    payment_installments   INTEGER NOT NULL,
    payment_value          NUMERIC(12,2) NOT NULL,
    UNIQUE (order_id, payment_sequential)
);

CREATE TABLE analytics.fact_reviews (
    review_key             SERIAL PRIMARY KEY,
    review_id              TEXT NOT NULL UNIQUE,
    order_id               TEXT NOT NULL,
    review_score           INTEGER NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_creation_date_key INTEGER REFERENCES analytics.dim_date(date_key),
    has_comment            BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE analytics.fact_delivery_performance (
    delivery_key           SERIAL PRIMARY KEY,
    order_id               TEXT NOT NULL UNIQUE,
    customer_key           INTEGER REFERENCES analytics.dim_customer(customer_key),
    order_date_key         INTEGER REFERENCES analytics.dim_date(date_key),
    delivered_date_key     INTEGER REFERENCES analytics.dim_date(date_key),
    estimated_delivery_date_key INTEGER REFERENCES analytics.dim_date(date_key),
    delivery_days          INTEGER, -- actual: delivered - purchased
    estimated_delivery_days INTEGER,
    delivery_delay_days    INTEGER, -- actual - estimated (positive = late)
    is_late                BOOLEAN NOT NULL DEFAULT FALSE,
    is_delivered           BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for dashboard query performance
CREATE INDEX idx_fact_orders_order_date ON analytics.fact_orders(order_date_key);
CREATE INDEX idx_fact_orders_customer ON analytics.fact_orders(customer_key);
CREATE INDEX idx_fact_order_items_order ON analytics.fact_order_items(order_id);
CREATE INDEX idx_fact_order_items_product ON analytics.fact_order_items(product_key);
CREATE INDEX idx_fact_order_items_seller ON analytics.fact_order_items(seller_key);
CREATE INDEX idx_fact_payments_order ON analytics.fact_payments(order_id);
CREATE INDEX idx_fact_reviews_order ON analytics.fact_reviews(order_id);
CREATE INDEX idx_fact_delivery_order_date ON analytics.fact_delivery_performance(order_date_key);
CREATE INDEX idx_dim_customer_state ON analytics.dim_customer(customer_state);
CREATE INDEX idx_dim_product_category ON analytics.dim_product(product_category_name_english);
CREATE INDEX idx_dim_seller_state ON analytics.dim_seller(seller_state);

-- Audit: data-quality results
CREATE TABLE IF NOT EXISTS audit.data_quality_results (
    quality_id             BIGSERIAL PRIMARY KEY,
    check_name             TEXT NOT NULL,
    table_name             TEXT NOT NULL,
    column_name            TEXT,
    check_type             TEXT NOT NULL,
    expected               TEXT,
    actual                 TEXT,
    passed                 BOOLEAN NOT NULL,
    checked_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    details                TEXT
);

COMMENT ON TABLE analytics.fact_orders IS 'Order-level fact. Grain: one row per order_id. Revenue is item-based to avoid payment join duplication.';
COMMENT ON TABLE analytics.fact_order_items IS 'Item-level fact. Grain: (order_id, order_item_id).';
COMMENT ON TABLE analytics.fact_payments IS 'Payment-level fact. Grain: (order_id, payment_sequential). Revenue reported separately from fact_orders.';
COMMENT ON TABLE analytics.fact_reviews IS 'Review-level fact. Grain: review_id (one review per order).';
COMMENT ON TABLE analytics.fact_delivery_performance IS 'Delivery performance fact. Grain: order_id.';
