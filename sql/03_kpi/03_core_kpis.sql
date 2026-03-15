-- ============================================================
-- UPI TRANSACTION ANALYTICS PROJECT
-- FILE: 03_core_kpis.sql
-- PURPOSE: All platform-level KPIs — GMV, Net Revenue, Margin,
--          MAU, DAU, MoM Growth, Stickiness
-- ============================================================


-- ─────────────────────────────────────────
-- KPI-01: TOTAL GMV (Gross Merchandise Value)
-- Definition: Sum of all successful transaction amounts
-- ─────────────────────────────────────────

SELECT
    ROUND(SUM(amount)::NUMERIC, 2) AS total_gmv
FROM fact_transactions
WHERE status = 'SUCCESS';


-- ─────────────────────────────────────────
-- KPI-02: NET REVENUE
-- Formula: (MDR% × Amount) - Cashback - Processing Fee
-- ─────────────────────────────────────────

SELECT
    ROUND(SUM((mdr_pct / 100.0) * amount)::NUMERIC, 2)              AS gross_mdr_revenue,
    ROUND(SUM(cashback_amt)::NUMERIC, 2)                             AS total_cashback_cost,
    ROUND(SUM(processing_fee_amt)::NUMERIC, 2)                       AS total_processing_cost,
    ROUND(SUM(
        (mdr_pct / 100.0) * amount - cashback_amt - processing_fee_amt
    )::NUMERIC, 2)                                                   AS net_revenue
FROM fact_transactions
WHERE status = 'SUCCESS';


-- ─────────────────────────────────────────
-- KPI-03: OVERALL MARGIN %
-- Formula: Net Revenue / GMV × 100
-- ─────────────────────────────────────────

SELECT
    ROUND(
        SUM((mdr_pct / 100.0) * amount - cashback_amt - processing_fee_amt) /
        NULLIF(SUM(amount), 0) * 100
    , 4) AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS';


-- ─────────────────────────────────────────
-- KPI-04: MONTHLY GMV, NET REVENUE & MARGIN %
-- Business use: track platform growth month by month
-- ─────────────────────────────────────────

SELECT
    TO_CHAR(DATE_TRUNC('month', txn_date), 'YYYY-MM')                       AS month,
    COUNT(*)                                                                 AS txn_count,
    COUNT(DISTINCT customer_id)                                              AS mau,
    ROUND(SUM(amount)::NUMERIC, 2)                                           AS gmv,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)::NUMERIC, 2) AS net_revenue,
    ROUND(
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) /
        NULLIF(SUM(amount),0) * 100
    , 4)                                                                     AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY DATE_TRUNC('month', txn_date)
ORDER BY month;


-- ─────────────────────────────────────────
-- KPI-05: MoM GROWTH % (Revenue & GMV)
-- Business use: Is the platform accelerating or decelerating?
-- ─────────────────────────────────────────

WITH monthly AS (
    SELECT
        DATE_TRUNC('month', txn_date)                                            AS month,
        SUM(amount)                                                              AS gmv,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)          AS net_revenue,
        COUNT(DISTINCT customer_id)                                              AS mau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY DATE_TRUNC('month', txn_date)
)
SELECT
    TO_CHAR(month, 'YYYY-MM')                                                   AS month,
    ROUND(gmv::NUMERIC, 2)                                                      AS gmv,
    ROUND(net_revenue::NUMERIC, 2)                                              AS net_revenue,
    mau,
    ROUND(
        100.0 * (gmv - LAG(gmv) OVER (ORDER BY month)) /
        NULLIF(LAG(gmv) OVER (ORDER BY month), 0)
    , 2)                                                                        AS gmv_mom_growth_pct,
    ROUND(
        100.0 * (net_revenue - LAG(net_revenue) OVER (ORDER BY month)) /
        NULLIF(LAG(net_revenue) OVER (ORDER BY month), 0)
    , 2)                                                                        AS revenue_mom_growth_pct,
    ROUND(
        100.0 * (mau - LAG(mau) OVER (ORDER BY month)) /
        NULLIF(LAG(mau) OVER (ORDER BY month), 0)
    , 2)                                                                        AS mau_mom_growth_pct
FROM monthly
ORDER BY month;


-- ─────────────────────────────────────────
-- KPI-06: MAU (Monthly Active Users)
-- Definition: Unique customers who transacted in a month
-- ─────────────────────────────────────────

SELECT
    TO_CHAR(DATE_TRUNC('month', txn_date), 'YYYY-MM') AS month,
    COUNT(DISTINCT customer_id)                        AS mau
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY DATE_TRUNC('month', txn_date)
ORDER BY month;


-- ─────────────────────────────────────────
-- KPI-07: DAU (Daily Active Users) - last 30 days
-- ─────────────────────────────────────────

SELECT
    txn_date,
    COUNT(DISTINCT customer_id) AS dau
FROM fact_transactions
WHERE status = 'SUCCESS'
  AND txn_date >= (SELECT MAX(txn_date) - INTERVAL '30 days' FROM fact_transactions)
GROUP BY txn_date
ORDER BY txn_date;


