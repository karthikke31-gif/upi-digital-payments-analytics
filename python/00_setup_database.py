"""
============================================================
FILE: 00_setup_database.py
PURPOSE: Load all CSVs into SQLite + Run all SQL queries + Export results
RUN THIS FIRST before any other Python script
============================================================
"""

import sqlite3
import pandas as pd
import os
import sys

# ─────────────────────────────────────────────────────────
# CONFIGURATION — Update paths if needed
# ─────────────────────────────────────────────────────────

DATA_DIR   = os.path.join(os.path.dirname(__file__), '..', 'data')
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'outputs')
DB_PATH    = os.path.join(os.path.dirname(__file__), '..', 'upi_analytics.db')

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(DATA_DIR,   exist_ok=True)

# Map CSV filenames → table names
CSV_FILES = {
    'fact_transactions': 'fact_transactions_50k.csv',
    'dim_customer':      'dim_customer_50k.csv',
    'dim_merchant':      'dim_merchant_50k.csv',
    'dim_channel':       'dim_channel_50k.csv',
    'dim_city':          'dim_city_50k.csv',
    'dim_date':          'dim_date_50k.csv',
}


def load_data(conn: sqlite3.Connection, data_dir: str) -> None:
    """Load all CSV files into SQLite tables."""
    for table_name, filename in CSV_FILES.items():
        filepath = os.path.join(data_dir, filename)
        if not os.path.exists(filepath):
            print(f"  [SKIP] {filepath} not found.")
            continue
        df = pd.read_csv(filepath)
        df.to_sql(table_name, conn, if_exists='replace', index=False)
        print(f"  [OK]   {table_name}: {len(df):,} rows loaded")


def create_indexes(conn: sqlite3.Connection) -> None:
    """Create performance indexes."""
    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_fact_txn_date     ON fact_transactions(txn_date)",
        "CREATE INDEX IF NOT EXISTS idx_fact_customer      ON fact_transactions(customer_id)",
        "CREATE INDEX IF NOT EXISTS idx_fact_channel       ON fact_transactions(channel_id)",
        "CREATE INDEX IF NOT EXISTS idx_fact_status        ON fact_transactions(status)",
        "CREATE INDEX IF NOT EXISTS idx_fact_city          ON fact_transactions(city_id)",
        "CREATE INDEX IF NOT EXISTS idx_fact_cust_date     ON fact_transactions(customer_id, txn_date)",
    ]
    for idx in indexes:
        conn.execute(idx)
    conn.commit()
    print("  [OK]   Indexes created")


def run_query(conn: sqlite3.Connection, sql: str) -> pd.DataFrame:
    """Execute a SQL query and return result as DataFrame."""
    return pd.read_sql_query(sql, conn)


