"""
UPI Transaction Analytics Project
Script: 00_setup_database.py
Purpose: Load all CSV files into an SQLite database for SQL analysis.
         SQLite is used here for portability — the same SQL logic works
         on PostgreSQL, BigQuery, or any RDBMS with minor syntax tweaks.
"""

import sqlite3
import pandas as pd
import os
import time

# -------------------------------------------------------
# CONFIG
# -------------------------------------------------------
DB_PATH   = "upi_analytics.db"
DATA_DIR  = "data"

FILES = {
    "dim_date":         "dim_date.csv",
    "dim_channel":      "dim_channel.csv",
    "dim_city":         "dim_city.csv",
    "dim_customer":     "dim_customer.csv",
    "dim_merchant":     "dim_merchant.csv",
    "fact_transactions":"fact_transactions.csv",
}

# -------------------------------------------------------
# HELPER
# -------------------------------------------------------
def load_csv(conn: sqlite3.Connection, table: str, filename: str):
    path = os.path.join(DATA_DIR, filename)
    df   = pd.read_csv(path)

    # Normalize boolean columns (SQLite stores as 0/1)
    for col in df.columns:
        if df[col].dtype == object and df[col].isin(["True", "False"]).any():
            df[col] = df[col].map({"True": 1, "False": 0})

    df.to_sql(table, conn, if_exists="replace", index=False)
    print(f"  ✓ Loaded {table:25s} → {len(df):>7,} rows")
    return df


# -------------------------------------------------------
# MAIN
# -------------------------------------------------------
def main():
    print("=" * 60)
    print("  UPI Analytics — Database Setup")
    print("=" * 60)

    # Remove stale DB
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        print(f"  Removed existing DB: {DB_PATH}")

    conn = sqlite3.connect(DB_PATH)
    t0   = time.time()

    print("\n  Loading dimension tables first…")
    for table in ["dim_date", "dim_channel", "dim_city", "dim_customer", "dim_merchant"]:
        load_csv(conn, table, FILES[table])

    print("\n  Loading fact table (50 k rows)…")
    load_csv(conn, "fact_transactions", FILES["fact_transactions"])

    # -------------------------------------------------------
    # Create indexes for performance
    # -------------------------------------------------------
    print("\n  Creating indexes…")
    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_txn_date    ON fact_transactions(txn_date)",
        "CREATE INDEX IF NOT EXISTS idx_txn_status  ON fact_transactions(status)",
        "CREATE INDEX IF NOT EXISTS idx_txn_cust    ON fact_transactions(customer_id, txn_date)",
        "CREATE INDEX IF NOT EXISTS idx_txn_channel ON fact_transactions(channel_id)",
        "CREATE INDEX IF NOT EXISTS idx_txn_city    ON fact_transactions(city_id)",
    ]
    for sql in indexes:
        conn.execute(sql)
    conn.commit()
    print("  ✓ Indexes created")

    # -------------------------------------------------------
    # Quick validation
    # -------------------------------------------------------
    print("\n  Row-count verification:")
    cur = conn.execute("""
        SELECT 'fact_transactions' AS tbl, COUNT(*) AS n FROM fact_transactions
        UNION ALL SELECT 'dim_customer', COUNT(*) FROM dim_customer
        UNION ALL SELECT 'dim_merchant', COUNT(*) FROM dim_merchant
        UNION ALL SELECT 'dim_channel',  COUNT(*) FROM dim_channel
        UNION ALL SELECT 'dim_city',     COUNT(*) FROM dim_city
        UNION ALL SELECT 'dim_date',     COUNT(*) FROM dim_date
    """)
    for row in cur.fetchall():
        print(f"    {row[0]:25s}: {row[1]:>7,}")

    elapsed = time.time() - t0
    print(f"\n  ✓ Database ready → {DB_PATH}  ({elapsed:.1f}s)")
    conn.close()


if __name__ == "__main__":
    main()
