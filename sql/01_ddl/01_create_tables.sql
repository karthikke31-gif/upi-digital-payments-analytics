-- ============================================================
-- UPI TRANSACTION ANALYTICS PROJECT
-- FILE: 01_create_tables.sql
-- PURPOSE: Create star schema tables for UPI analytics
-- Author: UPI Analytics Project
-- ============================================================

-- ─────────────────────────────────────────
-- DIMENSION TABLES
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id    INTEGER PRIMARY KEY,
    channel_name  VARCHAR(50) NOT NULL  -- UPI / CARD / WALLET / NETBANKING
);

CREATE TABLE IF NOT EXISTS dim_city (
    city_id    INTEGER PRIMARY KEY,
    city_name  VARCHAR(100),
    state      VARCHAR(100),
    tier       VARCHAR(20)   -- Tier-1 / Tier-2 / Tier-3
);

CREATE TABLE IF NOT EXISTS dim_merchant (
    merchant_id    INTEGER PRIMARY KEY,
    merchant_name  VARCHAR(200),
    category       VARCHAR(100),  -- Food / Retail / Travel / Transport / Entertainment / Utilities
    city_id        INTEGER REFERENCES dim_city(city_id)
);

CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id    INTEGER PRIMARY KEY,
    signup_date    DATE,
    first_txn_date DATE,
    city_id        INTEGER REFERENCES dim_city(city_id),
    segment_tag    VARCHAR(5)    -- A / B / C / D customer value segments
);

CREATE TABLE IF NOT EXISTS dim_date (
    date          DATE PRIMARY KEY,
    year          INTEGER,
    month         INTEGER,
    day           INTEGER,
    week_of_year  INTEGER,
    is_weekend    BOOLEAN,
    holiday_flag  BOOLEAN
);

-- ─────────────────────────────────────────
-- FACT TABLE (Core transactional table)
-- ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS fact_transactions (
    transaction_id      BIGINT PRIMARY KEY,
    txn_ts              TIMESTAMP,           -- Exact event timestamp
    txn_date            DATE,                -- Partition/join key
    customer_id         INTEGER REFERENCES dim_customer(customer_id),
    merchant_id         INTEGER REFERENCES dim_merchant(merchant_id),
    channel_id          INTEGER REFERENCES dim_channel(channel_id),
    amount              NUMERIC(14, 2),      -- Transaction gross value (GMV component)
    mdr_pct             NUMERIC(6, 4),       -- Merchant Discount Rate %
    cashback_amt        NUMERIC(10, 2),      -- Cashback given to customer
    processing_fee_amt  NUMERIC(10, 2),      -- Fee paid to PSP / bank network
    status              VARCHAR(20),         -- SUCCESS / FAILED / PENDING
    retry_count         INTEGER DEFAULT 0,
    settlement_date     DATE,
    refunded_amt        NUMERIC(10, 2) DEFAULT 0,
    device_os           VARCHAR(50),         -- Android / iOS / Other
    city_id             INTEGER REFERENCES dim_city(city_id),
    acquirer_id         INTEGER
);

-- ─────────────────────────────────────────
-- INDEXES FOR PERFORMANCE
-- ─────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_ft_txn_date         ON fact_transactions(txn_date);
CREATE INDEX IF NOT EXISTS idx_ft_customer_date    ON fact_transactions(customer_id, txn_date);
CREATE INDEX IF NOT EXISTS idx_ft_channel_date     ON fact_transactions(channel_id, txn_date);
CREATE INDEX IF NOT EXISTS idx_ft_status           ON fact_transactions(status);
CREATE INDEX IF NOT EXISTS idx_ft_merchant         ON fact_transactions(merchant_id);
CREATE INDEX IF NOT EXISTS idx_ft_city             ON fact_transactions(city_id);
CREATE INDEX IF NOT EXISTS idx_ft_acquirer         ON fact_transactions(acquirer_id);
