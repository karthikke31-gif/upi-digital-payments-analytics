-- ============================================================
-- FILE: 01_ddl_create_tables.sql
-- PURPOSE: Create star schema tables for UPI Transaction Analytics
-- ENGINE: SQLite (compatible with PostgreSQL with minor edits)
-- AUTHOR: UPI Analytics Project
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- DIMENSION TABLES
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS dim_customer (
    customer_id     INTEGER PRIMARY KEY,
    signup_date     DATE,
    first_txn_date  DATE,
    city_id         INTEGER,
    segment_tag     TEXT
);

CREATE TABLE IF NOT EXISTS dim_merchant (
    merchant_id     INTEGER PRIMARY KEY,
    category        TEXT,
    merchant_name   TEXT,
    city_id         INTEGER
);

CREATE TABLE IF NOT EXISTS dim_channel (
    channel_id      INTEGER PRIMARY KEY,
    channel_name    TEXT          -- UPI / CARD / WALLET / NETBANKING
);

CREATE TABLE IF NOT EXISTS dim_city (
    city_id         INTEGER PRIMARY KEY,
    city_name       TEXT,
    state           TEXT,
    tier            TEXT          -- Tier-1 / Tier-2 / Tier-3
);

CREATE TABLE IF NOT EXISTS dim_date (
    date            DATE PRIMARY KEY,
    year            INTEGER,
    month           INTEGER,
    day             INTEGER,
    week_of_year    INTEGER,
    is_weekend      TEXT,         -- True / False
    holiday_flag    TEXT          -- True / False
);

-- ────────────────────────────────────────────────────────────
-- FACT TABLE
-- ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS fact_transactions (
    transaction_id      INTEGER PRIMARY KEY,
    txn_ts              DATETIME,
    txn_date            DATE,
    customer_id         INTEGER,
    merchant_id         INTEGER,
    channel_id          INTEGER,
    amount              REAL,
    mdr_pct             REAL,     -- Merchant Discount Rate %
    cashback_amt        REAL,
    processing_fee_amt  REAL,
    status              TEXT,     -- SUCCESS / FAILED / PENDING
    retry_count         INTEGER,
    settlement_date     DATE,
    refunded_amt        REAL,
    device_os           TEXT,     -- Android / iOS / Other
    city_id             INTEGER,
    acquirer_id         INTEGER,
    -- Derived columns (computed at query time)
    FOREIGN KEY (customer_id)   REFERENCES dim_customer(customer_id),
    FOREIGN KEY (merchant_id)   REFERENCES dim_merchant(merchant_id),
    FOREIGN KEY (channel_id)    REFERENCES dim_channel(channel_id),
    FOREIGN KEY (city_id)       REFERENCES dim_city(city_id),
    FOREIGN KEY (txn_date)      REFERENCES dim_date(date)
);

-- ────────────────────────────────────────────────────────────
-- INDEXES — critical for query performance on 50k+ rows
-- ────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_fact_txn_date       ON fact_transactions(txn_date);
CREATE INDEX IF NOT EXISTS idx_fact_customer       ON fact_transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_fact_channel        ON fact_transactions(channel_id);
CREATE INDEX IF NOT EXISTS idx_fact_status         ON fact_transactions(status);
CREATE INDEX IF NOT EXISTS idx_fact_city           ON fact_transactions(city_id);
CREATE INDEX IF NOT EXISTS idx_fact_cust_date      ON fact_transactions(customer_id, txn_date);
CREATE INDEX IF NOT EXISTS idx_fact_channel_date   ON fact_transactions(channel_id, txn_date);

-- ────────────────────────────────────────────────────────────
-- NOTES FOR POSTGRESQL USERS
-- ────────────────────────────────────────────────────────────
-- Replace DATE_TRUNC('month', col) for monthly grouping (SQLite uses strftime)
-- Replace DATE_DIFF('day', a, b) with JULIANDAY(b) - JULIANDAY(a)
-- PARTITION BY txn_date RANGE: add in PostgreSQL for time-based partitioning
-- MATERIALIZED VIEW for rollup_daily_kpis can be added for repeated aggregations
