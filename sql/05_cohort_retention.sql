-- ============================================================
-- FILE: 05_cohort_retention.sql
-- PURPOSE: Cohort retention at Month 1, 3, 6 + DAU/MAU Stickiness
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- SECTION 1: COHORT DEFINITION
-- Cohort = month of customer's first transaction
-- ────────────────────────────────────────────────────────────

-- Step 1: Find each customer's first transaction month
WITH first_txn AS (
    SELECT
        customer_id,
        strftime('%Y-%m', MIN(txn_date))    AS cohort_month,
        MIN(txn_date)                        AS first_txn_date
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),

-- Step 2: Get all months each customer was active
customer_activity AS (
    SELECT
        f.customer_id,
        strftime('%Y-%m', f.txn_date)       AS activity_month
    FROM fact_transactions f
    WHERE f.status = 'SUCCESS'
    GROUP BY f.customer_id, strftime('%Y-%m', f.txn_date)
),

-- Step 3: Compute months since cohort (0 = acquisition month)
cohort_activity AS (
    SELECT
        ft.cohort_month,
        ft.customer_id,
        ca.activity_month,
        -- Month difference approximation
        (CAST(strftime('%Y', ca.activity_month || '-01') AS INTEGER) * 12 +
         CAST(strftime('%m', ca.activity_month || '-01') AS INTEGER))
        -
        (CAST(strftime('%Y', ft.cohort_month || '-01') AS INTEGER) * 12 +
         CAST(strftime('%m', ft.cohort_month || '-01') AS INTEGER))  AS months_since_cohort
    FROM first_txn ft
    JOIN customer_activity ca ON ft.customer_id = ca.customer_id
    WHERE (
        (CAST(strftime('%Y', ca.activity_month || '-01') AS INTEGER) * 12 +
         CAST(strftime('%m', ca.activity_month || '-01') AS INTEGER))
        -
        (CAST(strftime('%Y', ft.cohort_month || '-01') AS INTEGER) * 12 +
         CAST(strftime('%m', ft.cohort_month || '-01') AS INTEGER))
    ) BETWEEN 0 AND 11
),

-- Step 4: Cohort sizes (number of users acquired in each cohort month)
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS cohort_size
    FROM first_txn
    GROUP BY cohort_month
)

-- Step 5: Final cohort retention table
SELECT
    ca.cohort_month,
    cs.cohort_size,
    ca.months_since_cohort,
    COUNT(DISTINCT ca.customer_id)                              AS active_users,
    ROUND(
        100.0 * COUNT(DISTINCT ca.customer_id) / cs.cohort_size
    , 2)                                                        AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.cohort_size, ca.months_since_cohort
ORDER BY ca.cohort_month, ca.months_since_cohort;


-- ────────────────────────────────────────────────────────────
-- SECTION 2: RETENTION SUMMARY (Month 1, 3, 6 pivot)
-- ────────────────────────────────────────────────────────────

