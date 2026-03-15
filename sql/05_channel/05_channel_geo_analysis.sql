-- ============================================================
-- UPI TRANSACTION ANALYTICS PROJECT
-- FILE: 05_channel_geo_analysis.sql
-- PURPOSE: Channel Mix, Channel Efficiency, Geo GMV,
--          Merchant Analysis, Cashback ROI
-- ============================================================


-- ─────────────────────────────────────────
-- CHAN-01: CHANNEL MIX (GMV & Transaction Count)
-- Business use: Which channels dominate the platform?
-- ─────────────────────────────────────────

SELECT
    ch.channel_name,
    COUNT(f.transaction_id)                                          AS txn_count,
    ROUND(SUM(f.amount)::NUMERIC, 2)                                 AS gmv,
    ROUND(100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER (), 2)    AS gmv_share_pct,
    ROUND(AVG(f.amount)::NUMERIC, 2)                                 AS avg_txn_value,
    COUNT(DISTINCT f.customer_id)                                    AS unique_users
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY gmv DESC;


-- ─────────────────────────────────────────
-- CHAN-02: CHANNEL EFFICIENCY RATIO
-- Formula: Net Revenue / (Processing Cost + Cashback)
-- Higher ratio = more profitable channel
-- ─────────────────────────────────────────

SELECT
    ch.channel_name,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)::NUMERIC, 2)
                                                                    AS net_revenue,
    ROUND(SUM(f.processing_fee_amt + f.cashback_amt)::NUMERIC, 2)  AS total_cost,
    ROUND(SUM(f.cashback_amt)::NUMERIC, 2)                          AS cashback_cost,
    ROUND(SUM(f.processing_fee_amt)::NUMERIC, 2)                    AS processing_cost,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt) /
        NULLIF(SUM(f.processing_fee_amt + f.cashback_amt), 0)
    ::NUMERIC, 4)                                                   AS efficiency_ratio,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt) /
        NULLIF(SUM(f.amount), 0) * 100
    ::NUMERIC, 4)                                                   AS margin_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY efficiency_ratio DESC;


-- ─────────────────────────────────────────
-- CHAN-03: MONTHLY CHANNEL TREND
-- Business use: Is UPI growing faster than Card? Are any channels declining?
-- ─────────────────────────────────────────

SELECT
    TO_CHAR(DATE_TRUNC('month', f.txn_date), 'YYYY-MM')             AS month,
    ch.channel_name,
    COUNT(f.transaction_id)                                          AS txn_count,
    ROUND(SUM(f.amount)::NUMERIC, 2)                                 AS gmv
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY DATE_TRUNC('month', f.txn_date), ch.channel_name
ORDER BY month, gmv DESC;


-- ─────────────────────────────────────────
-- CHAN-04: CASHBACK ROI ANALYSIS
-- Business use: Is cashback actually generating enough GMV to justify cost?
-- Key metric: GMV per cashback rupee spent
-- ─────────────────────────────────────────

-- Overall platform cashback ROI
SELECT
    ROUND(SUM(f.amount)::NUMERIC, 2)         AS total_gmv,
    ROUND(SUM(f.cashback_amt)::NUMERIC, 2)   AS total_cashback_spent,
    ROUND(SUM(f.amount) / NULLIF(SUM(f.cashback_amt), 0)::NUMERIC, 2) AS gmv_per_cashback_rupee,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount) /
        NULLIF(SUM(f.cashback_amt), 0)
    ::NUMERIC, 2)                            AS mdr_revenue_per_cashback_rupee,
    ROUND(
        (SUM((f.mdr_pct/100.0)*f.amount) - SUM(f.cashback_amt) - SUM(f.processing_fee_amt)) /
        NULLIF(SUM(f.cashback_amt), 0)
    ::NUMERIC, 2)                            AS net_return_per_cashback_rupee
FROM fact_transactions f
WHERE f.status = 'SUCCESS';


-- Cashback ROI by Channel
SELECT
    ch.channel_name,
    ROUND(SUM(f.cashback_amt)::NUMERIC, 2)                          AS cashback_spent,
    ROUND(SUM(f.amount)::NUMERIC, 2)                                 AS gmv_generated,
    ROUND(SUM(f.amount) / NULLIF(SUM(f.cashback_amt), 0)::NUMERIC, 2) AS gmv_per_cashback_rupee,
    COUNT(*) FILTER (WHERE f.cashback_amt > 0)                      AS txns_with_cashback,
    COUNT(*)                                                         AS total_txns,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.cashback_amt > 0) / COUNT(*), 2)
                                                                    AS cashback_txn_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY gmv_per_cashback_rupee DESC;


