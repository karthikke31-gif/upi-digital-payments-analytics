-- ============================================================
-- FILE: 07_cashback_roi_whatif.sql
-- PURPOSE: Cashback ROI, Processing Cost Analysis, What-If Scenarios
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- SECTION 1: CASHBACK ROI ANALYSIS
-- ────────────────────────────────────────────────────────────

-- 1a. Overall cashback spend vs GMV generated
SELECT
    ROUND(SUM(amount), 2)                               AS total_gmv,
    ROUND(SUM(cashback_amt), 2)                         AS total_cashback,
    ROUND(SUM(amount) / NULLIF(SUM(cashback_amt), 0), 2) AS gmv_per_cashback_rupee,
    ROUND(SUM(cashback_amt) / NULLIF(SUM(amount), 0) * 100, 4) AS cashback_rate_pct,
    COUNT(CASE WHEN cashback_amt > 0 THEN 1 END)        AS txns_with_cashback,
    COUNT(CASE WHEN cashback_amt = 0 THEN 1 END)        AS txns_without_cashback,
    ROUND(100.0 * COUNT(CASE WHEN cashback_amt > 0 THEN 1 END) / COUNT(*), 2) AS cashback_coverage_pct
FROM fact_transactions
WHERE status = 'SUCCESS';

-- 1b. Cashback users vs non-cashback users: transaction behavior
SELECT
    CASE WHEN cashback_amt > 0 THEN 'Cashback' ELSE 'No Cashback' END AS user_type,
    COUNT(DISTINCT customer_id)                         AS unique_customers,
    COUNT(*)                                            AS total_txns,
    ROUND(AVG(amount), 2)                               AS avg_txn_value,
    ROUND(SUM(amount) / COUNT(DISTINCT customer_id), 2) AS gmv_per_customer,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT customer_id), 2) AS txns_per_customer
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY CASE WHEN cashback_amt > 0 THEN 'Cashback' ELSE 'No Cashback' END;

-- 1c. Monthly cashback cost and ROI trend
SELECT
    strftime('%Y-%m', txn_date)                         AS month,
    ROUND(SUM(amount), 2)                               AS gmv,
    ROUND(SUM(cashback_amt), 2)                         AS cashback_cost,
    ROUND(SUM(processing_fee_amt), 2)                   AS processing_cost,
    ROUND(SUM((mdr_pct/100.0)*amount), 2)               AS mdr_income,
    ROUND(SUM((mdr_pct/100.0)*amount
              - cashback_amt - processing_fee_amt), 2)  AS net_revenue,
    ROUND(SUM(amount) / NULLIF(SUM(cashback_amt), 0), 2) AS gmv_per_cashback_rupee
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY strftime('%Y-%m', txn_date)
ORDER BY month;

-- 1d. Cashback ROI by channel
SELECT
    ch.channel_name,
    ROUND(SUM(f.amount), 2)                             AS gmv,
    ROUND(SUM(f.cashback_amt), 2)                       AS cashback_spent,
    ROUND(SUM(f.cashback_amt) / NULLIF(SUM(f.amount),0)*100, 4) AS cashback_rate_pct,
    ROUND(SUM(f.amount) / NULLIF(SUM(f.cashback_amt),0), 2)     AS gmv_per_cashback_rupee,
    ROUND(SUM((f.mdr_pct/100.0)*f.amount
              - f.cashback_amt - f.processing_fee_amt), 2)       AS net_revenue
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY net_revenue DESC;

-- ────────────────────────────────────────────────────────────
-- SECTION 2: PROCESSING COST ANALYSIS
-- ────────────────────────────────────────────────────────────

-- 2a. Processing cost breakdown
SELECT
    ROUND(AVG(processing_fee_amt), 4)       AS avg_processing_fee,
    ROUND(MIN(processing_fee_amt), 4)       AS min_fee,
    ROUND(MAX(processing_fee_amt), 4)       AS max_fee,
    ROUND(SUM(processing_fee_amt), 2)       AS total_processing_cost,
    ROUND(SUM(processing_fee_amt) / NULLIF(SUM(amount), 0) * 100, 4) AS processing_cost_pct_gmv
FROM fact_transactions
WHERE status = 'SUCCESS';

-- 2b. Processing cost by channel
SELECT
    ch.channel_name,
    ROUND(AVG(f.processing_fee_amt), 4)     AS avg_fee_per_txn,
    ROUND(SUM(f.processing_fee_amt), 2)     AS total_cost,
    ROUND(SUM(f.processing_fee_amt) / NULLIF(SUM(f.amount), 0) * 100, 4) AS cost_pct_gmv
FROM fact_transactions f
JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE f.status = 'SUCCESS'
GROUP BY ch.channel_name
ORDER BY avg_fee_per_txn ASC;

-- 2c. Processing cost by acquirer
SELECT
    acquirer_id,
    COUNT(*)                                AS txn_count,
    ROUND(AVG(processing_fee_amt), 4)       AS avg_fee,
    ROUND(SUM(processing_fee_amt), 2)       AS total_cost,
    ROUND(SUM(amount), 2)                   AS gmv,
    ROUND(100.0 * SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END) / COUNT(*), 2) AS success_rate
FROM fact_transactions
GROUP BY acquirer_id
ORDER BY avg_fee ASC;

-- ────────────────────────────────────────────────────────────
-- SECTION 3: WHAT-IF ANALYSIS SCENARIOS
-- Simulate impact of changing MDR, cashback, and processing fees
-- ────────────────────────────────────────────────────────────

