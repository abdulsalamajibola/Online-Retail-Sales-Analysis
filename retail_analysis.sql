-- ============================================================
-- Online Retail Sales Analysis
-- Tools: MySQL + Power BI
-- Purpose: Clean and analyse transactional retail data
-- ============================================================

CREATE DATABASE IF NOT EXISTS retail_analysis;
USE retail_analysis;

-- ============================================================
-- 1. RAW DATA TABLE
-- ============================================================
-- The source CSV was imported into this table using MySQL Workbench.
-- A local file path is intentionally omitted so the script is portable.

CREATE TABLE IF NOT EXISTS online_retail_raw (
    InvoiceNo   VARCHAR(20),
    StockCode   VARCHAR(20),
    Description VARCHAR(255),
    Quantity    INT,
    InvoiceDate DATETIME,
    UnitPrice   DECIMAL(12,4),
    CustomerID  VARCHAR(20),
    Country     VARCHAR(100)
);

-- Confirm raw row count.
SELECT COUNT(*) AS total_rows
FROM online_retail_raw;

-- ============================================================
-- 2. DATA QUALITY ASSESSMENT
-- ============================================================

-- Check missing values in key fields.
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN InvoiceNo IS NULL OR TRIM(InvoiceNo) = '' THEN 1 ELSE 0 END) AS missing_invoice_no,
    SUM(CASE WHEN StockCode IS NULL OR TRIM(StockCode) = '' THEN 1 ELSE 0 END) AS missing_stock_code,
    SUM(CASE WHEN Description IS NULL OR TRIM(Description) = '' THEN 1 ELSE 0 END) AS missing_description,
    SUM(CASE WHEN CustomerID IS NULL OR TRIM(CustomerID) = '' THEN 1 ELSE 0 END) AS missing_customer_id,
    SUM(CASE WHEN Country IS NULL OR TRIM(Country) = '' THEN 1 ELSE 0 END) AS missing_country
FROM online_retail_raw;

-- Investigate negative quantities and identify cancelled invoices.
SELECT
    COUNT(*) AS total_negative_quantity,
    SUM(CASE WHEN InvoiceNo LIKE 'C%' THEN 1 ELSE 0 END) AS cancellation_invoices,
    SUM(CASE WHEN InvoiceNo NOT LIKE 'C%' THEN 1 ELSE 0 END) AS negative_without_c
FROM online_retail_raw
WHERE Quantity < 0;

-- Investigate zero and negative prices.
SELECT
    SUM(CASE WHEN UnitPrice = 0 THEN 1 ELSE 0 END) AS zero_price,
    SUM(CASE WHEN UnitPrice < 0 THEN 1 ELSE 0 END) AS negative_price,
    MIN(UnitPrice) AS minimum_price,
    MAX(UnitPrice) AS maximum_price
FROM online_retail_raw;

-- ============================================================
-- 3. DATA CLEANING
-- ============================================================
-- Cleaning decisions:
--   * Keep only positive quantities and prices.
--   * Exclude cancelled invoices.
--   * Remove rows without a valid product description.
--   * Exclude administrative/non-product stock codes.
--   * Retain rows with missing CustomerID for sales analysis.
--     CustomerID is filtered only for customer-level analysis.

DROP TABLE IF EXISTS online_retail_clean;

CREATE TABLE online_retail_clean AS
SELECT
    InvoiceNo,
    StockCode,
    TRIM(Description) AS Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    TRIM(Country) AS Country,
    ROUND(Quantity * UnitPrice, 2) AS TotalSales
FROM online_retail_raw
WHERE Quantity > 0
  AND UnitPrice > 0
  AND InvoiceNo NOT LIKE 'C%'
  AND Description IS NOT NULL
  AND TRIM(Description) <> ''
  AND StockCode NOT IN ('AMAZONFEE', 'B', 'POST', 'DOT', 'M');

-- ============================================================
-- 4. CLEANING VALIDATION
-- ============================================================

SELECT
    COUNT(*) AS clean_rows,
    COUNT(DISTINCT InvoiceNo) AS unique_invoices,
    COUNT(DISTINCT StockCode) AS unique_products,
    ROUND(SUM(TotalSales), 2) AS total_revenue,
    MIN(InvoiceDate) AS first_transaction,
    MAX(InvoiceDate) AS last_transaction
FROM online_retail_clean;

-- ============================================================
-- 5. OVERALL SALES PERFORMANCE
-- ============================================================

SELECT
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    COUNT(DISTINCT StockCode) AS total_products,
    SUM(Quantity) AS total_units_sold,
    ROUND(SUM(TotalSales), 2) AS total_revenue,
    ROUND(SUM(TotalSales) / COUNT(DISTINCT InvoiceNo), 2) AS average_order_value
FROM online_retail_clean;

-- Monthly sales performance.
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS sales_month,
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS monthly_revenue,
    ROUND(SUM(TotalSales) / COUNT(DISTINCT InvoiceNo), 2) AS average_order_value
FROM online_retail_clean
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY sales_month;

-- Best-performing month by revenue.
SELECT
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS sales_month,
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS total_revenue,
    ROUND(SUM(TotalSales) / COUNT(DISTINCT InvoiceNo), 2) AS average_order_value
FROM online_retail_clean
GROUP BY DATE_FORMAT(InvoiceDate, '%Y-%m')
ORDER BY total_revenue DESC
LIMIT 1;

