-- ============================================================
-- UPI Transaction Analytics Project
-- Script 03: Data Quality Checks
-- Run BEFORE any analysis to validate data integrity
-- ============================================================

-- -------------------------------------------------------
-- CHECK 1: Row counts
-- -------------------------------------------------------
SELECT 'fact_transactions' AS table_name, COUNT(*) AS total_rows FROM fact_transactions
UNION ALL SELECT 'dim_customer',  COUNT(*) FROM dim_customer
UNION ALL SELECT 'dim_merchant',  COUNT(*) FROM dim_merchant
UNION ALL SELECT 'dim_channel',   COUNT(*) FROM dim_channel
UNION ALL SELECT 'dim_city',      COUNT(*) FROM dim_city
UNION ALL SELECT 'dim_date',      COUNT(*) FROM dim_date;

-- -------------------------------------------------------
-- CHECK 2: Null / Missing values in critical columns
-- -------------------------------------------------------
SELECT
    COUNT(*)                                          AS total_rows,
    SUM(CASE WHEN transaction_id   IS NULL THEN 1 ELSE 0 END) AS null_txn_id,
    SUM(CASE WHEN customer_id      IS NULL THEN 1 ELSE 0 END) AS null_customer,
    SUM(CASE WHEN merchant_id      IS NULL THEN 1 ELSE 0 END) AS null_merchant,
    SUM(CASE WHEN amount           IS NULL THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN mdr_pct          IS NULL THEN 1 ELSE 0 END) AS null_mdr,
    SUM(CASE WHEN status           IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN txn_date         IS NULL THEN 1 ELSE 0 END) AS null_date
FROM fact_transactions;

-- -------------------------------------------------------
-- CHECK 3: Invalid / negative amounts
-- -------------------------------------------------------
SELECT 'negative_amount'     AS issue, COUNT(*) AS count FROM fact_transactions WHERE amount < 0
UNION ALL
SELECT 'zero_amount',         COUNT(*) FROM fact_transactions WHERE amount = 0
UNION ALL
SELECT 'negative_cashback',   COUNT(*) FROM fact_transactions WHERE cashback_amt < 0
UNION ALL
SELECT 'negative_processing', COUNT(*) FROM fact_transactions WHERE processing_fee_amt < 0
UNION ALL
SELECT 'cashback_exceeds_mdr',COUNT(*) FROM fact_transactions
  WHERE cashback_amt > (mdr_pct/100.0) * amount;

-- -------------------------------------------------------
-- CHECK 4: Orphan transactions (missing dimension keys)
-- -------------------------------------------------------
SELECT 'missing_customer' AS issue, COUNT(*) AS orphan_count
FROM fact_transactions t
LEFT JOIN dim_customer c ON t.customer_id = c.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'missing_merchant', COUNT(*)
FROM fact_transactions t
LEFT JOIN dim_merchant m ON t.merchant_id = m.merchant_id
WHERE m.merchant_id IS NULL
UNION ALL
SELECT 'missing_channel', COUNT(*)
FROM fact_transactions t
LEFT JOIN dim_channel ch ON t.channel_id = ch.channel_id
WHERE ch.channel_id IS NULL
UNION ALL
SELECT 'missing_city', COUNT(*)
FROM fact_transactions t
LEFT JOIN dim_city ci ON t.city_id = ci.city_id
WHERE ci.city_id IS NULL
UNION ALL
SELECT 'missing_date', COUNT(*)
FROM fact_transactions t
LEFT JOIN dim_date d ON t.txn_date = d.date
WHERE d.date IS NULL;

-- -------------------------------------------------------
-- CHECK 5: Duplicate transactions
-- -------------------------------------------------------
SELECT transaction_id, COUNT(*) AS dup_count
FROM fact_transactions
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY dup_count DESC
LIMIT 10;

-- -------------------------------------------------------
-- CHECK 6: Transaction status distribution
-- -------------------------------------------------------
SELECT
    status,
    COUNT(*)                           AS txn_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM fact_transactions
GROUP BY status;

-- -------------------------------------------------------
-- CHECK 7: Date range and coverage
-- -------------------------------------------------------
SELECT
    MIN(txn_date) AS earliest_txn,
    MAX(txn_date) AS latest_txn,
    COUNT(DISTINCT txn_date) AS distinct_dates
FROM fact_transactions;

-- Dates in fact table NOT in dim_date (coverage gap)
SELECT COUNT(DISTINCT txn_date) AS fact_dates_not_in_dim
FROM fact_transactions f
LEFT JOIN dim_date d ON f.txn_date = d.date
WHERE d.date IS NULL;

-- -------------------------------------------------------
-- CHECK 8: MDR % range sanity
-- -------------------------------------------------------
SELECT
    MIN(mdr_pct) AS min_mdr,
    MAX(mdr_pct) AS max_mdr,
    AVG(mdr_pct) AS avg_mdr,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY mdr_pct) AS median_mdr
FROM fact_transactions
WHERE status = 'SUCCESS';

-- -------------------------------------------------------
-- CHECK 9: Outlier detection on transaction amount
-- -------------------------------------------------------
WITH stats AS (
    SELECT
        AVG(amount) AS mean_amt,
        STDDEV(amount) AS std_amt
    FROM fact_transactions WHERE status = 'SUCCESS'
)
SELECT COUNT(*) AS outlier_count
FROM fact_transactions f, stats s
WHERE status = 'SUCCESS'
  AND (f.amount > s.mean_amt + 3 * s.std_amt
    OR f.amount < s.mean_amt - 3 * s.std_amt);

-- -------------------------------------------------------
-- CHECK 10: Channel distribution (basic sanity)
-- -------------------------------------------------------
SELECT ch.channel_name, COUNT(*) AS txn_count
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
GROUP BY ch.channel_name
ORDER BY txn_count DESC;

-- ============================================================
-- END OF SCRIPT 03 — If all checks pass with zero/expected
-- counts, proceed to core KPI analysis.
-- ============================================================
