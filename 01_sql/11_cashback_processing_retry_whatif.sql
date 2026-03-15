-- ============================================================
-- UPI Transaction Analytics Project
-- Script 11: Cashback ROI, Processing Cost & Retry Analysis
-- ============================================================

-- ============================================================
-- PART A: CASHBACK ROI ANALYSIS
-- ============================================================

-- -------------------------------------------------------
-- CB 1: Overall Cashback Economics
-- -------------------------------------------------------
SELECT
    COUNT(*)                                                                    AS total_txns,
    SUM(CASE WHEN cashback_amt > 0 THEN 1 ELSE 0 END)                        AS cashback_txns,
    ROUND(SUM(CASE WHEN cashback_amt > 0 THEN 1.0 ELSE 0 END)
          / COUNT(*) * 100, 2)                                                AS cashback_txn_pct,
    ROUND(SUM(cashback_amt), 2)                                               AS total_cashback_cost,
    ROUND(SUM(amount), 2)                                                     AS total_gmv,
    ROUND(SUM(CASE WHEN cashback_amt > 0 THEN amount ELSE 0 END), 2)        AS cashback_gmv,
    ROUND(SUM(CASE WHEN cashback_amt = 0 THEN amount ELSE 0 END), 2)        AS no_cashback_gmv,
    ROUND(SUM(cashback_amt) / NULLIF(SUM(amount), 0) * 100, 4)              AS cashback_as_pct_of_gmv,
    ROUND(SUM(amount) / NULLIF(SUM(cashback_amt), 0), 2)                    AS gmv_per_cashback_rupee
FROM fact_transactions
WHERE status = 'SUCCESS';

-- -------------------------------------------------------
-- CB 2: Cashback ROI by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    COUNT(CASE WHEN f.cashback_amt > 0 THEN 1 END)                          AS cashback_txns,
    ROUND(SUM(f.cashback_amt), 2)                                            AS total_cashback,
    ROUND(SUM(CASE WHEN f.cashback_amt > 0 THEN f.amount ELSE 0 END), 2)   AS cashback_gmv,
    ROUND(SUM(CASE WHEN f.cashback_amt > 0 THEN f.amount ELSE 0 END)
          / NULLIF(SUM(f.cashback_amt), 0), 2)                              AS gmv_per_cashback_rupee,
    ROUND(SUM(f.cashback_amt)
          / NULLIF(SUM(CASE WHEN f.cashback_amt > 0 THEN f.amount ELSE 0 END), 0) * 100, 4) AS cashback_rate_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY total_cashback DESC;

-- -------------------------------------------------------
-- CB 3: Monthly Cashback Trend
-- -------------------------------------------------------
SELECT
    STRFTIME('%Y-%m', txn_date)                                              AS month,
    ROUND(SUM(cashback_amt), 2)                                             AS total_cashback,
    ROUND(SUM(amount), 2)                                                   AS gmv,
    ROUND(SUM(cashback_amt) / NULLIF(SUM(amount), 0) * 100, 4)            AS cashback_rate_pct,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount), 0) * 100, 4)                              AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- CB 4: Cashback Cannibalisation Check
-- Compare avg spend: cashback users vs non-cashback users
-- -------------------------------------------------------
SELECT
    CASE WHEN cashback_amt > 0 THEN 'With Cashback' ELSE 'Without Cashback' END AS cashback_group,
    COUNT(DISTINCT customer_id)  AS unique_users,
    COUNT(*)                     AS txn_count,
    ROUND(SUM(amount), 2)       AS total_gmv,
    ROUND(AVG(amount), 2)       AS avg_txn_value,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT customer_id), 2) AS avg_txns_per_user
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY CASE WHEN cashback_amt > 0 THEN 'With Cashback' ELSE 'Without Cashback' END;

-- ============================================================
-- PART B: PROCESSING COST ANALYSIS
-- ============================================================

-- -------------------------------------------------------
-- PC 1: Processing Cost Summary
-- -------------------------------------------------------
SELECT
    ROUND(SUM(processing_fee_amt), 2)   AS total_processing_cost,
    ROUND(AVG(processing_fee_amt), 4)   AS avg_cost_per_txn,
    ROUND(MIN(processing_fee_amt), 4)   AS min_cost,
    ROUND(MAX(processing_fee_amt), 4)   AS max_cost,
    COUNT(*)                             AS txn_count,
    ROUND(SUM(processing_fee_amt) / NULLIF(SUM(amount), 0) * 100, 4) AS cost_as_pct_of_gmv
FROM fact_transactions
WHERE status = 'SUCCESS';