-- Sales performance by day of week.
SELECT
    DAYNAME(InvoiceDate) AS day_of_week,
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS total_revenue
FROM online_retail_clean
GROUP BY DAYNAME(InvoiceDate)
ORDER BY total_revenue DESC;

-- Average number of units per order.
SELECT
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS total_units_sold,
    ROUND(SUM(Quantity) / COUNT(DISTINCT InvoiceNo), 2) AS average_items_per_order
FROM online_retail_clean;

-- ============================================================
-- 6. PRODUCT ANALYSIS
-- ============================================================

-- Top 10 products by revenue.
SELECT
    StockCode,
    Description,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS product_revenue
FROM online_retail_clean
GROUP BY StockCode, Description
ORDER BY product_revenue DESC
LIMIT 10;

-- Top 10 products by units sold.
SELECT
    StockCode,
    Description,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS product_revenue
FROM online_retail_clean
GROUP BY StockCode, Description
ORDER BY units_sold DESC
LIMIT 10;

-- Revenue contribution of the top 10 individual products.
SELECT
    StockCode,
    Description,
    ROUND(SUM(TotalSales), 2) AS product_revenue,
    ROUND(
        SUM(TotalSales) * 100.0 /
        (SELECT SUM(TotalSales) FROM online_retail_clean),
        2
    ) AS revenue_percentage
FROM online_retail_clean
GROUP BY StockCode, Description
ORDER BY product_revenue DESC
LIMIT 10;

-- Combined share of revenue generated by the top 10 products.
WITH product_sales AS (
    SELECT
        StockCode,
        Description,
        SUM(TotalSales) AS product_revenue
    FROM online_retail_clean
    GROUP BY StockCode, Description
    ORDER BY product_revenue DESC
    LIMIT 10
)
SELECT
    ROUND(SUM(product_revenue), 2) AS top_10_revenue,
    ROUND(
        SUM(product_revenue) * 100.0 /
        (SELECT SUM(TotalSales) FROM online_retail_clean),
        2
    ) AS top_10_revenue_percentage
FROM product_sales;

-- ============================================================
-- 7. GEOGRAPHIC ANALYSIS
-- ============================================================

-- Revenue and order performance by country.
SELECT
    Country,
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS country_revenue
FROM online_retail_clean
GROUP BY Country
ORDER BY country_revenue DESC;

-- Top 10 international markets, excluding the United Kingdom.
SELECT
    Country,
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS units_sold,
    ROUND(SUM(TotalSales), 2) AS total_revenue
FROM online_retail_clean
WHERE Country <> 'United Kingdom'
GROUP BY Country
ORDER BY total_revenue DESC
LIMIT 10;

-- ============================================================
-- 8. CUSTOMER ANALYSIS
-- ============================================================
-- Customer-level queries exclude blank CustomerID values.

-- Top 10 identifiable customers by revenue.
SELECT
    CustomerID,
    COUNT(DISTINCT InvoiceNo) AS total_orders,
    SUM(Quantity) AS units_purchased,
    ROUND(SUM(TotalSales), 2) AS customer_revenue
FROM online_retail_clean
WHERE LENGTH(TRIM(CustomerID)) > 0
GROUP BY CustomerID
ORDER BY customer_revenue DESC
LIMIT 10;

-- Customer purchase behaviour: one-time vs repeat customers.
SELECT
    CASE
        WHEN total_orders = 1 THEN 'One-time Customer'
        ELSE 'Repeat Customer'
    END AS customer_type,
    COUNT(*) AS number_of_customers
FROM (
    SELECT
        CustomerID,
        COUNT(DISTINCT InvoiceNo) AS total_orders
    FROM online_retail_clean
    WHERE LENGTH(TRIM(CustomerID)) > 0
    GROUP BY CustomerID
) AS customer_orders
GROUP BY customer_type;

-- Repeat purchase rate.
SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN total_orders = 1 THEN 1 ELSE 0 END) AS one_time_customers,
    SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    ROUND(
        100.0 * SUM(CASE WHEN total_orders > 1 THEN 1 ELSE 0 END) / COUNT(*),
        2
    ) AS repeat_customer_rate
FROM (
    SELECT
        CustomerID,
        COUNT(DISTINCT InvoiceNo) AS total_orders
    FROM online_retail_clean
    WHERE LENGTH(TRIM(CustomerID)) > 0
    GROUP BY CustomerID
) AS customer_orders;

-- Identifiable customer KPIs.
SELECT
    COUNT(DISTINCT CustomerID) AS unique_customers,
    ROUND(SUM(TotalSales), 2) AS identified_customer_revenue,
    ROUND(SUM(TotalSales) / COUNT(DISTINCT CustomerID), 2) AS average_revenue_per_customer
FROM online_retail_clean
WHERE LENGTH(TRIM(CustomerID)) > 0;

-- CTE example: top customers by revenue.
WITH customer_sales AS (
    SELECT
        CustomerID,
        ROUND(SUM(TotalSales), 2) AS total_revenue
    FROM online_retail_clean
    WHERE LENGTH(TRIM(CustomerID)) > 0
    GROUP BY CustomerID
)
SELECT *
FROM customer_sales
ORDER BY total_revenue DESC
LIMIT 10;
