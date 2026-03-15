-- ============================================================
-- UPI Transaction Analytics Project
-- Script 05: Channel Analysis — Mix, Margin, Efficiency
-- ============================================================

-- -------------------------------------------------------
-- CHANNEL 1: Transaction Volume & GMV by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    COUNT(*)                                          AS txn_count,
    ROUND(SUM(f.amount), 2)                          AS gmv,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS txn_share_pct,
    ROUND(SUM(f.amount) * 100.0 / SUM(SUM(f.amount)) OVER (), 2) AS gmv_share_pct,
    ROUND(AVG(f.amount), 2)                          AS avg_txn_value
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY gmv DESC;

-- -------------------------------------------------------
-- CHANNEL 2: Channel Mix over Time (Monthly)
-- -------------------------------------------------------
SELECT
    STRFTIME('%Y-%m', f.txn_date)  AS month,
    ch.channel_name,
    COUNT(*)                        AS txn_count,
    ROUND(SUM(f.amount), 2)        AS gmv
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', f.txn_date), ch.channel_name
ORDER BY month, gmv DESC;

-- -------------------------------------------------------
-- CHANNEL 3: Margin % by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    ROUND(SUM(f.amount), 2)                                                   AS gmv,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount), 2)                               AS gross_mdr,
    ROUND(SUM(f.cashback_amt), 2)                                            AS total_cashback,
    ROUND(SUM(f.processing_fee_amt), 2)                                      AS processing_cost,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
          / NULLIF(SUM(f.amount), 0) * 100, 4)                              AS margin_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY margin_pct DESC;

-- -------------------------------------------------------
-- CHANNEL 4: Channel Efficiency Ratio
-- Efficiency = Net Revenue / (Cashback + Processing Cost)
-- > 1.0 means channel is profitable relative to cost
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue,
    ROUND(SUM(f.cashback_amt + f.processing_fee_amt), 2)                   AS total_cost,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
        / NULLIF(SUM(f.cashback_amt + f.processing_fee_amt), 0),
    4) AS efficiency_ratio
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY efficiency_ratio DESC;

-- -------------------------------------------------------
-- CHANNEL 5: Processing Cost per Transaction by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    ROUND(AVG(f.processing_fee_amt), 4) AS avg_processing_fee,
    ROUND(MIN(f.processing_fee_amt), 4) AS min_processing_fee,
    ROUND(MAX(f.processing_fee_amt), 4) AS max_processing_fee,
    COUNT(*)                             AS txn_count
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY avg_processing_fee DESC;

-- -------------------------------------------------------
-- CHANNEL 6: Success Rate by Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    COUNT(*)                                                              AS total_txns,
    SUM(CASE WHEN f.status = 'SUCCESS' THEN 1 ELSE 0 END)              AS success_txns,
    ROUND(SUM(CASE WHEN f.status='SUCCESS' THEN 1.0 ELSE 0 END)
          / COUNT(*) * 100, 2)                                          AS success_rate_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
GROUP BY ch.channel_name
ORDER BY success_rate_pct DESC;

-- -------------------------------------------------------
-- CHANNEL 7: MoM Channel GMV Shift (Window function)
-- -------------------------------------------------------
WITH monthly_channel AS (
    SELECT
        STRFTIME('%Y-%m', f.txn_date) AS month,
        ch.channel_name,
        SUM(f.amount) AS gmv
    FROM fact_transactions f
    JOIN dim_channel ch ON f.channel_id = ch.channel_id
    WHERE f.status = 'SUCCESS'
    GROUP BY STRFTIME('%Y-%m', f.txn_date), ch.channel_name
)
SELECT
    month,
    channel_name,
    ROUND(gmv, 2) AS gmv,
    ROUND(gmv - LAG(gmv) OVER (PARTITION BY channel_name ORDER BY month), 2) AS mom_change,
    ROUND((gmv - LAG(gmv) OVER (PARTITION BY channel_name ORDER BY month))
          / NULLIF(LAG(gmv) OVER (PARTITION BY channel_name ORDER BY month), 0) * 100, 2) AS mom_pct
FROM monthly_channel
ORDER BY channel_name, month;

-- -------------------------------------------------------
-- CHANNEL 8: Device OS breakdown per Channel
-- -------------------------------------------------------
SELECT
    ch.channel_name,
    f.device_os,
    COUNT(*)                 AS txn_count,
    ROUND(SUM(f.amount), 2) AS gmv
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name, f.device_os
ORDER BY ch.channel_name, txn_count DESC;

-- ============================================================
-- END OF SCRIPT 05
-- ============================================================
