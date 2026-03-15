-- ============================================================
-- FILE: 04_channel_geo_analysis.sql
-- PURPOSE: Channel Mix, Geo GMV, Channel Efficiency Ratio
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- SECTION 1: CHANNEL MIX ANALYSIS
-- ────────────────────────────────────────────────────────────

-- 1a. Overall channel mix by GMV and transaction count
SELECT
    ch.channel_name,
    COUNT(*)                                                AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)    AS txn_share_pct,
    ROUND(SUM(f.amount), 2)                                AS channel_gmv,
    ROUND(100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER (), 2)   AS gmv_share_pct,
    ROUND(AVG(f.amount), 2)                                AS avg_ticket_size
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY channel_gmv DESC;

-- 1b. Monthly channel GMV trend
SELECT
    strftime('%Y-%m', f.txn_date)   AS month,
    ch.channel_name,
    COUNT(*)                         AS txn_count,
    ROUND(SUM(f.amount), 2)          AS gmv
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY strftime('%Y-%m', f.txn_date), ch.channel_name
ORDER BY month, ch.channel_name;

-- 1c. Channel success rate comparison
SELECT
    ch.channel_name,
    COUNT(*)                                                            AS total_txns,
    SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END)             AS successful,
    ROUND(100.0 * SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                               AS success_rate_pct,
    ROUND(AVG(CASE WHEN f.status = 'SUCCESS' THEN f.retry_count END), 2) AS avg_retries_on_success
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
GROUP BY ch.channel_name
ORDER BY success_rate_pct DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 2: CHANNEL EFFICIENCY RATIO
-- Definition: Net Revenue Generated / Total Cost of Channel
-- Higher ratio = more profitable channel
-- ────────────────────────────────────────────────────────────

SELECT
    ch.channel_name,
    ROUND(SUM(f.amount), 2)                                           AS gmv,
    ROUND(SUM((f.mdr_pct / 100.0) * f.amount), 2)                    AS gross_mdr_income,
    ROUND(SUM(f.cashback_amt), 2)                                     AS cashback_cost,
    ROUND(SUM(f.processing_fee_amt), 2)                               AS processing_cost,
    ROUND(SUM((f.mdr_pct / 100.0) * f.amount
              - f.cashback_amt - f.processing_fee_amt), 2)            AS net_revenue,
    ROUND(
        SUM((f.mdr_pct / 100.0) * f.amount - f.cashback_amt - f.processing_fee_amt)
        / NULLIF(SUM(f.cashback_amt + f.processing_fee_amt), 0)
    , 4)                                                              AS efficiency_ratio,
    ROUND(
        SUM((f.mdr_pct / 100.0) * f.amount - f.cashback_amt - f.processing_fee_amt)
        / NULLIF(SUM(f.amount), 0) * 100
    , 4)                                                              AS margin_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY efficiency_ratio DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 3: MARGIN % BY CHANNEL
-- ────────────────────────────────────────────────────────────

SELECT
    ch.channel_name,
    ROUND(AVG(f.mdr_pct), 4)          AS avg_mdr_pct,
    ROUND(AVG(f.cashback_amt), 4)      AS avg_cashback_per_txn,
    ROUND(AVG(f.processing_fee_amt),4) AS avg_processing_per_txn,
    ROUND(
        SUM((f.mdr_pct / 100.0) * f.amount - f.cashback_amt - f.processing_fee_amt)
        / NULLIF(SUM(f.amount), 0) * 100
    , 4)                               AS net_margin_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY net_margin_pct DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 4: GEO-WISE GMV ANALYSIS
-- ────────────────────────────────────────────────────────────

-- 4a. GMV by State
SELECT
    ci.state,
    COUNT(*)                                                           AS txn_count,
    COUNT(DISTINCT f.customer_id)                                      AS unique_customers,
    ROUND(SUM(f.amount), 2)                                            AS gmv,
    ROUND(100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER (), 2)     AS gmv_share_pct,
    ROUND(SUM((f.mdr_pct / 100.0) * f.amount
              - f.cashback_amt - f.processing_fee_amt), 2)            AS net_revenue
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.state
ORDER BY gmv DESC;

-- 4b. GMV by City Tier (Tier-1 / Tier-2 / Tier-3)
SELECT
    ci.tier,
    COUNT(*)                                                           AS txn_count,
    COUNT(DISTINCT f.customer_id)                                      AS unique_customers,
    ROUND(SUM(f.amount), 2)                                            AS gmv,
    ROUND(100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER (), 2)     AS gmv_share_pct,
    ROUND(AVG(f.amount), 2)                                            AS avg_ticket_size,
    ROUND(
        SUM((f.mdr_pct / 100.0) * f.amount - f.cashback_amt - f.processing_fee_amt)
        / NULLIF(SUM(f.amount), 0) * 100
    , 4)                                                              AS margin_pct
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.tier
ORDER BY gmv DESC;

-- 4c. Top 15 cities by GMV
SELECT
    ci.city_name,
    ci.state,
    ci.tier,
    COUNT(*)                                                           AS txn_count,
    ROUND(SUM(f.amount), 2)                                            AS gmv,
    COUNT(DISTINCT f.customer_id)                                      AS unique_customers
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.city_name, ci.state, ci.tier
ORDER BY gmv DESC
LIMIT 15;

-- 4d. Channel preference by city tier
SELECT
    ci.tier,
    ch.channel_name,
    COUNT(*)                                                           AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY ci.tier), 2) AS pct_within_tier
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.tier, ch.channel_name
ORDER BY ci.tier, txn_count DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 5: MERCHANT ANALYSIS
-- ────────────────────────────────────────────────────────────

