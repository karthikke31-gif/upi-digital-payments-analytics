-- ============================================================
-- FILE: 02_etl_data_quality.sql
-- PURPOSE: ETL validation & data quality checks
-- RUN AFTER: Loading CSVs into tables
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- SECTION 1: ROW COUNT VALIDATION
-- ────────────────────────────────────────────────────────────

-- Total rows in fact table
SELECT 'fact_transactions' AS table_name, COUNT(*) AS row_count FROM fact_transactions
UNION ALL
SELECT 'dim_customer',  COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_merchant',  COUNT(*) FROM dim_merchant
UNION ALL
SELECT 'dim_channel',   COUNT(*) FROM dim_channel
UNION ALL
SELECT 'dim_city',      COUNT(*) FROM dim_city
UNION ALL
SELECT 'dim_date',      COUNT(*) FROM dim_date;

-- ────────────────────────────────────────────────────────────
-- SECTION 2: NULL / MISSING VALUE CHECKS
-- ────────────────────────────────────────────────────────────

-- Check for NULLs in key columns
SELECT
    SUM(CASE WHEN transaction_id      IS NULL THEN 1 ELSE 0 END) AS null_txn_id,
    SUM(CASE WHEN customer_id         IS NULL THEN 1 ELSE 0 END) AS null_customer,
    SUM(CASE WHEN amount              IS NULL THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN status              IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN channel_id          IS NULL THEN 1 ELSE 0 END) AS null_channel,
    SUM(CASE WHEN mdr_pct             IS NULL THEN 1 ELSE 0 END) AS null_mdr,
    SUM(CASE WHEN txn_date            IS NULL THEN 1 ELSE 0 END) AS null_date
FROM fact_transactions;

-- ────────────────────────────────────────────────────────────
-- SECTION 3: BUSINESS RULE VIOLATIONS
-- ────────────────────────────────────────────────────────────

-- 3a. Negative or zero transaction amounts
SELECT COUNT(*) AS invalid_amounts
FROM fact_transactions
WHERE amount <= 0;

-- 3b. MDR percentage out of realistic range (0% - 5%)
SELECT COUNT(*) AS invalid_mdr
FROM fact_transactions
WHERE mdr_pct < 0 OR mdr_pct > 5;

-- 3c. Cashback exceeding transaction amount
SELECT COUNT(*) AS cashback_exceeds_amount
FROM fact_transactions
WHERE cashback_amt > amount;

-- 3d. Processing fee exceeding 10% of amount
SELECT COUNT(*) AS high_processing_fee
FROM fact_transactions
WHERE processing_fee_amt > amount * 0.10;

-- 3e. Settlement date before transaction date
SELECT COUNT(*) AS invalid_settlement
FROM fact_transactions
WHERE settlement_date < txn_date;

-- 3f. Refunded amount on SUCCESS transactions (flag unusual)
SELECT COUNT(*) AS refunded_success_txns
FROM fact_transactions
WHERE status = 'SUCCESS' AND refunded_amt > 0;

-- ────────────────────────────────────────────────────────────
-- SECTION 4: REFERENTIAL INTEGRITY CHECKS
-- ────────────────────────────────────────────────────────────

-- 4a. Orphan customer IDs (in fact but not in dim)
SELECT COUNT(*) AS orphan_customers
FROM fact_transactions f
LEFT JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- 4b. Orphan merchant IDs
SELECT COUNT(*) AS orphan_merchants
FROM fact_transactions f
LEFT JOIN dim_merchant m ON f.merchant_id = m.merchant_id
WHERE m.merchant_id IS NULL;

-- 4c. Orphan channel IDs
SELECT COUNT(*) AS orphan_channels
FROM fact_transactions f
LEFT JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE ch.channel_id IS NULL;

-- 4d. Orphan city IDs
SELECT COUNT(*) AS orphan_cities
FROM fact_transactions f
LEFT JOIN dim_city ci ON f.city_id = ci.city_id
WHERE ci.city_id IS NULL;

-- ────────────────────────────────────────────────────────────
-- SECTION 5: DISTRIBUTION & OUTLIER CHECKS
-- ────────────────────────────────────────────────────────────

-- 5a. Transaction status distribution
SELECT status, COUNT(*) AS txn_count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM fact_transactions
GROUP BY status
ORDER BY txn_count DESC;

-- 5b. Amount distribution (min, max, avg, median-proxy)
SELECT
    ROUND(MIN(amount), 2)   AS min_amount,
    ROUND(MAX(amount), 2)   AS max_amount,
    ROUND(AVG(amount), 2)   AS avg_amount,
    COUNT(*)                AS total_txns
FROM fact_transactions
WHERE status = 'SUCCESS';

-- 5c. Extreme outliers (amount > 3x stddev from mean)
WITH stats AS (
    SELECT AVG(amount) AS mean_amt,
           AVG(amount * amount) - AVG(amount) * AVG(amount) AS variance
    FROM fact_transactions WHERE status = 'SUCCESS'
)
SELECT COUNT(*) AS outlier_transactions
FROM fact_transactions, stats
WHERE status = 'SUCCESS'
  AND ABS(amount - mean_amt) > 3 * SQRT(variance);

-- 5d. Daily GMV sanity check (spot days with zero or unusually low GMV)
SELECT txn_date,
       COUNT(*)        AS txn_count,
       ROUND(SUM(amount), 2) AS daily_gmv
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY txn_date
ORDER BY daily_gmv ASC
LIMIT 10;

-- ────────────────────────────────────────────────────────────
-- SECTION 6: DUPLICATE DETECTION
-- ────────────────────────────────────────────────────────────

-- 6a. Duplicate transaction IDs
SELECT transaction_id, COUNT(*) AS dup_count
FROM fact_transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1
LIMIT 10;

-- 6b. Potential duplicate transactions (same customer, amount, date, channel)
SELECT customer_id, txn_date, amount, channel_id, COUNT(*) AS potential_dups
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY customer_id, txn_date, amount, channel_id
HAVING COUNT(*) > 1
ORDER BY potential_dups DESC
LIMIT 20;

-- ────────────────────────────────────────────────────────────
-- SECTION 7: DATE RANGE & COVERAGE VALIDATION
-- ────────────────────────────────────────────────────────────

-- Date range of data
SELECT
    MIN(txn_date) AS earliest_date,
    MAX(txn_date) AS latest_date,
    COUNT(DISTINCT txn_date) AS distinct_dates,
    COUNT(DISTINCT strftime('%Y-%m', txn_date)) AS distinct_months
FROM fact_transactions;

-- Monthly transaction count (check for data gaps)
SELECT
    strftime('%Y-%m', txn_date) AS month,
    COUNT(*) AS txn_count,
    ROUND(SUM(amount), 2) AS monthly_gmv
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- ────────────────────────────────────────────────────────────
-- SECTION 8: CHANNEL & DEVICE DISTRIBUTION
-- ────────────────────────────────────────────────────────────

-- Channel breakdown
SELECT ch.channel_name, COUNT(*) AS txn_count
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
GROUP BY ch.channel_name;

-- Device OS breakdown
SELECT device_os, COUNT(*) AS txn_count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM fact_transactions
GROUP BY device_os
ORDER BY txn_count DESC;
