-- ============================================================
-- FILE: 06_rfm_clv_segmentation.sql
-- PURPOSE: RFM Segmentation + Customer Lifetime Value (CLV)
-- No ML. Pure SQL percentile-based scoring.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- SECTION 1: BASE RFM METRICS
-- R = Recency (days since last transaction — lower is better)
-- F = Frequency (number of transactions — higher is better)
-- M = Monetary (total amount spent — higher is better)
-- ────────────────────────────────────────────────────────────

-- Note: We use '2026-03-05' as "today" since data is historical
-- Replace with date('now') if running live

CREATE TEMP TABLE IF NOT EXISTS rfm_base AS
SELECT
    customer_id,
    CAST(JULIANDAY('2026-03-05') - JULIANDAY(MAX(txn_date)) AS INTEGER) AS recency_days,
    COUNT(*)                                                              AS frequency,
    ROUND(SUM(amount), 2)                                                AS monetary,
    ROUND(AVG(amount), 2)                                                AS avg_order_value,
    MIN(txn_date)                                                        AS first_txn_date,
    MAX(txn_date)                                                        AS last_txn_date,
    COUNT(DISTINCT strftime('%Y-%m', txn_date))                          AS active_months
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY customer_id;

-- Preview RFM base
SELECT * FROM rfm_base ORDER BY monetary DESC LIMIT 20;

-- ────────────────────────────────────────────────────────────
-- SECTION 2: RFM SCORING (1-4 scale using NTILE)
-- R Score: 4 = most recent, 1 = least recent (REVERSED)
-- F Score: 4 = highest frequency
-- M Score: 4 = highest spend
-- ────────────────────────────────────────────────────────────

CREATE TEMP TABLE IF NOT EXISTS rfm_scored AS
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    active_months,
    -- R score: lower recency = better = higher score
    CASE
        WHEN recency_days <= (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1 OFFSET CAST(COUNT(*)*0.25 AS INT) FROM rfm_base) THEN 4
        WHEN recency_days <= (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1 OFFSET CAST(COUNT(*)*0.50 AS INT) FROM rfm_base) THEN 3
        WHEN recency_days <= (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1 OFFSET CAST(COUNT(*)*0.75 AS INT) FROM rfm_base) THEN 2
        ELSE 1
    END AS r_score,
    -- F score: higher frequency = better
    NTILE(4) OVER (ORDER BY frequency ASC)  AS f_score,
    -- M score: higher spend = better
    NTILE(4) OVER (ORDER BY monetary ASC)   AS m_score
FROM rfm_base;

-- ────────────────────────────────────────────────────────────
-- SECTION 3: SIMPLIFIED RFM USING PERCENTILE THRESHOLDS
-- More reliable in SQLite (no window function limitations)
-- ────────────────────────────────────────────────────────────

