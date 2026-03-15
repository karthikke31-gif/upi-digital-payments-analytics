-- ============================================================
-- UPI Transaction Analytics Project
-- Script 08: Cohort Retention Analysis (Month 1, 3, 6, 12)
-- ============================================================

-- -------------------------------------------------------
-- COHORT 1: Build Cohort Table
-- Each user's cohort = month of their FIRST transaction
-- -------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS user_cohorts AS
SELECT
    customer_id,
    STRFTIME('%Y-%m', MIN(txn_date)) AS cohort_month
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY customer_id;

-- -------------------------------------------------------
-- COHORT 2: Activity Matrix (user × month number)
-- -------------------------------------------------------
CREATE TEMP TABLE IF NOT EXISTS cohort_activity AS
SELECT
    uc.customer_id,
    uc.cohort_month,
    STRFTIME('%Y-%m', f.txn_date)  AS activity_month,
    -- Months since cohort (0 = first month, 1 = Month 1 retention, etc.)
    (
        (CAST(STRFTIME('%Y', f.txn_date) AS INT) - CAST(STRFTIME('%Y', uc.cohort_month || '-01') AS INT)) * 12
        + (CAST(STRFTIME('%m', f.txn_date) AS INT) - CAST(STRFTIME('%m', uc.cohort_month || '-01') AS INT))
    ) AS months_since_cohort
FROM user_cohorts uc
JOIN fact_transactions f ON uc.customer_id = f.customer_id
WHERE f.status = 'SUCCESS'
GROUP BY uc.customer_id, uc.cohort_month, STRFTIME('%Y-%m', f.txn_date);

-- -------------------------------------------------------
-- COHORT 3: Cohort Size per Month
-- -------------------------------------------------------
SELECT
    cohort_month,
    COUNT(DISTINCT customer_id) AS cohort_size
FROM user_cohorts
GROUP BY cohort_month
ORDER BY cohort_month;

-- -------------------------------------------------------
-- COHORT 4: Full Retention Heatmap
-- Rows = cohort month, Columns = months 0-11
-- -------------------------------------------------------
WITH cohort_counts AS (
    SELECT
        cohort_month,
        months_since_cohort,
        COUNT(DISTINCT customer_id) AS retained_users
    FROM cohort_activity
    WHERE months_since_cohort BETWEEN 0 AND 11
    GROUP BY cohort_month, months_since_cohort
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM user_cohorts
    GROUP BY cohort_month
)
SELECT
    cc.cohort_month,
    cs.cohort_size,
    cc.months_since_cohort,
    cc.retained_users,
    ROUND(cc.retained_users * 100.0 / cs.cohort_size, 2) AS retention_pct
FROM cohort_counts cc
JOIN cohort_sizes cs ON cc.cohort_month = cs.cohort_month
ORDER BY cc.cohort_month, cc.months_since_cohort;

-- -------------------------------------------------------
-- COHORT 5: Key Retention Milestones — Month 1, 3, 6
-- (The numbers companies like PhonePe/Google Pay track)
-- -------------------------------------------------------
WITH cohort_counts AS (
    SELECT
        cohort_month,
        months_since_cohort,
        COUNT(DISTINCT customer_id) AS retained_users
    FROM cohort_activity
    GROUP BY cohort_month, months_since_cohort
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM user_cohorts
    GROUP BY cohort_month
),
pivoted AS (
    SELECT
        cs.cohort_month,
        cs.cohort_size,
        MAX(CASE WHEN months_since_cohort = 0  THEN retained_users END) AS m0_users,
        MAX(CASE WHEN months_since_cohort = 1  THEN retained_users END) AS m1_users,
        MAX(CASE WHEN months_since_cohort = 3  THEN retained_users END) AS m3_users,
        MAX(CASE WHEN months_since_cohort = 6  THEN retained_users END) AS m6_users,
        MAX(CASE WHEN months_since_cohort = 11 THEN retained_users END) AS m12_users
    FROM cohort_sizes cs
    LEFT JOIN cohort_counts cc ON cs.cohort_month = cc.cohort_month
    GROUP BY cs.cohort_month, cs.cohort_size
)
SELECT
    cohort_month,
    cohort_size,
    ROUND(m1_users  * 100.0 / cohort_size, 2)  AS month1_retention_pct,
    ROUND(m3_users  * 100.0 / cohort_size, 2)  AS month3_retention_pct,
    ROUND(m6_users  * 100.0 / cohort_size, 2)  AS month6_retention_pct,
    ROUND(m12_users * 100.0 / cohort_size, 2)  AS month12_retention_pct
FROM pivoted
ORDER BY cohort_month;

-- -------------------------------------------------------
-- COHORT 6: Average Retention across All Cohorts
-- -------------------------------------------------------
WITH cohort_counts AS (
    SELECT
        cohort_month,
        months_since_cohort,
        COUNT(DISTINCT customer_id) AS retained_users
    FROM cohort_activity
    GROUP BY cohort_month, months_since_cohort
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM user_cohorts
    GROUP BY cohort_month
)
SELECT
    cc.months_since_cohort,
    ROUND(AVG(cc.retained_users * 100.0 / cs.cohort_size), 2) AS avg_retention_pct,
    SUM(cc.retained_users)                                      AS total_retained,
    SUM(cs.cohort_size)                                         AS total_cohort_size
FROM cohort_counts cc
JOIN cohort_sizes cs ON cc.cohort_month = cs.cohort_month
WHERE cc.months_since_cohort BETWEEN 0 AND 11
GROUP BY cc.months_since_cohort
ORDER BY cc.months_since_cohort;

-- -------------------------------------------------------
-- COHORT 7: Cohort Revenue — How much does each cohort earn?
-- -------------------------------------------------------
SELECT
    uc.cohort_month,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS cohort_lifetime_revenue,
    COUNT(DISTINCT uc.customer_id)   AS cohort_size,
    ROUND(
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
        / COUNT(DISTINCT uc.customer_id),
    4) AS revenue_per_user
FROM user_cohorts uc
JOIN fact_transactions f ON uc.customer_id = f.customer_id
WHERE f.status = 'SUCCESS'
GROUP BY uc.cohort_month
ORDER BY uc.cohort_month;

-- ============================================================
-- END OF SCRIPT 08
-- ============================================================
