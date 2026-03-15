-- ============================================================
-- UPI Transaction Analytics Project
-- Script 09: RFM Segmentation
-- R = Recency (days since last transaction)
-- F = Frequency (number of transactions)
-- M = Monetary (total spend)
-- ============================================================

-- -------------------------------------------------------
-- RFM 1: Raw RFM Metrics per Customer
-- -------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS rfm_raw AS
SELECT
    customer_id,
    MAX(txn_date)                                       AS last_txn_date,
    CAST(JULIANDAY('2025-12-31') - JULIANDAY(MAX(txn_date)) AS INT) AS recency_days,
    COUNT(*)                                            AS frequency,
    ROUND(SUM(amount), 2)                              AS monetary,
    ROUND(AVG(amount), 2)                              AS avg_order_value
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY customer_id;

-- -------------------------------------------------------
-- RFM 2: Score each dimension into 1-4 using NTILE
-- Higher score = better (lower recency days = score 4)
-- -------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS rfm_scored AS
SELECT
    customer_id,
    last_txn_date,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    -- R: reverse NTILE so recent = score 4
    5 - NTILE(4) OVER (ORDER BY recency_days ASC)      AS r_score,
    NTILE(4) OVER (ORDER BY frequency ASC)             AS f_score,
    NTILE(4) OVER (ORDER BY monetary ASC)              AS m_score
FROM rfm_raw;

-- -------------------------------------------------------
-- RFM 3: Combine into RFM Score and Segment Label
-- -------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS rfm_segments AS
SELECT
    customer_id,
    last_txn_date,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CAST(r_score AS TEXT) || CAST(f_score AS TEXT) || CAST(m_score AS TEXT) AS rfm_score,
    CASE
        WHEN r_score = 4 AND f_score = 4 AND m_score = 4  THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                 THEN 'Loyal Customers'
        WHEN r_score = 4 AND f_score <= 2                  THEN 'Recent Customers'
        WHEN r_score >= 3 AND f_score = 4                  THEN 'Promising'
        WHEN r_score >= 2 AND f_score >= 2 AND m_score >= 2 THEN 'Customers Needing Attention'
        WHEN r_score = 2 AND f_score <= 2                  THEN 'At Risk'
        WHEN r_score = 1 AND f_score >= 2                  THEN 'Cannot Lose Them'
        WHEN r_score = 1 AND f_score = 1                   THEN 'Lost Customers'
        ELSE 'Hibernating'
    END AS segment
FROM rfm_scored;

-- -------------------------------------------------------
-- RFM 4: Segment Summary — Count and GMV per Segment
-- -------------------------------------------------------
SELECT
    segment,
    COUNT(*)                             AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
    ROUND(SUM(monetary), 2)             AS total_gmv,
    ROUND(AVG(monetary), 2)             AS avg_gmv,
    ROUND(SUM(monetary) * 100.0 / SUM(SUM(monetary)) OVER (), 2) AS pct_gmv,
    ROUND(AVG(recency_days), 1)         AS avg_recency_days,
    ROUND(AVG(frequency), 1)            AS avg_frequency,
    ROUND(AVG(avg_order_value), 2)      AS avg_order_value
FROM rfm_segments
GROUP BY segment
ORDER BY total_gmv DESC;

-- -------------------------------------------------------
-- RFM 5: Score Distribution
-- -------------------------------------------------------
SELECT
    r_score, f_score, m_score,
    COUNT(*)                 AS customer_count,
    ROUND(AVG(monetary), 2) AS avg_monetary
FROM rfm_segments
GROUP BY r_score, f_score, m_score
ORDER BY r_score DESC, f_score DESC, m_score DESC;

-- -------------------------------------------------------
-- RFM 6: Top 50 Champions (for Key Account Management)
-- -------------------------------------------------------
SELECT
    customer_id,
    segment,
    recency_days,
    frequency,
    ROUND(monetary, 2) AS monetary,
    ROUND(avg_order_value, 2) AS aov
FROM rfm_segments
WHERE segment = 'Champions'
ORDER BY monetary DESC
LIMIT 50;

-- -------------------------------------------------------
-- RFM 7: "Cannot Lose" & "At Risk" Customers — Priority Alert
-- -------------------------------------------------------
SELECT
    rs.customer_id,
    rs.segment,
    rs.recency_days,
    rs.frequency,
    ROUND(rs.monetary, 2)   AS lifetime_spend,
    dc.city_id
FROM rfm_segments rs
JOIN dim_customer dc ON rs.customer_id = dc.customer_id
WHERE rs.segment IN ('Cannot Lose Them', 'At Risk')
ORDER BY rs.monetary DESC
LIMIT 100;

-- -------------------------------------------------------
-- RFM 8: Segment Transition — Monthly snapshot comparison
-- (Run once per month and store; compare to previous month)
-- -------------------------------------------------------
SELECT
    segment,
    COUNT(*) AS user_count
FROM rfm_segments
GROUP BY segment
ORDER BY user_count DESC;

-- ============================================================
-- END OF SCRIPT 09
-- ============================================================