WITH percentiles AS (
    SELECT
        -- Recency thresholds (lower recency is better)
        (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm_base)) AS r_p25,
        (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm_base)) AS r_p50,
        (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm_base)) AS r_p75,
        -- Frequency thresholds
        (SELECT frequency FROM rfm_base ORDER BY frequency LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm_base)) AS f_p25,
        (SELECT frequency FROM rfm_base ORDER BY frequency LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm_base)) AS f_p50,
        (SELECT frequency FROM rfm_base ORDER BY frequency LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm_base)) AS f_p75,
        -- Monetary thresholds
        (SELECT monetary FROM rfm_base ORDER BY monetary LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm_base)) AS m_p25,
        (SELECT monetary FROM rfm_base ORDER BY monetary LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm_base)) AS m_p50,
        (SELECT monetary FROM rfm_base ORDER BY monetary LIMIT 1
            OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm_base)) AS m_p75
),
rfm_with_scores AS (
    SELECT
        r.customer_id,
        r.recency_days,
        r.frequency,
        r.monetary,
        r.avg_order_value,
        r.active_months,
        -- R score (inverted: recent = high score)
        CASE
            WHEN r.recency_days <= p.r_p25  THEN 4
            WHEN r.recency_days <= p.r_p50  THEN 3
            WHEN r.recency_days <= p.r_p75  THEN 2
            ELSE                                 1
        END AS r_score,
        -- F score
        CASE
            WHEN r.frequency >= p.f_p75  THEN 4
            WHEN r.frequency >= p.f_p50  THEN 3
            WHEN r.frequency >= p.f_p25  THEN 2
            ELSE                              1
        END AS f_score,
        -- M score
        CASE
            WHEN r.monetary >= p.m_p75   THEN 4
            WHEN r.monetary >= p.m_p50   THEN 3
            WHEN r.monetary >= p.m_p25   THEN 2
            ELSE                              1
        END AS m_score
    FROM rfm_base r, percentiles p
)
SELECT
    customer_id,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    active_months,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) AS rfm_total_score,
    -- Segment label based on RFM combination
    CASE
        WHEN r_score = 4 AND f_score = 4 AND m_score = 4  THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                 THEN 'Loyal Customers'
        WHEN r_score = 4 AND f_score <= 2                  THEN 'New Customers'
        WHEN r_score >= 3 AND f_score <= 2 AND m_score >= 3 THEN 'Potential Loyalists'
        WHEN r_score = 2 AND f_score >= 3                  THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 3 THEN 'Cant Lose Them'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score <= 2 THEN 'Lost Customers'
        WHEN r_score = 1                                    THEN 'Hibernating'
        ELSE                                                     'Needs Attention'
    END AS rfm_segment
FROM rfm_with_scores
ORDER BY rfm_total_score DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 4: RFM SEGMENT SUMMARY
-- ────────────────────────────────────────────────────────────

WITH percentiles AS (
    SELECT
        (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm_base)) AS r_p25,
        (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm_base)) AS r_p50,
        (SELECT recency_days FROM rfm_base ORDER BY recency_days LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm_base)) AS r_p75,
        (SELECT frequency FROM rfm_base ORDER BY frequency LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm_base)) AS f_p25,
        (SELECT frequency FROM rfm_base ORDER BY frequency LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm_base)) AS f_p50,
        (SELECT frequency FROM rfm_base ORDER BY frequency LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm_base)) AS f_p75,
        (SELECT monetary FROM rfm_base ORDER BY monetary LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm_base)) AS m_p25,
        (SELECT monetary FROM rfm_base ORDER BY monetary LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm_base)) AS m_p50,
        (SELECT monetary FROM rfm_base ORDER BY monetary LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm_base)) AS m_p75
),
scored AS (
    SELECT
        r.customer_id, r.monetary,
        CASE WHEN r.recency_days<=p.r_p25 THEN 4 WHEN r.recency_days<=p.r_p50 THEN 3 WHEN r.recency_days<=p.r_p75 THEN 2 ELSE 1 END AS r_score,
        CASE WHEN r.frequency>=p.f_p75 THEN 4 WHEN r.frequency>=p.f_p50 THEN 3 WHEN r.frequency>=p.f_p25 THEN 2 ELSE 1 END AS f_score,
        CASE WHEN r.monetary>=p.m_p75 THEN 4 WHEN r.monetary>=p.m_p50 THEN 3 WHEN r.monetary>=p.m_p25 THEN 2 ELSE 1 END AS m_score
    FROM rfm_base r, percentiles p
),
segmented AS (
    SELECT customer_id, monetary,
        CASE
            WHEN r_score=4 AND f_score=4 AND m_score=4  THEN 'Champions'
            WHEN r_score>=3 AND f_score>=3               THEN 'Loyal Customers'
            WHEN r_score=4 AND f_score<=2                THEN 'New Customers'
            WHEN r_score>=3 AND f_score<=2 AND m_score>=3 THEN 'Potential Loyalists'
            WHEN r_score=2 AND f_score>=3                THEN 'At Risk'
            WHEN r_score<=2 AND f_score<=2 AND m_score>=3 THEN 'Cant Lose Them'
            WHEN r_score<=2 AND f_score<=2 AND m_score<=2 THEN 'Lost Customers'
            WHEN r_score=1                               THEN 'Hibernating'
            ELSE                                              'Needs Attention'
        END AS rfm_segment
    FROM scored
)
SELECT
    rfm_segment,
    COUNT(*)                                                        AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)             AS pct_customers,
    ROUND(SUM(monetary), 2)                                         AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2)   AS pct_revenue,
    ROUND(AVG(monetary), 2)                                         AS avg_revenue_per_customer
