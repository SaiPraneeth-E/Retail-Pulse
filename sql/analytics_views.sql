-- RetailPulse analytics views for Power BI and analytical queries.
-- Each view documents its grain. Views query the mart layer only.
-- All views are constructed to eliminate fan-out and revenue double-counting.

CREATE SCHEMA IF NOT EXISTS analytics;

-- 1. Executive KPIs (Grain: one row summary)
-- Revenue and order counts are derived strictly from fact_orders to prevent join inflation.
CREATE OR REPLACE VIEW analytics.vw_executive_kpis AS
WITH order_kpis AS (
    SELECT
        COUNT(fo.order_id) AS total_orders,
        ROUND(COALESCE(SUM(fo.order_revenue), 0)::numeric, 2) AS total_revenue,
        ROUND(COALESCE(AVG(fo.order_revenue), 0)::numeric, 2) AS average_order_value,
        MAX(dd.full_date) AS latest_order_date
    FROM analytics.fact_orders fo
    LEFT JOIN analytics.dim_date dd ON dd.date_key = fo.order_date_key
),
review_kpis AS (
    SELECT
        ROUND(COALESCE(AVG(review_score), 0)::numeric, 2) AS average_review_score
    FROM analytics.fact_reviews
),
delivery_kpis AS (
    SELECT
        ROUND(100.0 * COUNT(CASE WHEN NOT is_late AND is_delivered THEN 1 END)::numeric /
              NULLIF(COUNT(CASE WHEN is_delivered THEN 1 END), 0), 2) AS on_time_delivery_pct
    FROM analytics.fact_delivery_performance
)
SELECT
    o.total_orders,
    o.total_revenue,
    o.average_order_value,
    r.average_review_score,
    d.on_time_delivery_pct,
    o.latest_order_date
FROM order_kpis o
CROSS JOIN review_kpis r
CROSS JOIN delivery_kpis d;

-- 2. Sales trends over time (Grain: month)
CREATE OR REPLACE VIEW analytics.vw_sales_trends AS
SELECT
    dd.year,
    dd.month,
    dd.month_name,
    TO_CHAR(MAKE_DATE(dd.year, dd.month, 1), 'YYYY-MM-01')::date AS month_start,
    COUNT(DISTINCT fo.order_id) AS orders,
    ROUND(SUM(fo.order_revenue)::numeric, 2) AS revenue,
    CASE WHEN COUNT(*) > 0
         THEN ROUND(AVG(fo.order_revenue)::numeric, 2)
    END AS average_order_value
FROM analytics.fact_orders fo
JOIN analytics.dim_date dd ON dd.date_key = fo.order_date_key
GROUP BY dd.year, dd.month, dd.month_name
ORDER BY dd.year, dd.month;

-- 3. Category performance (Grain: product category)
CREATE OR REPLACE VIEW analytics.vw_category_performance AS
SELECT
    COALESCE(dp.product_category_name_english, dp.product_category_name, 'Unknown') AS category,
    dp.product_category_name AS category_portuguese,
    COUNT(DISTINCT foi.order_id) AS orders,
    COUNT(foi.order_item_id) AS items_sold,
    ROUND(SUM(foi.price)::numeric, 2) AS revenue,
    ROUND(AVG(foi.price)::numeric, 2) AS avg_item_price,
    ROUND(SUM(foi.freight_value)::numeric, 2) AS total_freight
FROM analytics.fact_order_items foi
JOIN analytics.dim_product dp ON dp.product_key = foi.product_key
GROUP BY dp.product_category_name, dp.product_category_name_english
ORDER BY revenue DESC;

-- 4. Product performance (Grain: product_id)
CREATE OR REPLACE VIEW analytics.vw_product_performance AS
SELECT
    dp.product_id,
    COALESCE(dp.product_category_name_english, dp.product_category_name, 'Unknown') AS category,
    COUNT(DISTINCT foi.order_id) AS orders,
    COUNT(foi.order_item_id) AS items_sold,
    ROUND(SUM(foi.price)::numeric, 2) AS revenue,
    ROUND(AVG(foi.price)::numeric, 2) AS avg_item_price
FROM analytics.fact_order_items foi
JOIN analytics.dim_product dp ON dp.product_key = foi.product_key
GROUP BY dp.product_id, dp.product_category_name, dp.product_category_name_english
ORDER BY revenue DESC;

-- 5. Seller performance (Grain: seller_id)
-- CTE aggregation eliminates Cartesian explosion when joining items, reviews, and delivery.
CREATE OR REPLACE VIEW analytics.vw_seller_performance AS
WITH seller_items AS (
    SELECT
        foi.seller_key,
        COUNT(DISTINCT foi.order_id) AS orders,
        COUNT(foi.order_item_id) AS items_sold,
        ROUND(SUM(foi.price)::numeric, 2) AS revenue
    FROM analytics.fact_order_items foi
    GROUP BY foi.seller_key
),
seller_reviews AS (
    SELECT
        foi.seller_key,
        ROUND(AVG(fr.review_score)::numeric, 2) AS avg_review_score
    FROM analytics.fact_order_items foi
    JOIN analytics.fact_reviews fr ON fr.order_id = foi.order_id
    GROUP BY foi.seller_key
),
seller_delivery AS (
    SELECT
        foi.seller_key,
        ROUND(100.0 * COUNT(CASE WHEN fd.is_late THEN 1 END)::numeric /
              NULLIF(COUNT(CASE WHEN fd.is_delivered THEN 1 END), 0), 2) AS late_delivery_pct
    FROM analytics.fact_order_items foi
    JOIN analytics.fact_delivery_performance fd ON fd.order_id = foi.order_id
    GROUP BY foi.seller_key
)
SELECT
    ds.seller_id,
    ds.seller_state,
    ds.seller_city,
    COALESCE(si.orders, 0) AS orders,
    COALESCE(si.items_sold, 0) AS items_sold,
    COALESCE(si.revenue, 0) AS revenue,
    sr.avg_review_score,
    sd.late_delivery_pct
