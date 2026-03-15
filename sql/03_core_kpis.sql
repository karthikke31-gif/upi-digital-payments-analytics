-- ============================================================
-- FILE: 03_core_kpis.sql
-- PURPOSE: All platform-level KPIs
-- GMV, Net Revenue, Margin, MAU, DAU, Stickiness, MoM Growth
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- KPI 1: TOTAL GMV (Gross Merchandise Value)
-- Definition: Total value of all successful transactions
-- ────────────────────────────────────────────────────────────

SELECT
    ROUND(SUM(amount), 2)           AS total_gmv,
    COUNT(*)                        AS total_successful_txns,
    ROUND(AVG(amount), 2)           AS avg_transaction_value
FROM fact_transactions
WHERE status = 'SUCCESS';

-- Monthly GMV Trend
SELECT
    strftime('%Y-%m', txn_date)     AS month,
    ROUND(SUM(amount), 2)           AS monthly_gmv,
    COUNT(*)                        AS txn_count,
    COUNT(DISTINCT customer_id)     AS unique_customers
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- ────────────────────────────────────────────────────────────
-- KPI 2: NET REVENUE
-- Definition: MDR Income - Cashback - Processing Fees
-- Formula: (mdr_pct/100 * amount) - cashback_amt - processing_fee_amt
-- ────────────────────────────────────────────────────────────

SELECT
    ROUND(SUM(amount), 2)                                             AS total_gmv,
    ROUND(SUM((mdr_pct / 100.0) * amount), 2)                        AS gross_mdr_revenue,
    ROUND(SUM(cashback_amt), 2)                                       AS total_cashback_cost,
    ROUND(SUM(processing_fee_amt), 2)                                 AS total_processing_cost,
    ROUND(SUM((mdr_pct / 100.0) * amount
              - cashback_amt
              - processing_fee_amt), 2)                               AS net_revenue
FROM fact_transactions
WHERE status = 'SUCCESS';

-- Monthly Net Revenue Trend
SELECT
    strftime('%Y-%m', txn_date)                                       AS month,
    ROUND(SUM(amount), 2)                                             AS gmv,
    ROUND(SUM((mdr_pct / 100.0) * amount
              - cashback_amt
              - processing_fee_amt), 2)                               AS net_revenue,
    ROUND(SUM(cashback_amt), 2)                                       AS cashback_spent,
    ROUND(SUM(processing_fee_amt), 2)                                 AS processing_costs
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- ────────────────────────────────────────────────────────────
-- KPI 3: MARGIN %
-- Definition: Net Revenue / GMV * 100
-- ────────────────────────────────────────────────────────────

SELECT
    ROUND(
        SUM((mdr_pct / 100.0) * amount - cashback_amt - processing_fee_amt)
        / NULLIF(SUM(amount), 0) * 100
    , 4)                                                              AS overall_margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS';

-- Monthly Margin Trend
SELECT
    strftime('%Y-%m', txn_date)                                       AS month,
    ROUND(SUM(amount), 2)                                             AS gmv,
    ROUND(SUM((mdr_pct / 100.0) * amount
              - cashback_amt - processing_fee_amt), 2)                AS net_revenue,
    ROUND(
        SUM((mdr_pct / 100.0) * amount - cashback_amt - processing_fee_amt)
        / NULLIF(SUM(amount), 0) * 100
    , 4)                                                              AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- ────────────────────────────────────────────────────────────
-- KPI 4: ACTIVE USERS (MAU - Monthly Active Users)
-- Definition: Unique customers with at least 1 transaction per month
-- ────────────────────────────────────────────────────────────

SELECT
    strftime('%Y-%m', txn_date)         AS month,
    COUNT(DISTINCT customer_id)         AS MAU,
    COUNT(*)                            AS total_txns,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT customer_id), 2) AS avg_txns_per_user
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- ────────────────────────────────────────────────────────────
-- KPI 5: DAU (Daily Active Users) & Stickiness
-- Stickiness = DAU / MAU (shows how often monthly users return daily)
-- ────────────────────────────────────────────────────────────

-- Daily Active Users
SELECT
    txn_date,
    COUNT(DISTINCT customer_id)         AS DAU
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY txn_date
ORDER BY txn_date DESC
LIMIT 60;

-- Monthly Average DAU
SELECT
    strftime('%Y-%m', txn_date)         AS month,
    ROUND(AVG(daily_users), 0)          AS avg_DAU
