-- ============================================================
-- UPI Transaction Analytics Project
-- Script 04: Core KPIs — GMV, Net Revenue, Margin, MAU, MoM
-- ============================================================

-- -------------------------------------------------------
-- KPI 1: Total GMV (Gross Merchandise Value)
-- -------------------------------------------------------
SELECT
    ROUND(SUM(amount), 2)                          AS total_gmv,
    COUNT(*)                                        AS total_txn_count,
    COUNT(DISTINCT customer_id)                    AS unique_customers,
    ROUND(SUM(amount) / COUNT(*), 2)               AS avg_txn_value
FROM fact_transactions
WHERE status = 'SUCCESS';

-- GMV by Month
SELECT
    STRFTIME('%Y-%m', txn_date)                    AS month,
    ROUND(SUM(amount), 2)                          AS gmv,
    COUNT(*)                                        AS txn_count,
    COUNT(DISTINCT customer_id)                    AS unique_customers
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- KPI 2: Net Revenue
-- Net Revenue = MDR earned - Cashback - Processing Cost
-- MDR earned  = (mdr_pct / 100) * amount
-- -------------------------------------------------------
SELECT
    ROUND(SUM((mdr_pct/100.0) * amount), 2)                               AS gross_mdr_revenue,
    ROUND(SUM(cashback_amt), 2)                                            AS total_cashback,
    ROUND(SUM(processing_fee_amt), 2)                                      AS total_processing_cost,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue
FROM fact_transactions
WHERE status = 'SUCCESS';

-- Net Revenue by Month
SELECT
    STRFTIME('%Y-%m', txn_date)                                            AS month,
    ROUND(SUM(amount), 2)                                                  AS gmv,
    ROUND(SUM((mdr_pct/100.0) * amount), 2)                               AS gross_mdr,
    ROUND(SUM(cashback_amt), 2)                                            AS cashback,
    ROUND(SUM(processing_fee_amt), 2)                                      AS processing_cost,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- KPI 3: Margin %
-- Margin % = Net Revenue / GMV * 100
-- -------------------------------------------------------
SELECT
    ROUND(
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
        / SUM(amount) * 100,
    4) AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS';

-- Margin % by Month
SELECT
    STRFTIME('%Y-%m', txn_date)                                             AS month,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
          / SUM(amount) * 100, 4)                                          AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- KPI 4: MAU — Monthly Active Users
-- Active = at least 1 SUCCESS transaction in the month
-- -------------------------------------------------------
SELECT
    STRFTIME('%Y-%m', txn_date)  AS month,
    COUNT(DISTINCT customer_id)  AS mau
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- KPI 5: Month-over-Month (MoM) Growth % for GMV & Revenue
-- -------------------------------------------------------
WITH monthly AS (
    SELECT
        STRFTIME('%Y-%m', txn_date)                                              AS month,
        SUM(amount)                                                               AS gmv,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)         AS net_revenue,
        COUNT(DISTINCT customer_id)                                              AS mau
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY STRFTIME('%Y-%m', txn_date)
),
with_lag AS (
    SELECT *,
        LAG(gmv)         OVER (ORDER BY month) AS prev_gmv,
        LAG(net_revenue) OVER (ORDER BY month) AS prev_revenue,
        LAG(mau)         OVER (ORDER BY month) AS prev_mau
    FROM monthly
)
SELECT
    month,
    ROUND(gmv, 2)                                                          AS gmv,
    ROUND(net_revenue, 2)                                                  AS net_revenue,
    mau,
    ROUND((gmv - prev_gmv) / NULLIF(prev_gmv, 0) * 100, 2)              AS gmv_mom_pct,
    ROUND((net_revenue - prev_revenue) / NULLIF(prev_revenue, 0)*100, 2) AS rev_mom_pct,
    ROUND((mau - prev_mau) / NULLIF(prev_mau, 0) * 100, 2)             AS mau_mom_pct
FROM with_lag
ORDER BY month;

-- -------------------------------------------------------
-- KPI 6: Transaction Success Rate
-- -------------------------------------------------------
SELECT
    status,
    COUNT(*)                                                       AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)           AS pct
FROM fact_transactions
GROUP BY status;

-- Success rate by Month
SELECT
    STRFTIME('%Y-%m', txn_date)                                    AS month,
    COUNT(*)                                                        AS total_txns,
    SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END)             AS success_txns,
    ROUND(SUM(CASE WHEN status='SUCCESS' THEN 1.0 ELSE 0 END)
          / COUNT(*) * 100, 2)                                     AS success_rate_pct
FROM fact_transactions
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- KPI 7: Average Order Value (AOV)
-- -------------------------------------------------------
SELECT
    STRFTIME('%Y-%m', txn_date)        AS month,
    ROUND(AVG(amount), 2)              AS avg_order_value,
    ROUND(MIN(amount), 2)              AS min_amount,
    ROUND(MAX(amount), 2)              AS max_amount,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount), 2) AS median_amount
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY STRFTIME('%Y-%m', txn_date)
ORDER BY month;

-- -------------------------------------------------------
-- KPI 8: Revenue per User (RPU)
-- -------------------------------------------------------
WITH user_rev AS (
    SELECT customer_id,
           SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS user_net_rev
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    ROUND(AVG(user_net_rev), 4)    AS avg_revenue_per_user,
    ROUND(MIN(user_net_rev), 4)    AS min_rev_per_user,
    ROUND(MAX(user_net_rev), 4)    AS max_rev_per_user
FROM user_rev;

-- ============================================================
-- END OF SCRIPT 04
-- ============================================================
