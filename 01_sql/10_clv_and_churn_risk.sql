-- ============================================================
-- UPI Transaction Analytics Project
-- Script 10: Customer Lifetime Value (CLV) & Churn Risk
-- ============================================================

-- ============================================================
-- PART A: CUSTOMER LIFETIME VALUE (CLV)
-- ============================================================

-- -------------------------------------------------------
-- CLV 1: Historical CLV per Customer (realized revenue)
-- -------------------------------------------------------
SELECT
    customer_id,
    COUNT(*)                                                                    AS total_txns,
    ROUND(SUM(amount), 2)                                                      AS lifetime_gmv,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS lifetime_net_revenue,
    MIN(txn_date)                                                              AS first_txn_date,
    MAX(txn_date)                                                              AS last_txn_date,
    CAST(JULIANDAY(MAX(txn_date)) - JULIANDAY(MIN(txn_date)) AS INT)          AS active_days
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY customer_id
ORDER BY lifetime_net_revenue DESC;

-- -------------------------------------------------------
-- CLV 2: CLV Distribution — Percentile Buckets
-- -------------------------------------------------------
WITH clv AS (
    SELECT
        customer_id,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS net_revenue
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN net_revenue <= 0                THEN 'Negative'
        WHEN net_revenue BETWEEN 0 AND 10   THEN '₹0–10'
        WHEN net_revenue BETWEEN 10 AND 50  THEN '₹10–50'
        WHEN net_revenue BETWEEN 50 AND 100 THEN '₹50–100'
        WHEN net_revenue BETWEEN 100 AND 200 THEN '₹100–200'
        ELSE '₹200+'
    END AS clv_bucket,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct,
    ROUND(SUM(net_revenue), 2)  AS total_revenue,
    ROUND(AVG(net_revenue), 4)  AS avg_clv
FROM clv
GROUP BY clv_bucket
ORDER BY MIN(net_revenue);

-- -------------------------------------------------------
-- CLV 3: Pareto Analysis — Top 20% users, what % of revenue?
-- -------------------------------------------------------
WITH clv_ranked AS (
    SELECT
        customer_id,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS net_revenue,
        NTILE(5) OVER (ORDER BY SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) DESC) AS quintile
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    quintile,
    COUNT(*) AS users,
    ROUND(SUM(net_revenue), 2)                                              AS revenue,
    ROUND(SUM(net_revenue) * 100.0 / SUM(SUM(net_revenue)) OVER (), 2)    AS revenue_pct
FROM clv_ranked
GROUP BY quintile
ORDER BY quintile;

-- -------------------------------------------------------
-- CLV 4: Projected CLV (Simple formula)
-- Projected CLV = Avg Monthly Revenue per User × Avg Lifetime Months
-- -------------------------------------------------------
WITH user_monthly AS (
    SELECT
        customer_id,
        STRFTIME('%Y-%m', txn_date) AS month,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS monthly_rev
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id, STRFTIME('%Y-%m', txn_date)
),
user_stats AS (
    SELECT
        customer_id,
        AVG(monthly_rev)    AS avg_monthly_revenue,
        COUNT(DISTINCT month) AS active_months
    FROM user_monthly
    GROUP BY customer_id
)
SELECT
    ROUND(AVG(avg_monthly_revenue), 4) AS avg_monthly_rev_per_user,
    ROUND(AVG(active_months), 2)       AS avg_active_months,
    ROUND(AVG(avg_monthly_revenue) * AVG(active_months), 4) AS projected_clv_avg
FROM user_stats;

-- ============================================================
-- PART B: CHURN RISK FUNNEL
-- ============================================================

-- -------------------------------------------------------
-- CHURN 1: Rule-Based Churn Risk Classification
-- -------------------------------------------------------
WITH user_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)  AS last_txn_date,
        COUNT(*)       AS total_txns,
        COUNT(CASE WHEN txn_date >= DATE('2025-12-31', '-90 days') THEN 1 END) AS txns_last_90d,
        COUNT(CASE WHEN txn_date >= DATE('2025-12-31', '-30 days') THEN 1 END) AS txns_last_30d
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    customer_id,
    last_txn_date,
    total_txns,
    txns_last_90d,
    txns_last_30d,
    CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) AS days_since_last_txn,
    CASE
        WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) > 90
             AND txns_last_90d = 0  THEN 'Churned'
        WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) BETWEEN 61 AND 90
             AND txns_last_90d < 2  THEN 'High Churn Risk'
        WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) BETWEEN 31 AND 60 THEN 'Medium Churn Risk'
        WHEN txns_last_30d >= 3                                                                  THEN 'Active'
        ELSE 'Low Risk'
    END AS churn_risk_label
FROM user_activity;

-- -------------------------------------------------------
-- CHURN 2: Churn Risk Funnel Summary
-- -------------------------------------------------------
WITH user_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)  AS last_txn_date,
        COUNT(CASE WHEN txn_date >= DATE('2025-12-31', '-90 days') THEN 1 END) AS txns_last_90d
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
classified AS (
    SELECT
        customer_id,
        CASE
            WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) > 90
                 AND txns_last_90d = 0  THEN 'Churned'
            WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) BETWEEN 61 AND 90
                 AND txns_last_90d < 2  THEN 'High Churn Risk'
            WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) BETWEEN 31 AND 60 THEN 'Medium Churn Risk'
            ELSE 'Active'
        END AS churn_risk_label
    FROM user_activity
)
SELECT
    churn_risk_label,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM classified
GROUP BY churn_risk_label
ORDER BY
    CASE churn_risk_label
        WHEN 'Churned'           THEN 1
        WHEN 'High Churn Risk'   THEN 2
        WHEN 'Medium Churn Risk' THEN 3
        ELSE 4
    END;

-- -------------------------------------------------------
-- CHURN 3: GMV at Risk from High Churn Segment
-- -------------------------------------------------------
WITH user_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)  AS last_txn_date,
        COUNT(CASE WHEN txn_date >= DATE('2025-12-31', '-90 days') THEN 1 END) AS txns_last_90d,
        SUM(amount) AS total_gmv
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
classified AS (
    SELECT
        customer_id,
        total_gmv,
        CASE
            WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) > 90
                 AND txns_last_90d = 0  THEN 'Churned'
            WHEN CAST(JULIANDAY('2025-12-31') - JULIANDAY(last_txn_date) AS INT) BETWEEN 61 AND 90
                 AND txns_last_90d < 2  THEN 'High Churn Risk'
            ELSE 'Other'
        END AS churn_risk_label
    FROM user_activity
)
SELECT
    churn_risk_label,
    COUNT(*) AS users,
    ROUND(SUM(total_gmv), 2) AS historical_gmv_at_risk
FROM classified
WHERE churn_risk_label IN ('Churned', 'High Churn Risk')
GROUP BY churn_risk_label;

-- ============================================================
-- END OF SCRIPT 10
-- ============================================================
