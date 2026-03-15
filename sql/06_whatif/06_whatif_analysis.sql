-- ============================================================
-- UPI TRANSACTION ANALYTICS PROJECT
-- FILE: 06_whatif_analysis.sql
-- PURPOSE: Scenario-based What-If analysis using SQL
--          No ML — pure arithmetic simulations
-- ============================================================


-- ─────────────────────────────────────────
-- WHATIF-01: MDR INCREASE SCENARIO (+0.5%)
-- Question: If we raise MDR by 0.5%, how does revenue change?
-- Assumption: GMV stays the same (no demand elasticity applied)
-- ─────────────────────────────────────────

WITH base AS (
    SELECT
        SUM(amount)                                                          AS gmv,
        SUM((mdr_pct/100.0)*amount)                                          AS current_mdr_revenue,
        SUM(cashback_amt)                                                    AS cashback_cost,
        SUM(processing_fee_amt)                                              AS processing_cost,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)      AS current_net_revenue
    FROM fact_transactions
    WHERE status = 'SUCCESS'
)
SELECT
    ROUND(gmv::NUMERIC, 2)                                                   AS gmv,
    ROUND(current_net_revenue::NUMERIC, 2)                                   AS current_net_revenue,
    ROUND((current_net_revenue + gmv * 0.005)::NUMERIC, 2)                   AS projected_revenue_mdr_plus_05pct,
    ROUND(gmv * 0.005::NUMERIC, 2)                                           AS incremental_revenue,
    ROUND(current_net_revenue / gmv * 100::NUMERIC, 4)                       AS current_margin_pct,
    ROUND((current_net_revenue + gmv * 0.005) / gmv * 100::NUMERIC, 4)       AS new_margin_pct
FROM base;


-- ─────────────────────────────────────────
-- WHATIF-02: CASHBACK REDUCTION SCENARIOS
-- Question: What if we reduce cashback by 10%, 20%, 30%?
-- This directly improves net revenue
-- ─────────────────────────────────────────

WITH base AS (
    SELECT
        SUM(amount)                                                          AS gmv,
        SUM(cashback_amt)                                                    AS total_cashback,
        SUM(processing_fee_amt)                                              AS total_processing_cost,
        SUM((mdr_pct/100.0)*amount)                                          AS gross_mdr_revenue,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)      AS current_net_revenue
    FROM fact_transactions
    WHERE status = 'SUCCESS'
)
SELECT
    reduction_pct,
    ROUND(gmv::NUMERIC, 2)                                                   AS gmv,
    ROUND(total_cashback::NUMERIC, 2)                                        AS current_cashback,
    ROUND((total_cashback * (1 - reduction_pct/100.0))::NUMERIC, 2)          AS new_cashback,
    ROUND(current_net_revenue::NUMERIC, 2)                                   AS current_net_revenue,
    ROUND((gross_mdr_revenue - total_cashback*(1-reduction_pct/100.0)
           - total_processing_cost)::NUMERIC, 2)                             AS new_net_revenue,
    ROUND(
        (gross_mdr_revenue - total_cashback*(1-reduction_pct/100.0) - total_processing_cost)
        / gmv * 100::NUMERIC, 4)                                             AS new_margin_pct,
    ROUND(
        (gross_mdr_revenue - total_cashback*(1-reduction_pct/100.0) - total_processing_cost)
        - current_net_revenue::NUMERIC, 2)                                   AS revenue_uplift
FROM base,
LATERAL (
    VALUES (0), (10), (20), (30), (40), (50)
) AS t(reduction_pct)
ORDER BY reduction_pct;


-- ─────────────────────────────────────────
-- WHATIF-03: USER GROWTH SCENARIO
-- Question: If MAU grows 10%/20%/30% with same avg revenue/user,
--           what is the projected revenue?
-- ─────────────────────────────────────────

WITH current_metrics AS (
    SELECT
        COUNT(DISTINCT customer_id)                                          AS current_mau,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)      AS current_net_revenue
    FROM fact_transactions
    WHERE status = 'SUCCESS'
      AND DATE_TRUNC('month', txn_date) = (
          SELECT DATE_TRUNC('month', MAX(txn_date)) FROM fact_transactions WHERE status='SUCCESS'
      )
),
avg_revenue_per_user AS (
    SELECT current_net_revenue / NULLIF(current_mau, 0) AS arpu
    FROM current_metrics
)
SELECT
    growth_pct,
    c.current_mau,
    ROUND(c.current_mau * (1 + growth_pct/100.0))                           AS projected_mau,
    ROUND(c.current_net_revenue::NUMERIC, 2)                                 AS current_revenue,
    ROUND((c.current_mau * (1 + growth_pct/100.0) * a.arpu)::NUMERIC, 2)    AS projected_revenue,
    ROUND(((c.current_mau * (1 + growth_pct/100.0) * a.arpu) - c.current_net_revenue)
          ::NUMERIC, 2)                                                      AS incremental_revenue
FROM current_metrics c, avg_revenue_per_user a,
LATERAL (VALUES (0), (10), (20), (30), (50)) AS t(growth_pct)
ORDER BY growth_pct;


-- ─────────────────────────────────────────
-- WHATIF-04: COMBINED SCENARIO — MDR UP + CASHBACK DOWN
-- Most realistic business lever: raise MDR 0.5% AND cut cashback 20%
-- ─────────────────────────────────────────