-- Cashback ROI by Month (trend)
SELECT
    TO_CHAR(DATE_TRUNC('month', f.txn_date), 'YYYY-MM')            AS month,
    ROUND(SUM(f.cashback_amt)::NUMERIC, 2)                          AS cashback_spent,
    ROUND(SUM(f.amount)::NUMERIC, 2)                                 AS gmv,
    ROUND(SUM(f.amount) / NULLIF(SUM(f.cashback_amt), 0)::NUMERIC, 2) AS gmv_per_cashback_rupee
FROM fact_transactions f
WHERE f.status = 'SUCCESS'
GROUP BY DATE_TRUNC('month', f.txn_date)
ORDER BY month;


-- ─────────────────────────────────────────
-- CHAN-05: GEO-WISE GMV (State and City Level)
-- Business use: Which cities/states drive the most revenue?
-- ─────────────────────────────────────────

-- State level
SELECT
    ci.state,
    COUNT(f.transaction_id)                AS txn_count,
    COUNT(DISTINCT f.customer_id)          AS unique_users,
    ROUND(SUM(f.amount)::NUMERIC, 2)       AS gmv,
    ROUND(AVG(f.amount)::NUMERIC, 2)       AS avg_txn_value,
    ROUND(
        100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER ()
    ::NUMERIC, 2)                          AS state_gmv_share_pct
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.state
ORDER BY gmv DESC;


-- City level (Top 20)
SELECT
    ci.city_name,
    ci.state,
    ci.tier,
    COUNT(f.transaction_id)                AS txn_count,
    COUNT(DISTINCT f.customer_id)          AS unique_users,
    ROUND(SUM(f.amount)::NUMERIC, 2)       AS gmv,
    ROUND(AVG(f.amount)::NUMERIC, 2)       AS avg_txn_value
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.city_name, ci.state, ci.tier
ORDER BY gmv DESC
LIMIT 20;


-- GMV by City Tier (Tier-1 vs Tier-2 vs Tier-3)
SELECT
    ci.tier,
    COUNT(DISTINCT ci.city_id)             AS city_count,
    COUNT(f.transaction_id)                AS txn_count,
    ROUND(SUM(f.amount)::NUMERIC, 2)       AS gmv,
    ROUND(AVG(f.amount)::NUMERIC, 2)       AS avg_txn_value,
    ROUND(
        100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER ()
    ::NUMERIC, 2)                          AS tier_gmv_share_pct
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.tier
ORDER BY gmv DESC;


-- ─────────────────────────────────────────
-- CHAN-06: MERCHANT CATEGORY ANALYSIS
-- Business use: Which merchant categories drive the most GMV?
-- ─────────────────────────────────────────

SELECT
    m.category,
    COUNT(f.transaction_id)                AS txn_count,
    COUNT(DISTINCT f.customer_id)          AS unique_buyers,
    ROUND(SUM(f.amount)::NUMERIC, 2)       AS gmv,
    ROUND(AVG(f.amount)::NUMERIC, 2)       AS avg_txn_value,
    ROUND(SUM(
        (f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt
    )::NUMERIC, 2)                         AS net_revenue,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt) /
        NULLIF(SUM(f.amount), 0) * 100
    ::NUMERIC, 4)                          AS margin_pct
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_id = m.merchant_id
WHERE f.status = 'SUCCESS'
GROUP BY m.category
ORDER BY gmv DESC;


-- TOP 20 MERCHANTS BY GMV
SELECT
    m.merchant_name,
    m.category,
    ci.city_name,
    COUNT(f.transaction_id)                AS txn_count,
    ROUND(SUM(f.amount)::NUMERIC, 2)       AS gmv,
    ROUND(SUM(
        (f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt
    )::NUMERIC, 2)                         AS net_revenue
FROM fact_transactions f
JOIN dim_merchant m  ON f.merchant_id = m.merchant_id
JOIN dim_city ci     ON m.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY m.merchant_name, m.category, ci.city_name
ORDER BY gmv DESC
LIMIT 20;


-- ─────────────────────────────────────────
-- CHAN-07: ACQUIRER PERFORMANCE
-- Business use: Which acquiring bank has best success rate?
-- ─────────────────────────────────────────

SELECT
    acquirer_id,
    COUNT(*)                                                          AS total_txns,
    COUNT(*) FILTER (WHERE status = 'SUCCESS')                        AS success_txns,
    COUNT(*) FILTER (WHERE status = 'FAILED')                         AS failed_txns,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE status='SUCCESS') / COUNT(*)
    , 2)                                                              AS success_rate_pct,
    ROUND(AVG(processing_fee_amt) FILTER (WHERE status='SUCCESS')::NUMERIC, 4)
                                                                      AS avg_processing_fee,
    ROUND(SUM(amount) FILTER (WHERE status='SUCCESS')::NUMERIC, 2)   AS total_gmv_processed
FROM fact_transactions
GROUP BY acquirer_id
ORDER BY success_rate_pct DESC;
