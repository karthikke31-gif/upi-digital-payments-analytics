-- ============================================================
-- UPI Transaction Analytics Project
-- Script 02: ETL - Load CSV Data into Tables
-- ============================================================
-- NOTE: Commands below use PostgreSQL \COPY syntax.
--       For SQLite: use the Python setup script (02_python/00_setup_database.py)
--       For MySQL : LOAD DATA INFILE with appropriate paths.
-- ============================================================

-- -------------------------------------------------------
-- STEP 1: Load Dimension Tables First (no FK violations)
-- -------------------------------------------------------

-- Load dim_date
\COPY dim_date(date, year, month, day, week_of_year, is_weekend, holiday_flag)
FROM 'data/dim_date.csv'
DELIMITER ',' CSV HEADER;

-- Load dim_channel
\COPY dim_channel(channel_id, channel_name)
FROM 'data/dim_channel.csv'
DELIMITER ',' CSV HEADER;

-- Load dim_city
\COPY dim_city(city_id, city_name, state, tier)
FROM 'data/dim_city.csv'
DELIMITER ',' CSV HEADER;

-- Load dim_customer
\COPY dim_customer(customer_id, signup_date, first_txn_date, city_id, segment_tag)
FROM 'data/dim_customer.csv'
DELIMITER ',' CSV HEADER;

-- Load dim_merchant
\COPY dim_merchant(merchant_id, category, merchant_name, city_id)
FROM 'data/dim_merchant.csv'
DELIMITER ',' CSV HEADER;

-- -------------------------------------------------------
-- STEP 2: Load Fact Table
-- -------------------------------------------------------

\COPY fact_transactions(
    transaction_id, txn_ts, txn_date, customer_id, merchant_id, channel_id,
    amount, mdr_pct, cashback_amt, processing_fee_amt, status, retry_count,
    settlement_date, refunded_amt, device_os, city_id, acquirer_id
)
FROM 'data/fact_transactions.csv'
DELIMITER ',' CSV HEADER;

-- -------------------------------------------------------
-- STEP 3: Post-Load Verification
-- -------------------------------------------------------

-- Row count check
SELECT 'fact_transactions' AS tbl, COUNT(*) AS rows FROM fact_transactions
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

-- -------------------------------------------------------
-- STEP 4: Incremental Load Pattern (for future data)
-- -------------------------------------------------------
-- Use this pattern when appending new data monthly:

/*
INSERT INTO fact_transactions
SELECT *
FROM staging_fact_transactions s
WHERE s.txn_date > (SELECT MAX(txn_date) FROM fact_transactions)
  AND NOT EXISTS (
      SELECT 1 FROM fact_transactions f WHERE f.transaction_id = s.transaction_id
  );
*/

-- -------------------------------------------------------
-- STEP 5: Handle Late-Arriving Refunds via UPSERT
-- -------------------------------------------------------
/*
INSERT INTO fact_transactions (transaction_id, refunded_amt, ...)
VALUES (...)
ON CONFLICT (transaction_id)
DO UPDATE SET
    refunded_amt = EXCLUDED.refunded_amt,
    settlement_date = EXCLUDED.settlement_date;
*/

-- ============================================================
-- END OF SCRIPT 02
-- ============================================================
