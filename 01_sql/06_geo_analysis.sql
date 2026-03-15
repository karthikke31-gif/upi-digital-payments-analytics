-- ============================================================
-- UPI Transaction Analytics Project
-- Script 06: Geo Analysis — City, State, Tier GMV
-- ============================================================

-- -------------------------------------------------------
-- GEO 1: State-wise GMV Ranking
-- -------------------------------------------------------
SELECT
    ci.state,
    COUNT(*)                                                                   AS txn_count,
    ROUND(SUM(f.amount), 2)                                                   AS gmv,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue,
    COUNT(DISTINCT f.customer_id)                                             AS unique_customers,
    ROUND(SUM(f.amount) * 100.0 / SUM(SUM(f.amount)) OVER (), 2)            AS gmv_share_pct,
    RANK() OVER (ORDER BY SUM(f.amount) DESC)                                 AS gmv_rank
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.state
ORDER BY gmv DESC;

-- -------------------------------------------------------
-- GEO 2: City-wise GMV — Top 20 Cities
-- -------------------------------------------------------
SELECT
    ci.city_name,
    ci.state,
    ci.tier,
    COUNT(*)                         AS txn_count,
    ROUND(SUM(f.amount), 2)         AS gmv,
    COUNT(DISTINCT f.customer_id)   AS unique_customers,
    ROUND(AVG(f.amount), 2)         AS avg_txn_value
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.city_name, ci.state, ci.tier
ORDER BY gmv DESC
LIMIT 20;

-- -------------------------------------------------------
-- GEO 3: Tier-wise GMV Analysis (Tier-1 / Tier-2 / Tier-3)
-- -------------------------------------------------------
SELECT
    ci.tier,
    COUNT(*)                                                                   AS txn_count,
    ROUND(SUM(f.amount), 2)                                                   AS gmv,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue,
    COUNT(DISTINCT f.customer_id)                                             AS unique_customers,
    ROUND(AVG(f.amount), 2)                                                   AS avg_txn_value,
    ROUND(SUM(f.amount) * 100.0 / SUM(SUM(f.amount)) OVER (), 2)            AS gmv_share_pct,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
          / NULLIF(SUM(f.amount), 0) * 100, 4)                              AS margin_pct
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.tier
ORDER BY gmv DESC;

-- -------------------------------------------------------
-- GEO 4: Merchant Category by City Tier
-- -------------------------------------------------------
SELECT
    ci.tier,
    m.category,
    COUNT(*)                       AS txn_count,
    ROUND(SUM(f.amount), 2)       AS gmv,
    ROUND(AVG(f.amount), 2)       AS avg_txn_value
FROM fact_transactions f
JOIN dim_city ci   ON f.city_id    = ci.city_id
JOIN dim_merchant m ON f.merchant_id = m.merchant_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.tier, m.category
ORDER BY ci.tier, gmv DESC;

-- -------------------------------------------------------
-- GEO 5: Channel Preference by Tier
-- -------------------------------------------------------
SELECT
    ci.tier,
    ch.channel_name,
    COUNT(*)                                                      AS txn_count,
    ROUND(SUM(f.amount), 2)                                      AS gmv,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (PARTITION BY ci.tier), 2) AS channel_pct_within_tier
FROM fact_transactions f
JOIN dim_city    ci ON f.city_id    = ci.city_id
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.tier, ch.channel_name
ORDER BY ci.tier, txn_count DESC;

-- -------------------------------------------------------
-- GEO 6: State MoM Growth
-- -------------------------------------------------------
WITH state_monthly AS (
    SELECT
        ci.state,
        STRFTIME('%Y-%m', f.txn_date) AS month,
        SUM(f.amount)                  AS gmv
    FROM fact_transactions f
    JOIN dim_city ci ON f.city_id = ci.city_id
    WHERE f.status = 'SUCCESS'
    GROUP BY ci.state, STRFTIME('%Y-%m', f.txn_date)
)
SELECT
    state,
    month,
    ROUND(gmv, 2) AS gmv,
    ROUND((gmv - LAG(gmv) OVER (PARTITION BY state ORDER BY month))
          / NULLIF(LAG(gmv) OVER (PARTITION BY state ORDER BY month), 0) * 100, 2) AS mom_pct
FROM state_monthly
ORDER BY state, month;

-- -------------------------------------------------------
-- GEO 7: Cities with High GMV but Low Margin (Opportunity)
-- -------------------------------------------------------
SELECT
    ci.city_name,
    ci.state,
    ci.tier,
    ROUND(SUM(f.amount), 2)                                                       AS gmv,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
          / NULLIF(SUM(f.amount), 0) * 100, 4)                                   AS margin_pct
FROM fact_transactions f
JOIN dim_city ci ON f.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY ci.city_name, ci.state, ci.tier
HAVING SUM(f.amount) > 50000           -- GMV threshold
ORDER BY margin_pct ASC                -- lowest margin first (opportunity cities)
LIMIT 15;

-- ============================================================
-- END OF SCRIPT 06
-- ============================================================