-- SCENARIO BASE: Current state
SELECT
    'BASE (Current)'                        AS scenario,
    ROUND(SUM(amount), 2)                   AS gmv,
    ROUND(SUM((mdr_pct/100.0)*amount), 2)   AS mdr_income,
    ROUND(SUM(cashback_amt), 2)             AS cashback_cost,
    ROUND(SUM(processing_fee_amt), 2)       AS processing_cost,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount),0)*100, 4)   AS margin_pct
FROM fact_transactions
WHERE status = 'SUCCESS'

UNION ALL

-- SCENARIO 1: MDR increases by +0.5%
SELECT
    'Scenario 1: MDR +0.5%',
    ROUND(SUM(amount), 2),
    ROUND(SUM(((mdr_pct + 0.5)/100.0)*amount), 2),
    ROUND(SUM(cashback_amt), 2),
    ROUND(SUM(processing_fee_amt), 2),
    ROUND(SUM(((mdr_pct+0.5)/100.0)*amount - cashback_amt - processing_fee_amt), 2),
    ROUND(SUM(((mdr_pct+0.5)/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount),0)*100, 4)
FROM fact_transactions WHERE status='SUCCESS'

UNION ALL

-- SCENARIO 2: MDR decreases by -0.5% (competitive pressure)
SELECT
    'Scenario 2: MDR -0.5%',
    ROUND(SUM(amount), 2),
    ROUND(SUM(((mdr_pct - 0.5)/100.0)*amount), 2),
    ROUND(SUM(cashback_amt), 2),
    ROUND(SUM(processing_fee_amt), 2),
    ROUND(SUM(((mdr_pct-0.5)/100.0)*amount - cashback_amt - processing_fee_amt), 2),
    ROUND(SUM(((mdr_pct-0.5)/100.0)*amount - cashback_amt - processing_fee_amt)
          / NULLIF(SUM(amount),0)*100, 4)
FROM fact_transactions WHERE status='SUCCESS'

UNION ALL

-- SCENARIO 3: Cashback reduced by 25%
SELECT
    'Scenario 3: Cashback -25%',
    ROUND(SUM(amount), 2),
    ROUND(SUM((mdr_pct/100.0)*amount), 2),
    ROUND(SUM(cashback_amt * 0.75), 2),
    ROUND(SUM(processing_fee_amt), 2),
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.75 - processing_fee_amt), 2),
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.75 - processing_fee_amt)
          / NULLIF(SUM(amount),0)*100, 4)
FROM fact_transactions WHERE status='SUCCESS'

UNION ALL

-- SCENARIO 4: Cashback reduced by 50%
SELECT
    'Scenario 4: Cashback -50%',
    ROUND(SUM(amount), 2),
    ROUND(SUM((mdr_pct/100.0)*amount), 2),
    ROUND(SUM(cashback_amt * 0.50), 2),
    ROUND(SUM(processing_fee_amt), 2),
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.50 - processing_fee_amt), 2),
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.50 - processing_fee_amt)
          / NULLIF(SUM(amount),0)*100, 4)
FROM fact_transactions WHERE status='SUCCESS'

UNION ALL

-- SCENARIO 5: Processing fee reduced by 10% (better bank deal)
SELECT
    'Scenario 5: Processing Fee -10%',
    ROUND(SUM(amount), 2),
    ROUND(SUM((mdr_pct/100.0)*amount), 2),
    ROUND(SUM(cashback_amt), 2),
    ROUND(SUM(processing_fee_amt * 0.90), 2),
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt*0.90), 2),
    ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt*0.90)
          / NULLIF(SUM(amount),0)*100, 4)
FROM fact_transactions WHERE status='SUCCESS'

UNION ALL

-- SCENARIO 6: Combined — MDR +0.3%, Cashback -20%, Processing -5%
SELECT
    'Scenario 6: Optimized (MDR+0.3, CB-20%, PF-5%)',
    ROUND(SUM(amount), 2),
    ROUND(SUM(((mdr_pct+0.3)/100.0)*amount), 2),
    ROUND(SUM(cashback_amt * 0.80), 2),
    ROUND(SUM(processing_fee_amt * 0.95), 2),
    ROUND(SUM(((mdr_pct+0.3)/100.0)*amount - cashback_amt*0.80 - processing_fee_amt*0.95), 2),
    ROUND(SUM(((mdr_pct+0.3)/100.0)*amount - cashback_amt*0.80 - processing_fee_amt*0.95)
          / NULLIF(SUM(amount),0)*100, 4)
FROM fact_transactions WHERE status='SUCCESS';

-- ────────────────────────────────────────────────────────────
-- SECTION 4: CASHBACK SEGMENT COMPARISON (Before/After proxy)
-- Compare users who got cashback vs did not — spending patterns
-- ────────────────────────────────────────────────────────────

WITH customer_cashback AS (
    SELECT
        customer_id,
        SUM(cashback_amt)   AS total_cashback_received,
        SUM(amount)         AS total_spend,
        COUNT(*)            AS total_txns,
        CASE WHEN SUM(cashback_amt) > 0 THEN 'Received Cashback'
             ELSE 'No Cashback' END AS cashback_group
    FROM fact_transactions
    WHERE status = 'SUCCESS'
    GROUP BY customer_id
)
SELECT
    cashback_group,
    COUNT(*)                                    AS customer_count,
    ROUND(AVG(total_spend), 2)                  AS avg_spend_per_customer,
    ROUND(AVG(total_txns), 2)                   AS avg_txns_per_customer,
    ROUND(AVG(total_cashback_received), 4)      AS avg_cashback_received,
    ROUND(SUM(total_spend) / COUNT(*), 2)       AS gmv_per_customer
FROM customer_cashback
GROUP BY cashback_group;
