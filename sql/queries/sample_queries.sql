-- RetailPulse sample analytical queries
-- Run against the retailpulse database in the analytics schema.

-- 1. Executive KPIs (order-level revenue, no double-counting)
SELECT
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(order_revenue)::numeric, 2) AS total_revenue,
    ROUND(AVG(order_revenue)::numeric, 2) AS average_order_value,
    ROUND(AVG(fr.review_score)::numeric, 2) AS average_review_score,
    ROUND(100.0 * SUM(CASE WHEN fd.is_late THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_delivery_pct
FROM analytics.fact_orders fo
LEFT JOIN analytics.fact_reviews fr ON fr.order_id = fo.order_id
LEFT JOIN analytics.fact_delivery_performance fd ON fd.order_id = fo.order_id;

-- 2. Sales trend over time (order-level, monthly)
SELECT
    dd.year,
    dd.month,
    dd.month_name,
    COUNT(DISTINCT fo.order_id) AS orders,
    ROUND(SUM(fo.order_revenue)::numeric, 2) AS revenue,
    ROUND(AVG(fo.order_revenue)::numeric, 2) AS aov
FROM analytics.fact_orders fo
JOIN analytics.dim_date dd ON dd.date_key = fo.order_date_key
GROUP BY dd.year, dd.month, dd.month_name
ORDER BY dd.year, dd.month;

-- 3. Category performance (revenue attributed once per item)
SELECT
    dp.product_category_name_english AS category,
    COUNT(DISTINCT foi.order_id) AS orders,
    COUNT(foi.order_item_id) AS items_sold,
    ROUND(SUM(foi.price)::numeric, 2) AS revenue,
    ROUND(AVG(foi.price)::numeric, 2) AS avg_item_price
FROM analytics.fact_order_items foi
JOIN analytics.dim_product dp ON dp.product_key = foi.product_key
GROUP BY dp.product_category_name_english
ORDER BY revenue DESC;

-- 4. Seller performance
SELECT
    ds.seller_id,
    ds.seller_state,
    COUNT(DISTINCT foi.order_id) AS orders,
    COUNT(foi.order_item_id) AS items_sold,
    ROUND(SUM(foi.price)::numeric, 2) AS revenue,
    ROUND(AVG(fr.review_score)::numeric, 2) AS avg_review_score
FROM analytics.fact_order_items foi
JOIN analytics.dim_seller ds ON ds.seller_key = foi.seller_key
LEFT JOIN analytics.fact_reviews fr ON fr.order_id = foi.order_id
GROUP BY ds.seller_id, ds.seller_state
ORDER BY revenue DESC;

-- 5. Geographic sales (customer geography)
SELECT
    dc.customer_state AS state,
    COUNT(DISTINCT fo.order_id) AS orders,
    ROUND(SUM(fo.order_revenue)::numeric, 2) AS revenue,
    ROUND(AVG(fo.order_revenue)::numeric, 2) AS aov
FROM analytics.fact_orders fo
JOIN analytics.dim_customer dc ON dc.customer_key = fo.customer_key
GROUP BY dc.customer_state
ORDER BY revenue DESC;

-- 6. Delivery delays vs review scores
SELECT
    CASE
        WHEN fd.delivery_delay_days < 0 THEN 'Early'
        WHEN fd.delivery_delay_days = 0 THEN 'On time'
        WHEN fd.delivery_delay_days BETWEEN 1 AND 7 THEN '1-7 days late'
        WHEN fd.delivery_delay_days BETWEEN 8 AND 30 THEN '8-30 days late'
        ELSE '30+ days late'
    END AS delivery_bucket,
    COUNT(*) AS orders,
    ROUND(AVG(fr.review_score)::numeric, 2) AS avg_review_score,
    ROUND(100.0 * SUM(CASE WHEN fr.review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS poor_review_pct
FROM analytics.fact_delivery_performance fd
JOIN analytics.fact_reviews fr ON fr.order_id = fd.order_id
WHERE fd.is_delivered
GROUP BY 1
ORDER BY MIN(fd.delivery_delay_days);

-- 7. Payment method patterns (payment-level grain, aggregated per order first)
SELECT
    fp.payment_type,
    COUNT(*) AS payment_count,
    ROUND(SUM(fp.payment_value)::numeric, 2) AS total_payment_value,
    ROUND(AVG(fp.payment_installments)::numeric, 1) AS avg_installments
FROM analytics.fact_payments fp
GROUP BY fp.payment_type
ORDER BY total_payment_value DESC;

-- 8. Categories with high sales but poor reviews
SELECT
    dp.product_category_name_english AS category,
    ROUND(SUM(foi.price)::numeric, 2) AS revenue,
    ROUND(AVG(fr.review_score)::numeric, 2) AS avg_review_score,
    COUNT(foi.order_item_id) AS items_sold
FROM analytics.fact_order_items foi
JOIN analytics.dim_product dp ON dp.product_key = foi.product_key
JOIN analytics.fact_reviews fr ON fr.order_id = foi.order_id
GROUP BY dp.product_category_name_english
HAVING AVG(fr.review_score) < 3.5
ORDER BY revenue DESC;
