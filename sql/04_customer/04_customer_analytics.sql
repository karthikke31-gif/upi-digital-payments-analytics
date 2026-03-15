-- ============================================================
-- UPI TRANSACTION ANALYTICS PROJECT
-- FILE: 04_customer_analytics.sql
-- PURPOSE: Cohort Retention, RFM Segmentation, CLV, Churn Risk
-- ============================================================


-- ─────────────────────────────────────────
-- CUST-01: COHORT RETENTION (Month 1, 3, 6, 12)
-- Logic: Group customers by their first transaction month,
--        then count how many come back in subsequent months
-- ─────────────────────────────────────────

WITH first_txn AS (
    -- Find the first transaction month per customer (cohort assignment)
    SELECT
        customer_id,
        DATE_TRUNC('month', MIN(txn_date)) AS cohort_month
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
cohort_size AS (
    -- Total customers per cohort
    SELECT cohort_month, COUNT(customer_id) AS total_in_cohort
    FROM first_txn
    GROUP BY cohort_month
),
activity AS (
    -- All months a customer was active
    SELECT
        customer_id,
        DATE_TRUNC('month', txn_date) AS activity_month
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
),
cohort_activity AS (
    -- Join cohort with activity, compute months since cohort start
    SELECT
        f.cohort_month,
        EXTRACT(YEAR FROM AGE(a.activity_month, f.cohort_month)) * 12 +
        EXTRACT(MONTH FROM AGE(a.activity_month, f.cohort_month)) AS months_since_start,
        COUNT(DISTINCT a.customer_id)                             AS active_users
    FROM first_txn f
    JOIN activity a ON f.customer_id = a.customer_id
    WHERE a.activity_month >= f.cohort_month
    GROUP BY f.cohort_month, months_since_start
)
SELECT
    TO_CHAR(ca.cohort_month, 'YYYY-MM')                          AS cohort_month,
    cs.total_in_cohort,
    ca.months_since_start,
    ca.active_users,
    ROUND(100.0 * ca.active_users / cs.total_in_cohort, 2)       AS retention_pct
FROM cohort_activity ca
JOIN cohort_size cs ON ca.cohort_month = cs.cohort_month
WHERE ca.months_since_start IN (0, 1, 2, 3, 6, 11)  -- Month 0=baseline, 1,3,6,12
ORDER BY cohort_month, months_since_start;


-- ─────────────────────────────────────────
-- CUST-02: RETENTION SUMMARY — Average across all cohorts
-- Business insight: What % of users are still using after 1/3/6 months?
-- ─────────────────────────────────────────

WITH first_txn AS (
    SELECT customer_id, DATE_TRUNC('month', MIN(txn_date)) AS cohort_month
    FROM fact_transactions WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS total_in_cohort FROM first_txn GROUP BY cohort_month
),
activity AS (
    SELECT customer_id, DATE_TRUNC('month', txn_date) AS activity_month
    FROM fact_transactions WHERE status = 'SUCCESS'
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
),
retention AS (
    SELECT
        f.cohort_month,
        EXTRACT(YEAR FROM AGE(a.activity_month, f.cohort_month)) * 12 +
        EXTRACT(MONTH FROM AGE(a.activity_month, f.cohort_month)) AS months_since_start,
        COUNT(DISTINCT a.customer_id)           AS active_users,
        cs.total_in_cohort
    FROM first_txn f
    JOIN activity a ON f.customer_id = a.customer_id
    JOIN cohort_size cs ON f.cohort_month = cs.cohort_month
    WHERE a.activity_month >= f.cohort_month
    GROUP BY f.cohort_month, months_since_start, cs.total_in_cohort
)
SELECT
    months_since_start,
    ROUND(AVG(100.0 * active_users / total_in_cohort), 2) AS avg_retention_pct,
    SUM(active_users)                                      AS total_retained_users
FROM retention
WHERE months_since_start IN (1, 3, 6, 11)
GROUP BY months_since_start
ORDER BY months_since_start;


-- ─────────────────────────────────────────
-- CUST-03: RFM SEGMENTATION
-- R = Recency (days since last transaction — lower is better)
-- F = Frequency (number of transactions)
-- M = Monetary (total spend)
-- ─────────────────────────────────────────

WITH rfm_base AS (
    SELECT
        customer_id,
        MAX(txn_date)                                   AS last_txn_date,
        (SELECT MAX(txn_date) FROM fact_transactions WHERE status='SUCCESS')
            - MAX(txn_date)                             AS recency_days,
        COUNT(*)                                        AS frequency,
        ROUND(SUM(amount)::NUMERIC, 2)                  AS monetary
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT
        customer_id,
        last_txn_date,
        recency_days,
        frequency,
        monetary,
        -- Score each dimension (5=best, 1=worst) using NTILE
        -- Recency: lower days = higher score
        NTILE(5) OVER (ORDER BY recency_days DESC)   AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)       AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)        AS m_score
    FROM rfm_base
),
rfm_labelled AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        r_score, f_score, m_score,
        (r_score + f_score + m_score)                AS rfm_total_score,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 3 AND f_score >= 3                   THEN 'Loyal Users'
            WHEN r_score >= 4 AND f_score <= 2                   THEN 'New Customers'
            WHEN r_score >= 3 AND f_score <= 2                   THEN 'Potential Loyalists'
            WHEN r_score <= 2 AND f_score >= 3                   THEN 'At Risk'
            WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 3  THEN 'Cannot Lose Them'
            WHEN r_score = 1 AND f_score = 1                     THEN 'Lost Customers'
            ELSE 'Hibernating'
        END                                          AS rfm_segment
    FROM rfm_scores
)
SELECT
    rfm_segment,
    COUNT(customer_id)               AS customer_count,
    ROUND(AVG(recency_days))         AS avg_recency_days,
    ROUND(AVG(frequency))            AS avg_frequency,
    ROUND(AVG(monetary)::NUMERIC, 2) AS avg_monetary,
    ROUND(SUM(monetary)::NUMERIC, 2) AS total_monetary
