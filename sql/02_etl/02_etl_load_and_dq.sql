-- ============================================================
-- UPI TRANSACTION ANALYTICS PROJECT
-- FILE: 02_etl_load_and_dq.sql
-- PURPOSE: Load CSVs into tables + full data quality checks
-- ============================================================

-- ─────────────────────────────────────────
-- SECTION 1: LOAD DATA FROM CSV (PostgreSQL COPY syntax)
-- Run these from psql or your SQL client with \COPY
-- ─────────────────────────────────────────

-- Load dimension tables first (no foreign key deps)
COPY dim_channel(channel_id, channel_name)
FROM '/path/to/data/dim_channel.csv'
CSV HEADER;

COPY dim_city(city_id, city_name, state, tier)
FROM '/path/to/data/dim_city.csv'
CSV HEADER;

COPY dim_merchant(merchant_id, category, merchant_name, city_id)
FROM '/path/to/data/dim_merchant.csv'
CSV HEADER;

COPY dim_customer(customer_id, signup_date, first_txn_date, city_id, segment_tag)
FROM '/path/to/data/dim_customer.csv'
CSV HEADER;

COPY dim_date(date, year, month, day, week_of_year, is_weekend, holiday_flag)
FROM '/path/to/data/dim_date.csv'
CSV HEADER;

-- Load fact table last (after all dims exist)
COPY fact_transactions(
    transaction_id, txn_ts, txn_date, customer_id, merchant_id, channel_id,
    amount, mdr_pct, cashback_amt, processing_fee_amt, status, retry_count,
    settlement_date, refunded_amt, device_os, city_id, acquirer_id
)
FROM '/path/to/data/fact_transactions.csv'
CSV HEADER;


-- ─────────────────────────────────────────
-- SECTION 2: DATA QUALITY CHECKS
-- Run each block and verify 0 issues before proceeding
-- ─────────────────────────────────────────

-- DQ-01: Row counts — verify all data loaded
SELECT 'fact_transactions' AS table_name, COUNT(*) AS row_count FROM fact_transactions
UNION ALL
SELECT 'dim_customer',  COUNT(*) FROM dim_customer
UNION ALL
SELECT 'dim_merchant',  COUNT(*) FROM dim_merchant
UNION ALL
SELECT 'dim_channel',   COUNT(*) FROM dim_channel
UNION ALL
SELECT 'dim_city',      COUNT(*) FROM dim_city
UNION ALL
SELECT 'dim_date',      COUNT(*) FROM dim_date;

-- DQ-02: Duplicate transaction IDs (must return 0)
SELECT COUNT(*) - COUNT(DISTINCT transaction_id) AS duplicate_txn_ids
FROM fact_transactions;

-- DQ-03: Negative or zero amounts (flag anomalies)
SELECT COUNT(*) AS negative_or_zero_amount
FROM fact_transactions
WHERE amount <= 0;

-- DQ-04: NULL values in critical columns
SELECT
    SUM(CASE WHEN transaction_id   IS NULL THEN 1 ELSE 0 END) AS null_txn_id,
    SUM(CASE WHEN customer_id      IS NULL THEN 1 ELSE 0 END) AS null_customer,
    SUM(CASE WHEN amount           IS NULL THEN 1 ELSE 0 END) AS null_amount,
    SUM(CASE WHEN status           IS NULL THEN 1 ELSE 0 END) AS null_status,
    SUM(CASE WHEN txn_date         IS NULL THEN 1 ELSE 0 END) AS null_txn_date
FROM fact_transactions;

-- DQ-05: Invalid status values (must only be SUCCESS/FAILED/PENDING)
SELECT status, COUNT(*) AS cnt
FROM fact_transactions
GROUP BY status
ORDER BY cnt DESC;

-- DQ-06: Orphan transactions — customers not in dim_customer
SELECT COUNT(*) AS orphan_customers
FROM fact_transactions f
LEFT JOIN dim_customer c ON f.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- DQ-07: Orphan transactions — merchants not in dim_merchant
SELECT COUNT(*) AS orphan_merchants
FROM fact_transactions f
LEFT JOIN dim_merchant m ON f.merchant_id = m.merchant_id
WHERE m.merchant_id IS NULL;

-- DQ-08: Channel IDs not in dim_channel
SELECT COUNT(*) AS orphan_channels
FROM fact_transactions f
LEFT JOIN dim_channel ch ON f.channel_id = ch.channel_id
WHERE ch.channel_id IS NULL;

-- DQ-09: Date range validation
SELECT
    MIN(txn_date)  AS earliest_txn,
    MAX(txn_date)  AS latest_txn,
    COUNT(DISTINCT txn_date) AS distinct_dates
FROM fact_transactions;

-- DQ-10: MDR % sanity (should be between 0 and 5% for UPI/payments)
SELECT
    MIN(mdr_pct) AS min_mdr,
    MAX(mdr_pct) AS max_mdr,
    AVG(mdr_pct) AS avg_mdr,
    COUNT(*) FILTER (WHERE mdr_pct < 0 OR mdr_pct > 5) AS out_of_range
FROM fact_transactions;

-- DQ-11: Cashback > transaction amount (invalid)
SELECT COUNT(*) AS cashback_exceeds_amount
FROM fact_transactions
WHERE cashback_amt > amount;

-- DQ-12: Processing fee anomaly (fee > 10% of amount)
SELECT COUNT(*) AS high_processing_fee
FROM fact_transactions
WHERE processing_fee_amt > (amount * 0.10);

-- DQ-13: Settlement date before transaction date (data error)
SELECT COUNT(*) AS settlement_before_txn
FROM fact_transactions
WHERE settlement_date < txn_date;

-- DQ-14: Daily GMV sanity check (spot large spikes)
SELECT txn_date,
       COUNT(*)           AS txn_count,
       ROUND(SUM(amount)::NUMERIC, 2) AS daily_gmv
FROM fact_transactions
WHERE status = 'SUCCESS'
GROUP BY txn_date
ORDER BY daily_gmv DESC
LIMIT 10;

-- DQ-15: Summary health report
SELECT
    COUNT(*)                                                        AS total_txns,
    COUNT(*) FILTER (WHERE status = 'SUCCESS')                      AS success_txns,
    COUNT(*) FILTER (WHERE status = 'FAILED')                       AS failed_txns,
    COUNT(*) FILTER (WHERE status = 'PENDING')                      AS pending_txns,
    ROUND(100.0 * COUNT(*) FILTER (WHERE status='SUCCESS') / COUNT(*), 2) AS success_rate_pct,
    ROUND(SUM(amount) FILTER (WHERE status='SUCCESS')::NUMERIC, 2)  AS total_gmv,
    ROUND(AVG(amount) FILTER (WHERE status='SUCCESS')::NUMERIC, 2)  AS avg_txn_value,
    COUNT(DISTINCT customer_id)                                     AS unique_customers
FROM fact_transactions;