def export_kpis(conn: sqlite3.Connection) -> dict:
    """Run all core KPI queries and export to Excel."""
    results = {}

    print("\n  Running KPI queries...")

    # ── GMV Summary
    results['gmv_summary'] = run_query(conn, """
        SELECT
            ROUND(SUM(amount), 2)           AS total_gmv,
            COUNT(*)                         AS total_txns,
            ROUND(AVG(amount), 2)            AS avg_txn_value,
            COUNT(DISTINCT customer_id)      AS unique_customers,
            COUNT(DISTINCT merchant_id)      AS unique_merchants
        FROM fact_transactions
        WHERE status = 'SUCCESS'
    """)

    # ── Net Revenue
    results['revenue_summary'] = run_query(conn, """
        SELECT
            ROUND(SUM(amount), 2)                                         AS total_gmv,
            ROUND(SUM((mdr_pct/100.0)*amount), 2)                        AS gross_mdr,
            ROUND(SUM(cashback_amt), 2)                                   AS cashback_cost,
            ROUND(SUM(processing_fee_amt), 2)                             AS processing_cost,
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
                  / NULLIF(SUM(amount),0)*100, 4)                         AS margin_pct
        FROM fact_transactions WHERE status='SUCCESS'
    """)

    # ── Monthly KPIs
    results['monthly_kpis'] = run_query(conn, """
        WITH monthly AS (
            SELECT
                strftime('%Y-%m', txn_date)                               AS month,
                ROUND(SUM(amount), 2)                                     AS gmv,
                ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
                COUNT(DISTINCT customer_id)                               AS mau,
                COUNT(*)                                                  AS txn_count,
                ROUND(SUM(cashback_amt), 2)                               AS cashback_spent
            FROM fact_transactions WHERE status='SUCCESS'
            GROUP BY strftime('%Y-%m', txn_date)
        )
        SELECT *,
            LAG(gmv) OVER (ORDER BY month) AS prev_gmv,
            ROUND((gmv - LAG(gmv) OVER (ORDER BY month))
                  / NULLIF(LAG(gmv) OVER (ORDER BY month), 0)*100, 2)    AS gmv_mom_pct,
            ROUND((net_revenue - LAG(net_revenue) OVER (ORDER BY month))
                  / NULLIF(LAG(net_revenue) OVER (ORDER BY month), 0)*100, 2) AS rev_mom_pct,
            ROUND((mau - LAG(mau) OVER (ORDER BY month))
                  / NULLIF(LAG(mau) OVER (ORDER BY month), 0)*100, 2)    AS mau_mom_pct
        FROM monthly ORDER BY month
    """)

    # ── Channel Efficiency
    results['channel_efficiency'] = run_query(conn, """
        SELECT
            ch.channel_name,
            COUNT(*) AS txn_count,
            ROUND(SUM(f.amount), 2) AS gmv,
            ROUND(SUM(f.cashback_amt), 2) AS cashback,
            ROUND(SUM(f.processing_fee_amt), 2) AS processing_cost,
            ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue,
            ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
                  / NULLIF(SUM(f.cashback_amt + f.processing_fee_amt), 0), 4) AS efficiency_ratio,
            ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
                  / NULLIF(SUM(f.amount), 0)*100, 4) AS margin_pct
        FROM fact_transactions f
        JOIN dim_channel ch ON f.channel_id = ch.channel_id
        WHERE f.status='SUCCESS'
        GROUP BY ch.channel_name ORDER BY net_revenue DESC
    """)

    # ── Geo GMV
    results['geo_gmv'] = run_query(conn, """
        SELECT ci.state, ci.tier,
            COUNT(*) AS txn_count,
            COUNT(DISTINCT f.customer_id) AS unique_customers,
            ROUND(SUM(f.amount), 2) AS gmv,
            ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue
        FROM fact_transactions f
        JOIN dim_city ci ON f.city_id = ci.city_id
        WHERE f.status='SUCCESS'
        GROUP BY ci.state, ci.tier
        ORDER BY gmv DESC
    """)

    # ── RFM Base
    results['rfm_segments'] = run_query(conn, """
        WITH rfm AS (
            SELECT customer_id,
                CAST(JULIANDAY('2026-03-05') - JULIANDAY(MAX(txn_date)) AS INTEGER) AS recency_days,
                COUNT(*) AS frequency,
                ROUND(SUM(amount), 2) AS monetary
            FROM fact_transactions WHERE status='SUCCESS'
            GROUP BY customer_id
        ),
        pcts AS (
            SELECT
                (SELECT recency_days FROM rfm ORDER BY recency_days LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm)) r_p25,
                (SELECT recency_days FROM rfm ORDER BY recency_days LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm)) r_p50,
                (SELECT recency_days FROM rfm ORDER BY recency_days LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm)) r_p75,
                (SELECT frequency FROM rfm ORDER BY frequency LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm)) f_p25,
                (SELECT frequency FROM rfm ORDER BY frequency LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm)) f_p50,
                (SELECT frequency FROM rfm ORDER BY frequency LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm)) f_p75,
                (SELECT monetary FROM rfm ORDER BY monetary LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.25 AS INT) FROM rfm)) m_p25,
                (SELECT monetary FROM rfm ORDER BY monetary LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.50 AS INT) FROM rfm)) m_p50,
                (SELECT monetary FROM rfm ORDER BY monetary LIMIT 1 OFFSET (SELECT CAST(COUNT(*)*0.75 AS INT) FROM rfm)) m_p75
        ),
        scored AS (
            SELECT r.customer_id, r.monetary,
                CASE WHEN r.recency_days<=p.r_p25 THEN 4 WHEN r.recency_days<=p.r_p50 THEN 3 WHEN r.recency_days<=p.r_p75 THEN 2 ELSE 1 END rs,
                CASE WHEN r.frequency>=p.f_p75 THEN 4 WHEN r.frequency>=p.f_p50 THEN 3 WHEN r.frequency>=p.f_p25 THEN 2 ELSE 1 END fs,
                CASE WHEN r.monetary>=p.m_p75 THEN 4 WHEN r.monetary>=p.m_p50 THEN 3 WHEN r.monetary>=p.m_p25 THEN 2 ELSE 1 END ms
            FROM rfm r, pcts p
        )
        SELECT
            CASE
                WHEN rs=4 AND fs=4 AND ms=4  THEN 'Champions'
                WHEN rs>=3 AND fs>=3          THEN 'Loyal Customers'
                WHEN rs=4 AND fs<=2           THEN 'New Customers'
                WHEN rs>=3 AND fs<=2 AND ms>=3 THEN 'Potential Loyalists'
                WHEN rs=2 AND fs>=3           THEN 'At Risk'
                WHEN rs<=2 AND fs<=2 AND ms>=3 THEN 'Cant Lose Them'
                WHEN rs<=2 AND fs<=2 AND ms<=2 THEN 'Lost Customers'
                WHEN rs=1                     THEN 'Hibernating'
                ELSE                               'Needs Attention'
            END AS rfm_segment,
            COUNT(*) AS customers,
            ROUND(SUM(monetary), 2) AS revenue,
            ROUND(AVG(monetary), 2) AS avg_revenue
        FROM scored
        GROUP BY rfm_segment ORDER BY revenue DESC
    """)

    # ── What-If Scenarios
    results['whatif_scenarios'] = run_query(conn, """
        SELECT 'BASE' AS scenario,
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)/NULLIF(SUM(amount),0)*100, 4) AS margin_pct
        FROM fact_transactions WHERE status='SUCCESS'
        UNION ALL
        SELECT 'MDR +0.5%',
            ROUND(SUM(((mdr_pct+0.5)/100.0)*amount - cashback_amt - processing_fee_amt), 2),
            ROUND(SUM(((mdr_pct+0.5)/100.0)*amount - cashback_amt - processing_fee_amt)/NULLIF(SUM(amount),0)*100, 4)
        FROM fact_transactions WHERE status='SUCCESS'
        UNION ALL
        SELECT 'Cashback -25%',
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.75 - processing_fee_amt), 2),
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.75 - processing_fee_amt)/NULLIF(SUM(amount),0)*100, 4)
        FROM fact_transactions WHERE status='SUCCESS'
        UNION ALL
        SELECT 'Cashback -50%',
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.50 - processing_fee_amt), 2),
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt*0.50 - processing_fee_amt)/NULLIF(SUM(amount),0)*100, 4)
        FROM fact_transactions WHERE status='SUCCESS'
        UNION ALL
        SELECT 'Processing Fee -10%',
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt*0.90), 2),
            ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt*0.90)/NULLIF(SUM(amount),0)*100, 4)
        FROM fact_transactions WHERE status='SUCCESS'
        UNION ALL
        SELECT 'Optimized (MDR+0.3, CB-20%, PF-5%)',
            ROUND(SUM(((mdr_pct+0.3)/100.0)*amount - cashback_amt*0.80 - processing_fee_amt*0.95), 2),
            ROUND(SUM(((mdr_pct+0.3)/100.0)*amount - cashback_amt*0.80 - processing_fee_amt*0.95)/NULLIF(SUM(amount),0)*100, 4)
        FROM fact_transactions WHERE status='SUCCESS'
    """)

    # ── Churn Risk
    results['churn_risk'] = run_query(conn, """
        WITH ca AS (
            SELECT customer_id,
                MAX(txn_date) AS last_txn,
                COUNT(*) AS total_txns,
                COUNT(CASE WHEN txn_date >= date('2026-03-05', '-90 days') THEN 1 END) AS txns_90d,
                COUNT(CASE WHEN txn_date >= date('2026-03-05', '-30 days') THEN 1 END) AS txns_30d
            FROM fact_transactions WHERE status='SUCCESS'
            GROUP BY customer_id
        )
        SELECT
            CASE
                WHEN JULIANDAY('2026-03-05') - JULIANDAY(last_txn) > 90 AND txns_90d=0  THEN 'CHURNED'
                WHEN JULIANDAY('2026-03-05') - JULIANDAY(last_txn) > 60 AND txns_90d<2  THEN 'HIGH_RISK'
                WHEN JULIANDAY('2026-03-05') - JULIANDAY(last_txn) > 30 AND txns_30d=0  THEN 'AT_RISK'
                WHEN txns_30d>=1 AND txns_90d>=3                                          THEN 'ACTIVE'
                ELSE                                                                           'MODERATE_RISK'
            END AS churn_segment,
            COUNT(*) AS users,
            ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER(), 2) AS pct
        FROM ca
        GROUP BY churn_segment ORDER BY users DESC
    """)

    return results