FROM (
    SELECT txn_date,
           COUNT(DISTINCT customer_id)  AS daily_users
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY txn_date
) daily
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- Stickiness Ratio = Avg DAU / MAU per month
WITH dau_monthly AS (
    SELECT
        strftime('%Y-%m', txn_date)         AS month,
        ROUND(AVG(daily_users), 2)          AS avg_dau
    FROM (
        SELECT txn_date,
               COUNT(DISTINCT customer_id)  AS daily_users
        FROM fact_transactions
        WHERE status = 'SUCCESS'
        GROUP BY txn_date
    ) daily
    GROUP BY strftime('%Y-%m', txn_date)
),
mau_monthly AS (
    SELECT
        strftime('%Y-%m', txn_date)         AS month,
        COUNT(DISTINCT customer_id)         AS mau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY strftime('%Y-%m', txn_date)
)
SELECT
    d.month,
    d.avg_dau,
    m.mau,
    ROUND(d.avg_dau / NULLIF(m.mau, 0) * 100, 2)   AS stickiness_pct
FROM dau_monthly d
JOIN mau_monthly m ON d.month = m.month
ORDER BY d.month;

-- ────────────────────────────────────────────────────────────
-- KPI 6: MoM GROWTH % (Month-over-Month)
-- Applied to: GMV, Net Revenue, MAU
-- ────────────────────────────────────────────────────────────

-- MoM Growth for GMV and Revenue
WITH monthly AS (
    SELECT
        strftime('%Y-%m', txn_date)                                   AS month,
        ROUND(SUM(amount), 2)                                         AS gmv,
        ROUND(SUM((mdr_pct / 100.0) * amount
                  - cashback_amt - processing_fee_amt), 2)            AS net_revenue,
        COUNT(DISTINCT customer_id)                                   AS mau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY strftime('%Y-%m', txn_date)
),
with_prev AS (
    SELECT
        month,
        gmv,
        net_revenue,
        mau,
        LAG(gmv)         OVER (ORDER BY month)        AS prev_gmv,
        LAG(net_revenue) OVER (ORDER BY month)        AS prev_revenue,
        LAG(mau)         OVER (ORDER BY month)        AS prev_mau
    FROM monthly
)
SELECT
    month,
    gmv,
    net_revenue,
    mau,
    ROUND(
        (gmv - prev_gmv) / NULLIF(prev_gmv, 0) * 100
    , 2)    AS gmv_mom_growth_pct,
    ROUND(
        (net_revenue - prev_revenue) / NULLIF(prev_revenue, 0) * 100
    , 2)    AS revenue_mom_growth_pct,
    ROUND(
        (mau - prev_mau) / NULLIF(prev_mau, 0) * 100
    , 2)    AS mau_mom_growth_pct
FROM with_prev
ORDER BY month;

-- ────────────────────────────────────────────────────────────
-- KPI 7: SUCCESS RATE & FAILURE ANALYSIS
-- ────────────────────────────────────────────────────────────

-- Overall success rate
SELECT
    status,
    COUNT(*)                                            AS txn_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_share
FROM fact_transactions
GROUP BY status
ORDER BY txn_count DESC;

-- Monthly success rate trend
SELECT
    strftime('%Y-%m', txn_date)   AS month,
    COUNT(*)                       AS total_txns,
    SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END)    AS successful,
    ROUND(
        100.0 * SUM(CASE WHEN status = 'SUCCESS' THEN 1 ELSE 0 END) / COUNT(*)
    , 2)                           AS success_rate_pct
FROM fact_transactions
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- Retry analysis — does more retries reduce success?
SELECT
    retry_count,
    COUNT(*)                                                          AS txn_count,
    ROUND(100.0 * SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END)
          / COUNT(*), 2)                                              AS success_rate_pct,
    ROUND(AVG(processing_fee_amt), 4)                                 AS avg_processing_fee
FROM fact_transactions
GROUP BY retry_count
ORDER BY retry_count;

-- ────────────────────────────────────────────────────────────
-- KPI 8: PROCESSING COST PER TRANSACTION
-- ────────────────────────────────────────────────────────────

SELECT
    ROUND(AVG(processing_fee_amt), 4)       AS avg_processing_cost,
    ROUND(MIN(processing_fee_amt), 4)       AS min_cost,
    ROUND(MAX(processing_fee_amt), 4)       AS max_cost,
    ROUND(SUM(processing_fee_amt), 2)       AS total_processing_cost,
    COUNT(*)                                AS txn_count
FROM fact_transactions
WHERE status = 'SUCCESS';