WITH base AS (
    SELECT
        SUM(amount)                                                          AS gmv,
        SUM(cashback_amt)                                                    AS total_cashback,
        SUM(processing_fee_amt)                                              AS total_processing,
        SUM((mdr_pct/100.0)*amount)                                          AS gross_mdr_revenue,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)      AS current_net_revenue
    FROM fact_transactions
    WHERE status = 'SUCCESS'
)
SELECT
    ROUND(gmv::NUMERIC, 2)                                                   AS gmv,
    ROUND(current_net_revenue::NUMERIC, 2)                                   AS current_net_revenue,
    ROUND(current_net_revenue / gmv * 100::NUMERIC, 4)                       AS current_margin_pct,
    -- Scenario: MDR +0.5%, Cashback -20%
    ROUND(
        (gross_mdr_revenue + gmv*0.005)
        - total_cashback*0.80
        - total_processing
    ::NUMERIC, 2)                                                            AS scenario_net_revenue,
    ROUND(
        ((gross_mdr_revenue + gmv*0.005) - total_cashback*0.80 - total_processing)
        / gmv * 100
    ::NUMERIC, 4)                                                            AS scenario_margin_pct,
    ROUND(
        ((gross_mdr_revenue + gmv*0.005) - total_cashback*0.80 - total_processing)
        - current_net_revenue
    ::NUMERIC, 2)                                                            AS revenue_uplift
FROM base;


-- ─────────────────────────────────────────
-- WHATIF-05: CHANNEL SHIFT SCENARIO
-- Question: What if 10% of CARD transactions moved to UPI?
-- (UPI is cheaper to process — lower processing fee)
-- ─────────────────────────────────────────

WITH channel_metrics AS (
    SELECT
        ch.channel_name,
        COUNT(*)                                                             AS txn_count,
        SUM(f.amount)                                                        AS gmv,
        AVG(f.processing_fee_amt)                                            AS avg_proc_fee,
        AVG(f.mdr_pct)                                                       AS avg_mdr_pct,
        AVG(f.cashback_amt)                                                  AS avg_cashback,
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
                                                                             AS net_revenue
    FROM fact_transactions f
    JOIN dim_channel ch ON f.channel_id = ch.channel_id
    WHERE f.status = 'SUCCESS'
    GROUP BY ch.channel_name
),
card_metrics AS (SELECT * FROM channel_metrics WHERE channel_name = 'CARD'),
upi_metrics  AS (SELECT * FROM channel_metrics WHERE channel_name = 'UPI')
SELECT
    'Current State'                                                          AS scenario,
    c.gmv                                                                    AS card_gmv,
    u.gmv                                                                    AS upi_gmv,
    c.net_revenue + u.net_revenue                                            AS combined_net_revenue
FROM card_metrics c, upi_metrics u

UNION ALL

SELECT
    '10% Card -> UPI Shift',
    c.gmv * 0.90,
    u.gmv + c.gmv * 0.10,
    -- Card revenue at 90% + UPI revenue (existing + shifted, with UPI processing cost)
    (c.net_revenue * 0.90) +
    (u.gmv + c.gmv * 0.10) * (u.avg_mdr_pct/100.0)
    - (u.gmv + c.gmv * 0.10) * u.avg_cashback / u.gmv
    - (u.gmv + c.gmv * 0.10) * u.avg_proc_fee / u.gmv
FROM card_metrics c, upi_metrics u;


-- ─────────────────────────────────────────
-- WHATIF-06: CHURN PREVENTION VALUE
-- Question: If we prevent 20% of high-risk churners from leaving,
--           what revenue do we retain?
-- ─────────────────────────────────────────

WITH last_ref_date AS (
    SELECT MAX(txn_date) AS ref_date FROM fact_transactions WHERE status = 'SUCCESS'
),
customer_activity AS (
    SELECT
        f.customer_id,
        MAX(f.txn_date)                                                      AS last_txn_date,
        COUNT(*) FILTER (
            WHERE f.txn_date >= (SELECT ref_date FROM last_ref_date) - INTERVAL '90 days'
        )                                                                    AS txn_last_90d,
        SUM(f.amount) / 12.0                                                 AS avg_monthly_gmv,
        SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt) / 12.0
                                                                             AS avg_monthly_revenue
    FROM fact_transactions f
    WHERE f.status = 'SUCCESS'
    GROUP BY f.customer_id
),
high_risk_churners AS (
    SELECT *
    FROM customer_activity, last_ref_date
    WHERE (ref_date - last_txn_date) > 60 AND txn_last_90d < 2
)
SELECT
    COUNT(*)                                                                 AS high_risk_count,
    ROUND(SUM(avg_monthly_gmv)::NUMERIC, 2)                                  AS at_risk_monthly_gmv,
    ROUND(SUM(avg_monthly_revenue)::NUMERIC, 2)                              AS at_risk_monthly_revenue,
    -- Scenario: Save 20% of high-risk users via targeted campaign
    ROUND(SUM(avg_monthly_revenue) * 0.20::NUMERIC, 2)                      AS recoverable_revenue_20pct,
    ROUND(SUM(avg_monthly_revenue) * 0.30::NUMERIC, 2)                      AS recoverable_revenue_30pct
FROM high_risk_churners;