-- ─────────────────────────────────────────
-- KPI-08: STICKINESS RATIO (DAU/MAU)
-- Formula: Avg daily unique users / Monthly unique users
-- Higher = more engagement
-- ─────────────────────────────────────────

WITH daily_active AS (
    SELECT
        DATE_TRUNC('month', txn_date) AS month,
        txn_date,
        COUNT(DISTINCT customer_id)   AS dau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY DATE_TRUNC('month', txn_date), txn_date
),
monthly_active AS (
    SELECT
        DATE_TRUNC('month', txn_date) AS month,
        COUNT(DISTINCT customer_id)   AS mau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY DATE_TRUNC('month', txn_date)
),
avg_dau AS (
    SELECT month, ROUND(AVG(dau), 2) AS avg_daily_active
    FROM daily_active
    GROUP BY month
)
SELECT
    TO_CHAR(m.month, 'YYYY-MM')            AS month,
    m.mau,
    a.avg_daily_active,
    ROUND(a.avg_daily_active / NULLIF(m.mau, 0) * 100, 2) AS stickiness_pct
FROM monthly_active m
JOIN avg_dau a ON m.month = a.month
ORDER BY m.month;


-- ─────────────────────────────────────────
-- KPI-09: TRANSACTION SUCCESS RATE & FAILURE ANALYSIS
-- Business use: Operational reliability metric
-- ─────────────────────────────────────────

SELECT
    status,
    COUNT(*)                                                             AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                  AS pct_of_total,
    ROUND(SUM(amount)::NUMERIC, 2)                                       AS total_amount
FROM fact_transactions
GROUP BY status
ORDER BY txn_count DESC;


-- ─────────────────────────────────────────
-- KPI-10: FAILED TRANSACTIONS BY CHANNEL
-- Business use: Find which channels have highest failure rates
-- ─────────────────────────────────────────

SELECT
    ch.channel_name,
    COUNT(*)                                                             AS total_txns,
    COUNT(*) FILTER (WHERE f.status = 'FAILED')                         AS failed_txns,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE f.status = 'FAILED') /
        NULLIF(COUNT(*), 0)
    , 2)                                                                 AS failure_rate_pct
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
GROUP BY ch.channel_name
ORDER BY failure_rate_pct DESC;


-- ─────────────────────────────────────────
-- KPI-11: RETRY ANALYSIS
-- Business use: High retries = bad UX and higher processing costs
-- ─────────────────────────────────────────

SELECT
    retry_count,
    COUNT(*)                                                             AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                  AS pct_of_total,
    ROUND(AVG(processing_fee_amt)::NUMERIC, 4)                          AS avg_processing_fee,
    COUNT(*) FILTER (WHERE status = 'SUCCESS')                          AS success_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE status='SUCCESS') / NULLIF(COUNT(*),0)
    , 2)                                                                 AS success_rate_pct
FROM fact_transactions
GROUP BY retry_count
ORDER BY retry_count;


-- ─────────────────────────────────────────
-- KPI-12: DEVICE OS BREAKDOWN
-- Business use: Prioritize app improvements
-- ─────────────────────────────────────────

SELECT
    device_os,
    COUNT(*)                                                             AS txn_count,
    ROUND(SUM(amount)::NUMERIC, 2)                                       AS gmv,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                  AS pct_of_total,
    ROUND(AVG(amount)::NUMERIC, 2)                                       AS avg_txn_value
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY device_os
ORDER BY txn_count DESC;


-- ─────────────────────────────────────────
-- KPI-13: WEEKEND VS WEEKDAY SPENDING PATTERNS
-- Business use: Plan cashback campaigns on high-volume days
-- ─────────────────────────────────────────

SELECT
    d.is_weekend,
    d.holiday_flag,
    COUNT(f.transaction_id)                AS txn_count,
    ROUND(SUM(f.amount)::NUMERIC, 2)       AS total_gmv,
    ROUND(AVG(f.amount)::NUMERIC, 2)       AS avg_txn_amount
FROM fact_transactions f
JOIN dim_date d ON f.txn_date = d.date
WHERE f.status = 'SUCCESS'
GROUP BY d.is_weekend, d.holiday_flag
ORDER BY is_weekend, holiday_flag;


-- ─────────────────────────────────────────
-- KPI-14: PROCESSING COST PER TRANSACTION
-- Business use: Monitor cost efficiency
-- ─────────────────────────────────────────

SELECT
    ROUND(AVG(processing_fee_amt)::NUMERIC, 4)  AS avg_processing_fee_per_txn,
    ROUND(MIN(processing_fee_amt)::NUMERIC, 4)  AS min_fee,
    ROUND(MAX(processing_fee_amt)::NUMERIC, 4)  AS max_fee,
    ROUND(SUM(processing_fee_amt)::NUMERIC, 2)  AS total_processing_cost,
    ROUND(
        SUM(processing_fee_amt) / NULLIF(SUM(amount), 0) * 100
    ::NUMERIC, 4)                               AS processing_cost_as_pct_gmv
FROM fact_transactions
WHERE status = 'SUCCESS';
