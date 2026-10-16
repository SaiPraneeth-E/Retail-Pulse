# RetailPulse — Microsoft Power BI Dashboard Specification

## Semantic Model Architecture

The Power BI semantic model connects to the **PostgreSQL `analytics` schema** via DirectQuery or Scheduled Import (via On-Premises Data Gateway).

### Star Schema Relationships

```text
[dim_date] (date_key) 1──────<* [fact_orders] (order_date_key)
[dim_customer] (customer_key) 1──────<* [fact_orders] (customer_key)

[dim_date] (date_key) 1──────<* [fact_delivery_performance] (order_date_key)
[dim_customer] (customer_key) 1──────<* [fact_delivery_performance] (customer_key)
[fact_orders] (order_id) 1──────1 [fact_delivery_performance] (order_id)

[dim_product] (product_key) 1──────<* [fact_order_items] (product_key)
[dim_seller] (seller_key) 1──────<* [fact_order_items] (seller_key)
[fact_orders] (order_id) 1──────<* [fact_order_items] (order_id)

[fact_orders] (order_id) 1──────<* [fact_payments] (order_id)
[fact_orders] (order_id) 1──────<* [fact_reviews] (order_id)
```

> **Data Integrity Guardrail**: Revenue is always calculated from `fact_orders[order_revenue]` at the order grain, or from `fact_order_items[price]` when analyzing by product, seller, or category. Payments are stored in `fact_payments` and are never cross-joined directly to line items to prevent fan-out inflation.

---

## 5-Page Dashboard Layout & Visual Specifications

### Page 1: Executive Overview
*Target Audience: VP of E-Commerce, Chief Operating Officer, Commercial Directors*

1. **KPI Header Cards (Top Row)**:
   - **Total Net Revenue**: `[Total Revenue]` (formatted as currency `$ #,##0`)
   - **Total Orders**: `[Total Orders]` (formatted `#,#00`)
   - **Average Order Value (AOV)**: `[Average Order Value]` (`$ #,##0.00`)
   - **Average Customer Rating**: `[Average Review Score]` (`0.0 ★`)
   - **On-Time Delivery Rate**: `[On-Time Delivery Rate]` (`0.0%`)
2. **Main Visuals (Middle Grid)**:
   - **Revenue & Order Trend (Area + Line Combo Chart)**:
     - X-Axis: `dim_date[month_name]` / `dim_date[year]`
     - Column Y-Axis: `[Total Revenue]`
     - Line Y-Axis: `[Total Orders]`
     - Tooltips: `[Revenue MoM Growth %]`, `[Revenue YoY Growth %]`
   - **Geographic Sales Heatmap (Choropleth Map / Filled Map)**:
     - Location: `dim_customer[customer_state]` (Brazilian federative units: SP, RJ, MG, etc.)
     - Color Saturation: `[Total Revenue]`
     - Tooltip: `[Total Orders]`, `[Average Order Value]`
3. **Bottom Row Visuals**:
   - **Top 10 Product Categories by Revenue (Horizontal Bar Chart)**:
     - Y-Axis: `dim_product[product_category_name_english]`
     - X-Axis: `[Category Revenue]`
     - Data Labels: Enabled
   - **Order Status Distribution (Donut Chart)**:
     - Legend: `fact_orders[order_status]` (`delivered`, `shipped`, `canceled`)
     - Values: `[Total Orders]`
4. **Slicers**:
   - Date Range Slider: `dim_date[full_date]`
   - State Multi-Select: `dim_customer[customer_state]`
   - Order Status Dropdown: `fact_orders[order_status]`

---

### Page 2: Product & Category Analysis
*Target Audience: Category Managers, Merchandising Leads*

1. **Summary KPIs**:
   - Total Active Categories, Total Products Sold, Category Average Item Price, Freight Ratio %
2. **Category Performance Matrix (Table / Matrix with conditional formatting)**:
   - Rows: `dim_product[product_category_name_english]`
   - Columns: `[Category Revenue]`, `[Category Revenue % of Total]`, `[Category Units Sold]`, `[Category Average Item Price]`, `[Freight Ratio %]`
   - Conditional Formatting: Background data bars on Revenue, Color scale on Freight Ratio.