-- -------------------------------------------------------
-- PC 2: Processing Cost by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    ROUND(AVG(f.processing_fee_amt), 4)  AS avg_processing_cost,
    ROUND(SUM(f.processing_fee_amt), 2)  AS total_processing_cost,
    COUNT(*)                              AS txn_count,
    ROUND(SUM(f.processing_fee_amt) / NULLIF(SUM(f.amount), 0) * 100, 4) AS cost_pct_gmv
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY avg_processing_cost DESC;

-- ============================================================
-- PART C: RETRY ANALYSIS
-- ============================================================

-- -------------------------------------------------------
-- RT 1: Success Rate by Retry Count
-- -------------------------------------------------------
SELECT
    retry_count,
    COUNT(*)                                                               AS txn_count,
    SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END)                    AS success_count,
    ROUND(SUM(CASE WHEN status='SUCCESS' THEN 1.0 ELSE 0 END)
          / COUNT(*) * 100, 2)                                            AS success_rate_pct,
    ROUND(AVG(CASE WHEN status='SUCCESS' THEN processing_fee_amt END), 4) AS avg_processing_cost
FROM fact_transactions
GROUP BY retry_count
ORDER BY retry_count;

-- -------------------------------------------------------
-- RT 2: Cost of Retries (Wasted processing fees on failures)
-- -------------------------------------------------------
SELECT
    SUM(CASE WHEN status != 'SUCCESS' THEN processing_fee_amt ELSE 0 END) AS failed_processing_cost,
    SUM(CASE WHEN status = 'SUCCESS'  THEN processing_fee_amt ELSE 0 END) AS success_processing_cost,
    ROUND(SUM(CASE WHEN status != 'SUCCESS' THEN processing_fee_amt ELSE 0 END)
          / NULLIF(SUM(processing_fee_amt), 0) * 100, 2)                AS wasted_cost_pct
FROM fact_transactions;

-- -------------------------------------------------------
-- RT 3: Retry Distribution by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    f.retry_count,
    COUNT(*) AS txn_count,
    ROUND(AVG(f.amount), 2) AS avg_amount
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
GROUP BY ch.channel_name, f.retry_count
ORDER BY ch.channel_name, f.retry_count;

-- ============================================================
-- PART D: WHAT-IF ANALYSIS (SQL Scenarios)
-- ============================================================

-- -------------------------------------------------------
-- WI 1: What if MDR increases by 0.5%?
-- -------------------------------------------------------
SELECT
    'Current'                                                                    AS scenario,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2)  AS net_revenue,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount), 0) * 100, 4)                                   AS margin_pct
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT
    '+0.5% MDR',
    ROUND(SUM(((mdr_pct + 0.5)/100.0)*amount - cashback_amt - processing_fee_amt), 2),
    ROUND(SUM(((mdr_pct + 0.5)/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount), 0) * 100, 4)
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT
    '+1.0% MDR',
    ROUND(SUM(((mdr_pct + 1.0)/100.0)*amount - cashback_amt - processing_fee_amt), 2),
    ROUND(SUM(((mdr_pct + 1.0)/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount), 0) * 100, 4)
FROM fact_transactions WHERE status = 'SUCCESS';

-- -------------------------------------------------------
-- WI 2: What if Cashback is reduced by 10%, 25%, 50%?
-- -------------------------------------------------------
SELECT
    'Current'                                                                      AS scenario,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2)   AS net_revenue
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT '-10% Cashback',
    ROUND(SUM((mdr_pct/100.0)*amount - (cashback_amt * 0.90) - processing_fee_amt), 2)
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT '-25% Cashback',
    ROUND(SUM((mdr_pct/100.0)*amount - (cashback_amt * 0.75) - processing_fee_amt), 2)
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT '-50% Cashback',
    ROUND(SUM((mdr_pct/100.0)*amount - (cashback_amt * 0.50) - processing_fee_amt), 2)
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT 'Zero Cashback',
    ROUND(SUM((mdr_pct/100.0)*amount - processing_fee_amt), 2)
FROM fact_transactions WHERE status = 'SUCCESS';

-- -------------------------------------------------------
-- WI 3: Revenue Impact if Processing Cost drops by 5%
-- -------------------------------------------------------
SELECT
    'Current' AS scenario,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT '-5% Processing Cost',
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - (processing_fee_amt * 0.95)), 2)
FROM fact_transactions WHERE status = 'SUCCESS'
UNION ALL
SELECT '-10% Processing Cost',
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - (processing_fee_amt * 0.90)), 2)
FROM fact_transactions WHERE status = 'SUCCESS';

-- ============================================================
-- END OF SCRIPT 11
-- ============================================================
