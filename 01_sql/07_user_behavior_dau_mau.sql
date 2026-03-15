-- ============================================================
-- UPI Transaction Analytics Project
-- Script 07: User Behavior — DAU, MAU, Stickiness Ratio
-- ============================================================

-- -------------------------------------------------------
-- UB 1: Daily Active Users (DAU) — Last 30 Days
-- -------------------------------------------------------
SELECT
    txn_date,
    COUNT(DISTINCT customer_id) AS dau
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY txn_date
ORDER BY txn_date;

-- -------------------------------------------------------
-- UB 2: Monthly Active Users (MAU)
-- -------------------------------------------------------
SELECT
    STRFTIME('%Y-%m', txn_date) AS month,
    COUNT(DISTINCT customer_id) AS mau,
    COUNT(*)                     AS txn_count,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT customer_id), 2) AS avg_txns_per_user
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- UB 3: Stickiness Ratio = Avg(DAU) / MAU per Month
-- Healthy fintech stickiness > 20%
-- -------------------------------------------------------
WITH daily_active AS (
    SELECT
        txn_date,
        STRFTIME('%Y-%m', txn_date)  AS month,
        COUNT(DISTINCT customer_id)  AS dau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY txn_date
),
monthly_active AS (
    SELECT
        STRFTIME('%Y-%m', txn_date) AS month,
        COUNT(DISTINCT customer_id) AS mau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY STRFTIME('%Y-%m', txn_date)
),
avg_dau AS (
    SELECT month, ROUND(AVG(dau), 2) AS avg_dau
    FROM daily_active
    GROUP BY month
)
SELECT
    m.month,
    m.mau,
    a.avg_dau,
    ROUND(a.avg_dau / NULLIF(m.mau, 0) * 100, 2) AS stickiness_pct
FROM monthly_active m
JOIN avg_dau a ON m.month = a.month
ORDER BY m.month;

-- -------------------------------------------------------
-- UB 4: New vs Returning Users per Month
-- -------------------------------------------------------
WITH first_txn_month AS (
    SELECT
        customer_id,
        STRFTIME('%Y-%m', MIN(txn_date)) AS first_month
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
),
monthly_users AS (
    SELECT
        STRFTIME('%Y-%m', f.txn_date) AS month,
        f.customer_id,
        ft.first_month
    FROM fact_transactions f
    JOIN first_txn_month ft ON f.customer_id = ft.customer_id
    WHERE f.status = 'SUCCESS'
    GROUP BY STRFTIME('%Y-%m', f.txn_date), f.customer_id, ft.first_month
)
SELECT
    month,
    COUNT(DISTINCT customer_id)                                                       AS total_active,
    COUNT(DISTINCT CASE WHEN month = first_month THEN customer_id END)               AS new_users,
    COUNT(DISTINCT CASE WHEN month != first_month THEN customer_id END)              AS returning_users,
    ROUND(COUNT(DISTINCT CASE WHEN month != first_month THEN customer_id END) * 100.0
          / NULLIF(COUNT(DISTINCT customer_id), 0), 2)                               AS returning_pct
FROM monthly_users
GROUP BY month
ORDER BY month;

-- -------------------------------------------------------
-- UB 5: User Transaction Frequency Distribution
-- -------------------------------------------------------
WITH user_freq AS (
    SELECT
        customer_id,
        COUNT(*) AS txn_count
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    CASE
        WHEN txn_count = 1             THEN '1 transaction'
        WHEN txn_count BETWEEN 2 AND 5 THEN '2-5 transactions'
        WHEN txn_count BETWEEN 6 AND 10 THEN '6-10 transactions'
        WHEN txn_count BETWEEN 11 AND 20 THEN '11-20 transactions'
        ELSE '20+ transactions'
    END AS frequency_bucket,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
FROM user_freq
GROUP BY frequency_bucket
ORDER BY MIN(txn_count);

-- -------------------------------------------------------
-- UB 6: Power Users — Top 10% by Transaction Volume
-- -------------------------------------------------------
WITH user_stats AS (
    SELECT
        customer_id,
        COUNT(*)                 AS txn_count,
        ROUND(SUM(amount), 2)   AS total_spent,
        NTILE(10) OVER (ORDER BY SUM(amount) DESC) AS decile
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    decile,
    COUNT(*) AS user_count,
    ROUND(SUM(total_spent), 2)   AS total_gmv,
    ROUND(AVG(total_spent), 2)   AS avg_gmv_per_user,
    ROUND(SUM(total_spent) * 100.0 / SUM(SUM(total_spent)) OVER (), 2) AS gmv_share_pct
FROM user_stats
GROUP BY decile
ORDER BY decile;

-- -------------------------------------------------------
-- UB 7: Weekend vs Weekday Transaction Patterns
-- -------------------------------------------------------
SELECT
    dd.is_weekend,
    COUNT(*)                         AS txn_count,
    ROUND(SUM(f.amount), 2)         AS gmv,
    COUNT(DISTINCT f.customer_id)   AS unique_users,
    ROUND(AVG(f.amount), 2)         AS avg_txn_value
FROM fact_transactions f
JOIN dim_date dd ON f.txn_date = dd.date
WHERE f.status = 'SUCCESS'
GROUP BY dd.is_weekend;

-- -------------------------------------------------------
-- UB 8: Hour-of-Day Transaction Pattern
-- -------------------------------------------------------
SELECT
    CAST(STRFTIME('%H', txn_ts) AS INT) AS hour_of_day,
    COUNT(*)                             AS txn_count,
    ROUND(SUM(amount), 2)               AS gmv,
    COUNT(DISTINCT customer_id)         AS unique_users
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY CAST(STRFTIME('%H', txn_ts) AS INT)
ORDER BY hour_of_day;

-- ============================================================
-- END OF SCRIPT 07
-- ============================================================