FROM analytics.dim_seller ds
JOIN seller_items si ON si.seller_key = ds.seller_key
LEFT JOIN seller_reviews sr ON sr.seller_key = ds.seller_key
LEFT JOIN seller_delivery sd ON sd.seller_key = ds.seller_key
ORDER BY revenue DESC;

-- 6. Customer analytics (Grain: customer_unique_id)
CREATE OR REPLACE VIEW analytics.vw_customer_analytics AS
SELECT
    dc.customer_unique_id,
    dc.customer_state,
    dc.customer_city,
    COUNT(DISTINCT fo.order_id) AS total_orders,
    ROUND(SUM(fo.order_revenue)::numeric, 2) AS total_spent,
    CASE WHEN COUNT(*) > 0
         THEN ROUND(AVG(fo.order_revenue)::numeric, 2)
    END AS avg_order_value,
    MIN(dd.full_date) AS first_order_date,
    MAX(dd.full_date) AS last_order_date,
    CASE WHEN COUNT(DISTINCT fo.order_id) > 1 THEN TRUE ELSE FALSE END AS is_repeat_customer
FROM analytics.fact_orders fo
JOIN analytics.dim_customer dc ON dc.customer_key = fo.customer_key
JOIN analytics.dim_date dd ON dd.date_key = fo.order_date_key
GROUP BY dc.customer_unique_id, dc.customer_state, dc.customer_city
ORDER BY total_spent DESC;

-- 7. Delivery performance (Grain: order_id)
CREATE OR REPLACE VIEW analytics.vw_delivery_performance AS
SELECT
    fd.order_id,
    dc.customer_state,
    dd.year,
    dd.month,
    fd.delivery_days,
    fd.estimated_delivery_days,
    fd.delivery_delay_days,
    fd.is_late,
    fd.is_delivered,
    CASE
        WHEN NOT fd.is_delivered THEN 'In Transit / Not Delivered'
        WHEN fd.delivery_delay_days < 0 THEN 'Early'
        WHEN fd.delivery_delay_days = 0 THEN 'On time'
        WHEN fd.delivery_delay_days BETWEEN 1 AND 7 THEN '1-7 days late'
        WHEN fd.delivery_delay_days BETWEEN 8 AND 30 THEN '8-30 days late'
        ELSE '30+ days late'
    END AS delay_bucket
FROM analytics.fact_delivery_performance fd
JOIN analytics.dim_customer dc ON dc.customer_key = fd.customer_key
JOIN analytics.dim_date dd ON dd.date_key = fd.order_date_key;

-- 8. Review analytics (Grain: review_id)
CREATE OR REPLACE VIEW analytics.vw_review_analytics AS
SELECT
    fr.review_id,
    fr.order_id,
    fr.review_score,
    fr.has_comment,
    dc.customer_state,
    COALESCE(dp.product_category_name_english, dp.product_category_name, 'Unknown') AS category,
    dd.year AS review_year,
    dd.month AS review_month
FROM analytics.fact_reviews fr
JOIN analytics.fact_orders fo ON fo.order_id = fr.order_id
JOIN analytics.dim_customer dc ON dc.customer_key = fo.customer_key
LEFT JOIN analytics.fact_order_items foi ON foi.order_id = fr.order_id
LEFT JOIN analytics.dim_product dp ON dp.product_key = foi.product_key
LEFT JOIN analytics.dim_date dd ON dd.date_key = fr.review_date_key
GROUP BY fr.review_id, fr.order_id, fr.review_score, fr.has_comment,
         dc.customer_state, dp.product_category_name_english, dp.product_category_name,
         dd.year, dd.month;

-- 9. Geographic sales (Grain: customer state)
CREATE OR REPLACE VIEW analytics.vw_geographic_sales AS
SELECT
    dc.customer_state AS state,
    COUNT(DISTINCT fo.order_id) AS orders,
    ROUND(SUM(fo.order_revenue)::numeric, 2) AS revenue,
    CASE WHEN COUNT(*) > 0
         THEN ROUND(AVG(fo.order_revenue)::numeric, 2)
    END AS average_order_value
FROM analytics.fact_orders fo
JOIN analytics.dim_customer dc ON dc.customer_key = fo.customer_key
GROUP BY dc.customer_state
ORDER BY revenue DESC;

COMMENT ON VIEW analytics.vw_executive_kpis IS 'Grain: single-row KPI summary without double-counting.';
COMMENT ON VIEW analytics.vw_sales_trends IS 'Grain: month. Monthly revenue and order volume trends.';
COMMENT ON VIEW analytics.vw_category_performance IS 'Grain: product category. Category sales, order count, and freight.';
COMMENT ON VIEW analytics.vw_product_performance IS 'Grain: product. Product unit sales, revenue, and average price.';
COMMENT ON VIEW analytics.vw_seller_performance IS 'Grain: seller. Seller metrics calculated via CTE to avoid join duplication.';
COMMENT ON VIEW analytics.vw_customer_analytics IS 'Grain: customer_unique_id. Spending totals and repeat purchase flags.';
COMMENT ON VIEW analytics.vw_delivery_performance IS 'Grain: order. Shipping duration, delays, and delay classification buckets.';
COMMENT ON VIEW analytics.vw_review_analytics IS 'Grain: review. Review ratings contextualized by category and state.';
COMMENT ON VIEW analytics.vw_geographic_sales IS 'Grain: customer state. Geographic distribution of revenue and order volume.';