3. **Category Revenue vs Freight Cost (Scatter Plot)**:
   - X-Axis: `[Category Freight Value]`
   - Y-Axis: `[Category Revenue]`
   - Size: `[Category Units Sold]`
   - Legend: `dim_product[product_category_name_english]`
4. **Product Drill-Through Table**:
   - Displays `product_id`, category, units sold, total revenue, average item price, and product dimensions (weight, length, height).

---

### Page 3: Seller Performance
*Target Audience: Marketplace Operations, Seller Relationship Managers*

1. **Top Sellers Leaderboard (Ranked Bar Chart)**:
   - Y-Axis: `dim_seller[seller_id]` (Top 20 filter)
   - X-Axis: `[Seller Total Revenue]`
   - Color: Dynamic by `[Seller Average Rating]` (Red < 3.5, Yellow 3.5-4.2, Green > 4.2)
2. **Seller Fulfillment & Quality Scatter (Quadrant Analysis)**:
   - X-Axis: `[Seller Late Delivery %]` (Target: < 10%)
   - Y-Axis: `[Seller Average Rating]` (Target: > 4.0)
   - Size: `[Seller Total Orders]`
   - Quadrant lines: Target thresholds separating high-performing from at-risk sellers.
3. **Seller State Breakdown (Treemap)**:
   - Category: `dim_seller[seller_state]`
   - Values: `[Seller Total Revenue]`

---

### Page 4: Customer & Geography
*Target Audience: Growth Marketing, Retention & CRM Teams*

1. **Customer Cohort & Retention KPIs**:
   - Total Unique Customers, Repeat Customers, Repeat Purchase Rate %, Average Customer Lifetime Value
2. **Repeat vs One-Time Customer Revenue (Stacked Bar Chart)**:
   - Grouping: `dim_date[year]`
   - Segments: One-Time Buyers vs Repeat Buyers
   - Metric: Revenue and Order Counts
3. **State-Level Order & Revenue Density (Matrix)**:
   - State, Total Customers, Total Orders, Total Revenue, AOV, Avg Shipping Days.
4. **Installment & Payment Method Distribution (Clustered Column Chart)**:
   - X-Axis: `fact_payments[payment_type]` (`credit_card`, `boleto`, `voucher`, `debit_card`)
   - Values: `SUM(fact_payments[payment_value])`, `COUNT(fact_payments[order_id])`
   - Secondary Dimension: `fact_payments[payment_installments]`

---

### Page 5: Delivery & Customer Satisfaction
*Target Audience: Logistics Directors, Customer Support Leadership*

1. **Delivery Metrics Summary**:
   - On-Time Delivery Rate %, Average Transit Days, Average Delay Days, Negative Review Rate (1-2 Stars)
2. **Estimated vs Actual Delivery Timeline (Histogram / Distribution)**:
   - X-Axis: Delivery Delay Bucket (`Early`, `On time`, `1-7 days late`, `8-30 days late`, `30+ days late`)
   - Y-Axis: Order Count
   - Secondary Axis: Average Review Score (line overlay illustrating score collapse as delays increase)
3. **Delay Impact on Customer Reviews (Box Plot / Clustered Column)**:
   - Shows the precipitous drop in customer rating from 4.3 stars for on-time orders down to 1.4 stars for orders delayed > 7 days.
4. **Logistics Bottlenecks by Destination State (Heat Table)**:
   - Destination State vs Average Shipping Duration vs Delay Frequency.

---

## Power BI Theme & Palette

- **Theme**: Slate Dark / Modern Minimalist
- **Primary Brand Color**: `#1E3A8A` (Deep Indigo)
- **Accent Revenue**: `#0EA5E9` (Sky Blue)
- **Positive Accent (On-Time / High Rating)**: `#10B981` (Emerald Green)
- **Warning Accent**: `#F59E0B` (Amber)
- **Critical Accent (Late / Low Rating)**: `#EF4444` (Coral Red)
- **Font**: Segoe UI / Aptos