-- 5a. Top 20 merchants by GMV
SELECT
    m.merchant_name,
    m.category,
    COUNT(*)                            AS txn_count,
    ROUND(SUM(f.amount), 2)             AS gmv,
    COUNT(DISTINCT f.customer_id)       AS unique_customers,
    ROUND(AVG(f.amount), 2)             AS avg_ticket_size
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_id = m.merchant_id
WHERE f.status = 'SUCCESS'
GROUP BY m.merchant_name, m.category
ORDER BY gmv DESC
LIMIT 20;

-- 5b. GMV by merchant category
SELECT
    m.category,
    COUNT(*)                                                           AS txn_count,
    COUNT(DISTINCT f.customer_id)                                      AS unique_customers,
    ROUND(SUM(f.amount), 2)                                            AS gmv,
    ROUND(100.0 * SUM(f.amount) / SUM(SUM(f.amount)) OVER (), 2)     AS gmv_share_pct,
    ROUND(AVG(f.amount), 2)                                            AS avg_ticket_size
FROM fact_transactions f
JOIN dim_merchant m ON f.merchant_id = m.merchant_id
WHERE f.status = 'SUCCESS'
GROUP BY m.category
ORDER BY gmv DESC;

-- 5c. Device OS preference per channel
SELECT
    ch.channel_name,
    f.device_os,
    COUNT(*)                                                           AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY ch.channel_name), 2) AS pct_of_channel
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name, f.device_os
ORDER BY ch.channel_name, txn_count DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 6: WEEKEND vs WEEKDAY PERFORMANCE
-- ────────────────────────────────────────────────────────────

SELECT
    d.is_weekend,
    COUNT(f.transaction_id)             AS txn_count,
    COUNT(DISTINCT f.customer_id)       AS unique_customers,
    ROUND(SUM(f.amount), 2)             AS gmv,
    ROUND(AVG(f.amount), 2)             AS avg_ticket_size,
    ROUND(
        SUM((f.mdr_pct / 100.0) * f.amount - f.cashback_amt - f.processing_fee_amt)
        / NULLIF(SUM(f.amount), 0) * 100
    , 4)                                AS margin_pct
FROM fact_transactions f
JOIN dim_date d ON f.txn_date = d.date
WHERE f.status = 'SUCCESS'
GROUP BY d.is_weekend;

-- Holiday vs Non-Holiday transactions
SELECT
    d.holiday_flag,
    COUNT(f.transaction_id)             AS txn_count,
    ROUND(SUM(f.amount), 2)             AS gmv,
    ROUND(AVG(f.amount), 2)             AS avg_ticket_size
FROM fact_transactions f
JOIN dim_date d ON f.txn_date = d.date
WHERE f.status = 'SUCCESS'
GROUP BY d.holiday_flag;