FROM segmented
GROUP BY rfm_segment
ORDER BY total_revenue DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 5: CUSTOMER LIFETIME VALUE (CLV)
-- Simple CLV = Total net revenue generated per customer
-- Advanced CLV = Avg monthly revenue * expected tenure months
-- ────────────────────────────────────────────────────────────

-- 5a. Historical CLV per customer
SELECT
    customer_id,
    COUNT(*)                                                AS txn_count,
    ROUND(SUM(amount), 2)                                   AS total_gmv_generated,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS clv_net_revenue,
    ROUND(AVG(amount), 2)                                   AS avg_order_value,
    MIN(txn_date)                                           AS customer_since,
    MAX(txn_date)                                           AS last_active,
    CAST(JULIANDAY(MAX(txn_date)) - JULIANDAY(MIN(txn_date)) AS INT) AS tenure_days
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY customer_id
ORDER BY clv_net_revenue DESC;

-- 5b. CLV Distribution (percentile buckets)
WITH clv AS (
    SELECT
        customer_id,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS lifetime_value
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN lifetime_value < 0      THEN 'Negative CLV'
        WHEN lifetime_value < 10     THEN '0 - 10'
        WHEN lifetime_value < 50     THEN '10 - 50'
        WHEN lifetime_value < 100    THEN '50 - 100'
        WHEN lifetime_value < 500    THEN '100 - 500'
        ELSE                              '500+'
    END AS clv_bucket,
    COUNT(*)                                                    AS customer_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)         AS pct_customers,
    ROUND(SUM(lifetime_value), 2)                               AS total_clv,
    ROUND(AVG(lifetime_value), 2)                               AS avg_clv
FROM clv
GROUP BY clv_bucket
ORDER BY avg_clv;

-- 5c. Top 10% customers contribution (Pareto analysis)
WITH clv AS (
    SELECT
        customer_id,
        SUM(amount) AS total_spend,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS net_clv
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY net_clv DESC)    AS rank_num,
           COUNT(*) OVER ()                              AS total_customers,
           SUM(net_clv) OVER ()                          AS total_revenue
    FROM clv
)
SELECT
    CASE
        WHEN rank_num <= total_customers * 0.10  THEN 'Top 10%'
        WHEN rank_num <= total_customers * 0.25  THEN 'Top 11-25%'
        WHEN rank_num <= total_customers * 0.50  THEN 'Top 26-50%'
        ELSE                                          'Bottom 50%'
    END                                                         AS customer_tier,
    COUNT(*)                                                    AS customer_count,
    ROUND(SUM(net_clv), 2)                                      AS segment_revenue,
    ROUND(100.0 * SUM(net_clv) / MAX(total_revenue), 2)        AS pct_of_total_revenue,
    ROUND(AVG(net_clv), 2)                                      AS avg_clv
FROM ranked
GROUP BY
    CASE
        WHEN rank_num <= total_customers * 0.10  THEN 'Top 10%'
        WHEN rank_num <= total_customers * 0.25  THEN 'Top 11-25%'
        WHEN rank_num <= total_customers * 0.50  THEN 'Top 26-50%'
        ELSE                                          'Bottom 50%'
    END
ORDER BY avg_clv DESC;
