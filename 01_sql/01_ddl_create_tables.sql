-- ============================================================
-- UPI Transaction Analytics Project
-- Script 01: DDL - Create All Tables (Star Schema)
-- Author  : UPI Analytics Project
-- DB      : PostgreSQL / SQLite compatible
-- ============================================================

-- -------------------------------------------------------
-- DIMENSION TABLES
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS dim_date (
    date           DATE        PRIMARY KEY,
    year           INT         NOT NULL,
    month          INT         NOT NULL,
    day            INT         NOT NULL,
    week_of_year   INT,
    is_weekend     BOOLEAN     DEFAULT FALSE,
    holiday_flag   BOOLEAN     DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id     INT         PRIMARY KEY,
    channel_name   VARCHAR(50) NOT NULL   -- UPI, CARD, WALLET, NB
);

CREATE TABLE IF NOT EXISTS dim_city (
    city_id        INT         PRIMARY KEY,
    city_name      VARCHAR(100),
    state          VARCHAR(100),
    tier           VARCHAR(20)            -- Tier-1, Tier-2, Tier-3
);

CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id     INT         PRIMARY KEY,
    signup_date     DATE,
    first_txn_date  DATE,
    city_id         INT         REFERENCES dim_city(city_id),
    segment_tag     VARCHAR(10)            -- A, B, C etc.
);

CREATE TABLE IF NOT EXISTS dim_merchant (
    merchant_id    INT         PRIMARY KEY,
    category       VARCHAR(100),
    merchant_name  VARCHAR(200),
    city_id        INT         REFERENCES dim_city(city_id)
);

-- -------------------------------------------------------
-- FACT TABLE  (50,000 rows — one row per transaction)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS fact_transactions (
    transaction_id      BIGINT      PRIMARY KEY,
    txn_ts              TIMESTAMP   NOT NULL,
    txn_date            DATE        NOT NULL REFERENCES dim_date(date),
    customer_id         INT         NOT NULL REFERENCES dim_customer(customer_id),
    merchant_id         INT         NOT NULL REFERENCES dim_merchant(merchant_id),
    channel_id          INT         NOT NULL REFERENCES dim_channel(channel_id),
    amount              NUMERIC(12,2) NOT NULL,          -- gross transaction value (INR)
    mdr_pct             NUMERIC(6,4) NOT NULL,            -- merchant discount rate %
    cashback_amt        NUMERIC(10,2) DEFAULT 0,
    processing_fee_amt  NUMERIC(10,2) DEFAULT 0,
    status              VARCHAR(20) NOT NULL,             -- SUCCESS / FAILED / PENDING
    retry_count         INT          DEFAULT 0,
    settlement_date     DATE,
    refunded_amt        NUMERIC(10,2) DEFAULT 0,
    device_os           VARCHAR(50),                      -- Android / iOS / Other
    city_id             INT         REFERENCES dim_city(city_id),
    acquirer_id         INT
);

-- -------------------------------------------------------
-- INDEXES  (critical for performance on large datasets)
-- -------------------------------------------------------

-- Most queries filter by date + status
CREATE INDEX IF NOT EXISTS idx_fact_txn_date   ON fact_transactions(txn_date);
CREATE INDEX IF NOT EXISTS idx_fact_status      ON fact_transactions(status);
CREATE INDEX IF NOT EXISTS idx_fact_customer    ON fact_transactions(customer_id, txn_date);
CREATE INDEX IF NOT EXISTS idx_fact_channel     ON fact_transactions(channel_id);
CREATE INDEX IF NOT EXISTS idx_fact_city        ON fact_transactions(city_id);

-- -------------------------------------------------------
-- PRE-AGGREGATED DAILY ROLLUP  (speeds up dashboard queries)
-- -------------------------------------------------------

CREATE TABLE IF NOT EXISTS daily_rollup AS
SELECT
    txn_date,
    channel_id,
    city_id,
    COUNT(*)                                                        AS txn_count,
    COUNT(CASE WHEN status = 'SUCCESS' THEN 1 END)                 AS success_count,
    SUM(CASE WHEN status = 'SUCCESS' THEN amount ELSE 0 END)       AS gmv,
    SUM(CASE WHEN status = 'SUCCESS' THEN
        (mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt
        ELSE 0 END)                                                AS net_revenue,
    SUM(CASE WHEN status = 'SUCCESS' THEN cashback_amt ELSE 0 END) AS total_cashback,
    SUM(CASE WHEN status = 'SUCCESS' THEN processing_fee_amt ELSE 0 END) AS total_processing_cost,
    COUNT(DISTINCT customer_id)                                    AS unique_customers
FROM fact_transactions
GROUP BY txn_date, channel_id, city_id;

-- ============================================================
-- END OF SCRIPT 01
-- ============================================================