def export_to_excel(results: dict, output_dir: str) -> None:
    """Export all results to a single Excel workbook."""
    out_path = os.path.join(output_dir, 'kpi_results.xlsx')
    with pd.ExcelWriter(out_path, engine='openpyxl') as writer:
        for sheet_name, df in results.items():
            df.to_excel(writer, sheet_name=sheet_name[:31], index=False)
    print(f"\n  [SAVED] KPI results → {out_path}")


def main():
    print("=" * 60)
    print("  UPI Analytics — Database Setup & KPI Export")
    print("=" * 60)

    # Find data directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    data_dir   = os.path.join(script_dir, '..', 'data')
    output_dir = os.path.join(script_dir, '..', 'outputs')
    db_path    = os.path.join(script_dir, '..', 'upi_analytics.db')

    os.makedirs(output_dir, exist_ok=True)

    print(f"\n  Data dir:   {os.path.abspath(data_dir)}")
    print(f"  Database:   {os.path.abspath(db_path)}")

    conn = sqlite3.connect(db_path)

    print("\n  Loading CSVs into SQLite...")
    load_data(conn, data_dir)

    print("\n  Creating indexes...")
    create_indexes(conn)

    print("\n  Exporting KPI results...")
    results = export_kpis(conn)

    for name, df in results.items():
        print(f"    {name}: {len(df)} rows")

    export_to_excel(results, output_dir)

    conn.close()
    print("\n  Setup complete! Run 01_eda_visuals.py next.")


if __name__ == "__main__":
    main()