FROM rfm_labelled
GROUP BY rfm_segment
ORDER BY total_monetary DESC;


-- DETAILED RFM TABLE (for export to Python or Power BI)
WITH rfm_base AS (
    SELECT
        customer_id,
        MAX(txn_date)                                   AS last_txn_date,
        (SELECT MAX(txn_date) FROM fact_transactions WHERE status='SUCCESS')
            - MAX(txn_date)                             AS recency_days,
        COUNT(*)                                        AS frequency,
        ROUND(SUM(amount)::NUMERIC, 2)                  AS monetary
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT *,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,
        NTILE(5) OVER (ORDER BY frequency ASC)     AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)      AS m_score
    FROM rfm_base
)
SELECT
    customer_id, last_txn_date, recency_days, frequency, monetary,
    r_score, f_score, m_score,
    (r_score + f_score + m_score) AS rfm_total,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3                   THEN 'Loyal Users'
        WHEN r_score >= 4 AND f_score <= 2                   THEN 'New Customers'
        WHEN r_score >= 3 AND f_score <= 2                   THEN 'Potential Loyalists'
        WHEN r_score <= 2 AND f_score >= 3                   THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 AND m_score >= 3  THEN 'Cannot Lose Them'
        WHEN r_score = 1 AND f_score = 1                     THEN 'Lost Customers'
        ELSE 'Hibernating'
    END AS rfm_segment
FROM rfm_scores
ORDER BY rfm_total DESC;


-- ─────────────────────────────────────────
-- CUST-04: CUSTOMER LIFETIME VALUE (CLV)
-- Formula: Total net revenue generated per customer
-- ─────────────────────────────────────────

WITH customer_revenue AS (
    SELECT
        customer_id,
        COUNT(*)                                                              AS total_txns,
        ROUND(SUM(amount)::NUMERIC, 2)                                        AS total_gmv,
        ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)::NUMERIC, 2)
                                                                              AS lifetime_value,
        MIN(txn_date)                                                         AS first_txn,
        MAX(txn_date)                                                         AS last_txn,
        MAX(txn_date) - MIN(txn_date)                                         AS active_days
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    cr.*,
    c.segment_tag,
    -- CLV percentile bucket
    CASE
        WHEN lifetime_value >= PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY lifetime_value) OVER () THEN 'Top 10%'
        WHEN lifetime_value >= PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lifetime_value) OVER () THEN 'Top 25%'
        WHEN lifetime_value >= PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY lifetime_value) OVER () THEN 'Top 50%'
        ELSE 'Bottom 50%'
    END AS clv_bucket
FROM customer_revenue cr
JOIN dim_customer c ON cr.customer_id = c.customer_id
ORDER BY lifetime_value DESC;


-- CLV DISTRIBUTION SUMMARY
WITH customer_ltv AS (
    SELECT
        customer_id,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS ltv
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ltv)::NUMERIC, 2) AS p25_ltv,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ltv)::NUMERIC, 2) AS median_ltv,
    ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ltv)::NUMERIC, 2) AS p75_ltv,
    ROUND(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY ltv)::NUMERIC, 2) AS p90_ltv,
    ROUND(AVG(ltv)::NUMERIC, 2)                                          AS avg_ltv,
    ROUND(SUM(ltv)::NUMERIC, 2)                                          AS total_net_revenue
FROM customer_ltv;


-- ─────────────────────────────────────────
-- CUST-05: CHURN RISK FUNNEL
-- Rules-based segmentation (no ML required)
-- ─────────────────────────────────────────