WITH first_txn AS (
    SELECT customer_id,
           strftime('%Y-%m', MIN(txn_date)) AS cohort_month
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
customer_activity AS (
    SELECT customer_id,
           strftime('%Y-%m', txn_date) AS activity_month
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id, strftime('%Y-%m', txn_date)
),
cohort_activity AS (
    SELECT
        ft.cohort_month,
        ft.customer_id,
        (CAST(strftime('%Y', ca.activity_month || '-01') AS INTEGER) * 12 +
         CAST(strftime('%m', ca.activity_month || '-01') AS INTEGER))
        -
        (CAST(strftime('%Y', ft.cohort_month || '-01') AS INTEGER) * 12 +
         CAST(strftime('%m', ft.cohort_month || '-01') AS INTEGER))  AS months_since
    FROM first_txn ft
    JOIN customer_activity ca ON ft.customer_id = ca.customer_id
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(DISTINCT customer_id) AS sz
    FROM first_txn
    GROUP BY cohort_month
)
SELECT
    ca.cohort_month,
    cs.sz                                                                       AS cohort_size,
    ROUND(100.0 * SUM(CASE WHEN months_since = 0 THEN 1 ELSE 0 END) / cs.sz, 2) AS month_0_pct,
    ROUND(100.0 * SUM(CASE WHEN months_since = 1 THEN 1 ELSE 0 END) / cs.sz, 2) AS month_1_pct,
    ROUND(100.0 * SUM(CASE WHEN months_since = 3 THEN 1 ELSE 0 END) / cs.sz, 2) AS month_3_pct,
    ROUND(100.0 * SUM(CASE WHEN months_since = 6 THEN 1 ELSE 0 END) / cs.sz, 2) AS month_6_pct
FROM cohort_activity ca
JOIN cohort_sizes cs ON ca.cohort_month = cs.cohort_month
GROUP BY ca.cohort_month, cs.sz
ORDER BY ca.cohort_month;


-- ────────────────────────────────────────────────────────────
-- SECTION 3: NEW vs RETURNING USER TREND
-- ────────────────────────────────────────────────────────────

WITH first_txn AS (
    SELECT customer_id,
           strftime('%Y-%m', MIN(txn_date)) AS first_month
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    strftime('%Y-%m', f.txn_date)   AS month,
    SUM(CASE WHEN strftime('%Y-%m', f.txn_date) = ft.first_month THEN 1 ELSE 0 END) AS new_users,
    SUM(CASE WHEN strftime('%Y-%m', f.txn_date) != ft.first_month THEN 1 ELSE 0 END) AS returning_users,
    COUNT(DISTINCT f.customer_id)                                                    AS total_active_users
FROM fact_transactions f
JOIN first_txn ft ON f.customer_id = ft.customer_id
WHERE f.status = 'SUCCESS'
GROUP BY strftime('%Y-%m', f.txn_date)
ORDER BY month;


-- ────────────────────────────────────────────────────────────
-- SECTION 4: CHURN RISK FUNNEL
-- Rules-based churn segmentation (no ML)
-- ────────────────────────────────────────────────────────────

WITH customer_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)                   AS last_txn_date,
        COUNT(*)                        AS total_txns,
        COUNT(CASE WHEN txn_date >= date('now', '-90 days') THEN 1 END) AS txns_last_90d,
        COUNT(CASE WHEN txn_date >= date('now', '-30 days') THEN 1 END) AS txns_last_30d,
        SUM(amount)                     AS total_spend,
        AVG(amount)                     AS avg_txn_value
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
    ROUND(total_spend, 2)               AS total_spend,
    ROUND(JULIANDAY('now') - JULIANDAY(last_txn_date), 0) AS days_since_last_txn,
    CASE
        WHEN JULIANDAY('now') - JULIANDAY(last_txn_date) > 90
             AND txns_last_90d = 0      THEN 'CHURNED'
        WHEN JULIANDAY('now') - JULIANDAY(last_txn_date) > 60
             AND txns_last_90d < 2      THEN 'HIGH_RISK'
        WHEN JULIANDAY('now') - JULIANDAY(last_txn_date) > 30
             AND txns_last_30d = 0      THEN 'AT_RISK'
        WHEN txns_last_30d >= 1
             AND txns_last_90d >= 3     THEN 'ACTIVE'
        ELSE                                 'MODERATE_RISK'
    END                                 AS churn_segment
FROM customer_activity
ORDER BY days_since_last_txn DESC;

-- Churn Funnel Summary
WITH customer_activity AS (
    SELECT
        customer_id,
        MAX(txn_date)   AS last_txn_date,
        COUNT(*)        AS total_txns,
        COUNT(CASE WHEN txn_date >= date('now', '-90 days') THEN 1 END) AS txns_last_90d,
        COUNT(CASE WHEN txn_date >= date('now', '-30 days') THEN 1 END) AS txns_last_30d
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
segments AS (
    SELECT
        CASE
            WHEN JULIANDAY('now') - JULIANDAY(last_txn_date) > 90 AND txns_last_90d = 0 THEN 'CHURNED'
            WHEN JULIANDAY('now') - JULIANDAY(last_txn_date) > 60 AND txns_last_90d < 2 THEN 'HIGH_RISK'
            WHEN JULIANDAY('now') - JULIANDAY(last_txn_date) > 30 AND txns_last_30d = 0 THEN 'AT_RISK'
            WHEN txns_last_30d >= 1 AND txns_last_90d >= 3                               THEN 'ACTIVE'
            ELSE                                                                               'MODERATE_RISK'
        END AS churn_segment
    FROM customer_activity
)
SELECT
    churn_segment,
    COUNT(*)                                                        AS user_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)             AS pct_of_users
FROM segments
GROUP BY churn_segment
ORDER BY user_count DESC;