WITH customer_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)                                                         AS last_txn_date,
        COUNT(*) FILTER (WHERE txn_date >= (SELECT MAX(txn_date) FROM fact_transactions)
                                            - INTERVAL '90 days')             AS txn_last_90d,
        COUNT(*) FILTER (WHERE txn_date >= (SELECT MAX(txn_date) FROM fact_transactions)
                                            - INTERVAL '30 days')             AS txn_last_30d,
        COUNT(*)                                                              AS total_txns,
        ROUND(SUM(amount)::NUMERIC, 2)                                        AS total_gmv
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
churn_flags AS (
    SELECT *,
        (SELECT MAX(txn_date) FROM fact_transactions WHERE status='SUCCESS') - last_txn_date
                                                                              AS days_since_last_txn,
        CASE
            WHEN (SELECT MAX(txn_date) FROM fact_transactions WHERE status='SUCCESS') - last_txn_date > 60
             AND txn_last_90d < 2                                             THEN 'High Risk'
            WHEN (SELECT MAX(txn_date) FROM fact_transactions WHERE status='SUCCESS') - last_txn_date BETWEEN 30 AND 60
             AND txn_last_90d < 5                                             THEN 'Medium Risk'
            WHEN txn_last_30d = 0                                             THEN 'Slipping Away'
            ELSE 'Active / Low Risk'
        END                                                                   AS churn_risk_label
    FROM customer_activity
)
SELECT
    churn_risk_label,
    COUNT(customer_id)               AS customer_count,
    ROUND(AVG(days_since_last_txn))  AS avg_days_inactive,
    ROUND(AVG(total_txns))           AS avg_lifetime_txns,
    ROUND(SUM(total_gmv)::NUMERIC,2) AS at_risk_gmv
FROM churn_flags
GROUP BY churn_risk_label
ORDER BY
    CASE churn_risk_label
        WHEN 'High Risk'       THEN 1
        WHEN 'Medium Risk'     THEN 2
        WHEN 'Slipping Away'   THEN 3
        ELSE 4
    END;


-- ─────────────────────────────────────────
-- CUST-06: NEW vs RETURNING USER SPLIT (Monthly)
-- Business use: Is growth coming from acquisition or retention?
-- ─────────────────────────────────────────

WITH first_txn AS (
    SELECT customer_id, DATE_TRUNC('month', MIN(txn_date)) AS first_month
    FROM fact_transactions WHERE status='SUCCESS'
    GROUP BY customer_id
),
monthly_txns AS (
    SELECT customer_id, DATE_TRUNC('month', txn_date) AS txn_month
    FROM fact_transactions WHERE status='SUCCESS'
    GROUP BY customer_id, DATE_TRUNC('month', txn_date)
)
SELECT
    TO_CHAR(mt.txn_month, 'YYYY-MM')    AS month,
    COUNT(DISTINCT CASE WHEN mt.txn_month = ft.first_month THEN mt.customer_id END) AS new_users,
    COUNT(DISTINCT CASE WHEN mt.txn_month > ft.first_month  THEN mt.customer_id END) AS returning_users
FROM monthly_txns mt
JOIN first_txn ft ON mt.customer_id = ft.customer_id
GROUP BY mt.txn_month
ORDER BY month;


-- ─────────────────────────────────────────
-- CUST-07: CLV BY CUSTOMER SEGMENT
-- Business use: Which segments to invest acquisition budget in
-- ─────────────────────────────────────────

SELECT
    c.segment_tag,
    COUNT(DISTINCT f.customer_id)                                              AS customer_count,
    ROUND(AVG(
        (f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt
    )::NUMERIC, 4)                                                             AS avg_net_revenue_per_txn,
    ROUND(SUM(f.amount)::NUMERIC, 2)                                           AS total_gmv,
    ROUND(SUM(
        (f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt
    )::NUMERIC, 2)                                                             AS total_net_revenue,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt) /
        NULLIF(COUNT(DISTINCT f.customer_id), 0)
    ::NUMERIC, 2)                                                              AS avg_clv_per_customer
FROM fact_transactions f
JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE f.status = 'SUCCESS'
GROUP BY c.segment_tag
ORDER BY avg_clv_per_customer DESC;


-- ─────────────────────────────────────────
-- CUST-08: TOP 100 CUSTOMERS BY LIFETIME VALUE
-- Business use: VIP list for loyalty programs
-- ─────────────────────────────────────────

SELECT
    f.customer_id,
    c.segment_tag,
    ci.city_name,
    ci.tier,
    COUNT(f.transaction_id)                                                    AS total_txns,
    ROUND(SUM(f.amount)::NUMERIC, 2)                                           AS total_spend,
    ROUND(SUM(
        (f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt
    )::NUMERIC, 2)                                                             AS lifetime_value,
    MIN(f.txn_date)                                                            AS first_txn_date,
    MAX(f.txn_date)                                                            AS last_txn_date
FROM fact_transactions f
JOIN dim_customer c  ON f.customer_id = c.customer_id
JOIN dim_city ci     ON c.city_id = ci.city_id
WHERE f.status = 'SUCCESS'
GROUP BY f.customer_id, c.segment_tag, ci.city_name, ci.tier
ORDER BY lifetime_value DESC
LIMIT 100;
