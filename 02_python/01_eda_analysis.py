"""
UPI Transaction Analytics Project
Script: 01_eda_analysis.py
Purpose: Exploratory Data Analysis — visualize all core KPIs, distributions,
         channel mix, geo insights using pandas + matplotlib + seaborn.
         NO ML / AI / DL. Pure statistical + visual analytics.
"""

import sqlite3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
import warnings
import os

warnings.filterwarnings("ignore")
os.makedirs("outputs/eda", exist_ok=True)

# -------------------------------------------------------
# CONFIG
# -------------------------------------------------------
DB_PATH = "../upi_analytics.db"
sns.set_theme(style="whitegrid", palette="muted")
plt.rcParams.update({"figure.dpi": 130, "figure.figsize": (12, 5)})

COLORS = {
    "UPI":    "#1f77b4",
    "CARD":   "#ff7f0e",
    "WALLET": "#2ca02c",
    "NB":     "#d62728",
}


# -------------------------------------------------------
# HELPER
# -------------------------------------------------------
def query(sql: str) -> pd.DataFrame:
    with sqlite3.connect(DB_PATH) as conn:
        return pd.read_sql_query(sql, conn)


def save(fig, name: str):
    path = f"outputs/eda/{name}.png"
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print(f"  ✓ Saved → {path}")


# -------------------------------------------------------
# 1. GMV & NET REVENUE MONTHLY TREND
# -------------------------------------------------------
def plot_gmv_revenue_trend():
    df = query("""
        SELECT
            STRFTIME('%Y-%m', txn_date) AS month,
            SUM(amount) AS gmv,
            SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS net_revenue,
            COUNT(*) AS txn_count
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY month ORDER BY month
    """)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].bar(df["month"], df["gmv"] / 1e6, color="#1f77b4", alpha=0.85)
    axes[0].set_title("Monthly GMV (₹ Million)", fontsize=13, fontweight="bold")
    axes[0].set_xlabel("Month")
    axes[0].set_ylabel("GMV (₹ M)")
    axes[0].tick_params(axis="x", rotation=45)

    axes[1].plot(df["month"], df["net_revenue"] / 1000, marker="o", color="#ff7f0e", linewidth=2)
    axes[1].fill_between(df["month"], df["net_revenue"] / 1000, alpha=0.15, color="#ff7f0e")
    axes[1].set_title("Monthly Net Revenue (₹ Thousands)", fontsize=13, fontweight="bold")
    axes[1].set_xlabel("Month")
    axes[1].set_ylabel("Net Revenue (₹ K)")
    axes[1].tick_params(axis="x", rotation=45)

    fig.suptitle("Platform GMV & Revenue Trend", fontsize=15, fontweight="bold")
    plt.tight_layout()
    save(fig, "01_gmv_revenue_trend")
    return df


# -------------------------------------------------------
# 2. MoM GROWTH %
# -------------------------------------------------------
def plot_mom_growth():
    df = query("""
        WITH monthly AS (
            SELECT STRFTIME('%Y-%m', txn_date) AS month,
                   SUM(amount) AS gmv,
                   SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS net_revenue,
                   COUNT(DISTINCT customer_id) AS mau
            FROM fact_transactions WHERE status='SUCCESS'
            GROUP BY month
        )
        SELECT month, gmv, net_revenue, mau,
               (gmv - LAG(gmv) OVER (ORDER BY month)) / LAG(gmv) OVER (ORDER BY month) * 100 AS gmv_mom,
               (net_revenue - LAG(net_revenue) OVER (ORDER BY month))
               / LAG(net_revenue) OVER (ORDER BY month) * 100 AS rev_mom,
               (mau - LAG(mau) OVER (ORDER BY month))
               / LAG(mau) OVER (ORDER BY month) * 100 AS mau_mom
        FROM monthly
    """)
    df = df.dropna()

    fig, ax = plt.subplots(figsize=(13, 5))
    x = range(len(df))
    width = 0.3
    ax.bar([i - width for i in x], df["gmv_mom"],   width, label="GMV MoM %",     color="#1f77b4", alpha=0.85)
    ax.bar([i        for i in x], df["rev_mom"],    width, label="Revenue MoM %", color="#ff7f0e", alpha=0.85)
    ax.bar([i + width for i in x], df["mau_mom"],   width, label="MAU MoM %",     color="#2ca02c", alpha=0.85)
    ax.axhline(0, color="black", linewidth=0.8, linestyle="--")
    ax.set_xticks(list(x))
    ax.set_xticklabels(df["month"].tolist(), rotation=45)
    ax.set_title("Month-over-Month Growth %  (GMV · Revenue · MAU)", fontsize=13, fontweight="bold")
    ax.set_ylabel("Growth %")
    ax.legend()
    plt.tight_layout()
    save(fig, "02_mom_growth")
    return df


# -------------------------------------------------------
# 3. CHANNEL MIX
# -------------------------------------------------------
def plot_channel_mix():
    df = query("""
        SELECT ch.channel_name,
               COUNT(*) AS txn_count,
               SUM(f.amount) AS gmv,
               SUM(f.cashback_amt + f.processing_fee_amt) AS total_cost,
               SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt) AS net_revenue
        FROM fact_transactions f
        JOIN dim_channel ch ON f.channel_id = ch.channel_id
        WHERE f.status='SUCCESS'
        GROUP BY ch.channel_name ORDER BY gmv DESC
    """)

    fig, axes = plt.subplots(1, 3, figsize=(16, 5))

    # Pie — GMV share
    axes[0].pie(df["gmv"], labels=df["channel_name"], autopct="%1.1f%%",
                colors=[COLORS.get(c, "#aec7e8") for c in df["channel_name"]])
    axes[0].set_title("GMV Share by Channel", fontweight="bold")

    # Bar — Net Revenue vs Cost
    x = range(len(df))
    w = 0.35
    axes[1].bar([i - w/2 for i in x], df["net_revenue"], w, label="Net Revenue", color="#1f77b4")
    axes[1].bar([i + w/2 for i in x], df["total_cost"],  w, label="Total Cost",  color="#d62728", alpha=0.7)
    axes[1].set_xticks(list(x))
    axes[1].set_xticklabels(df["channel_name"].tolist())
    axes[1].set_title("Net Revenue vs Cost by Channel", fontweight="bold")
    axes[1].legend()

    # Efficiency ratio
    df["efficiency"] = df["net_revenue"] / df["total_cost"].replace(0, np.nan)
    axes[2].barh(df["channel_name"], df["efficiency"],
                 color=[COLORS.get(c, "#aec7e8") for c in df["channel_name"]])
    axes[2].axvline(1, color="red", linestyle="--", linewidth=1.2)
    axes[2].set_title("Channel Efficiency Ratio\n(>1 = Profitable)", fontweight="bold")
    axes[2].set_xlabel("Efficiency Ratio")

    fig.suptitle("Channel Performance Analysis", fontsize=14, fontweight="bold")
    plt.tight_layout()
    save(fig, "03_channel_mix")
    return df


# -------------------------------------------------------
# 4. GEO — TOP STATES BY GMV
# -------------------------------------------------------
def plot_geo_gmv():
    df = query("""
        SELECT ci.state, ci.tier,
               SUM(f.amount) AS gmv,
               COUNT(DISTINCT f.customer_id) AS users
        FROM fact_transactions f
        JOIN dim_city ci ON f.city_id = ci.city_id
        WHERE f.status='SUCCESS'
        GROUP BY ci.state, ci.tier ORDER BY gmv DESC LIMIT 15
    """)

    fig, axes = plt.subplots(1, 2, figsize=(16, 6))

    palette = {"Tier-1": "#1f77b4", "Tier-2": "#ff7f0e", "Tier-3": "#2ca02c"}
    colors  = [palette.get(t, "#aec7e8") for t in df["tier"]]
    axes[0].barh(df["state"], df["gmv"] / 1e6, color=colors)
    axes[0].set_title("Top 15 States by GMV (₹ M)", fontweight="bold")
    axes[0].set_xlabel("GMV (₹ Million)")
    axes[0].invert_yaxis()

    tier_df = df.groupby("tier")["gmv"].sum().reset_index()
    axes[1].pie(tier_df["gmv"], labels=tier_df["tier"], autopct="%1.1f%%",
                colors=["#1f77b4", "#ff7f0e", "#2ca02c"])
    axes[1].set_title("GMV Share by City Tier", fontweight="bold")

    plt.tight_layout()
    save(fig, "04_geo_gmv")
    return df


# -------------------------------------------------------
# 5. TRANSACTION AMOUNT DISTRIBUTION
# -------------------------------------------------------
def plot_amount_distribution():
    df = query("""
        SELECT amount FROM fact_transactions WHERE status='SUCCESS' AND amount <= 2000
    """)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].hist(df["amount"], bins=60, color="#1f77b4", edgecolor="white", alpha=0.85)
    axes[0].set_title("Transaction Amount Distribution (≤₹2000)", fontweight="bold")
    axes[0].set_xlabel("Amount (₹)")
    axes[0].set_ylabel("Frequency")

    # Box plot by channel
    df_ch = query("""
        SELECT f.amount, ch.channel_name
        FROM fact_transactions f
        JOIN dim_channel ch ON f.channel_id = ch.channel_id
        WHERE f.status='SUCCESS' AND f.amount <= 2000
    """)
    df_ch.boxplot(column="amount", by="channel_name", ax=axes[1])
    axes[1].set_title("Amount Distribution by Channel", fontweight="bold")
    axes[1].set_xlabel("Channel")
    axes[1].set_ylabel("Amount (₹)")
    fig.suptitle("")

    plt.tight_layout()
    save(fig, "05_amount_distribution")


# -------------------------------------------------------
# 6. MAU TREND & NEW vs RETURNING USERS
# -------------------------------------------------------
def plot_user_trends():
    df = query("""
        WITH first_month AS (
            SELECT customer_id,
                   STRFTIME('%Y-%m', MIN(txn_date)) AS first_m
            FROM fact_transactions WHERE status='SUCCESS' GROUP BY customer_id
        ),
        monthly AS (
            SELECT STRFTIME('%Y-%m', f.txn_date) AS month,
                   f.customer_id, fm.first_m
            FROM fact_transactions f
            JOIN first_month fm ON f.customer_id = fm.customer_id
            WHERE f.status='SUCCESS'
            GROUP BY STRFTIME('%Y-%m', f.txn_date), f.customer_id, fm.first_m
        )
        SELECT month,
               COUNT(DISTINCT customer_id) AS mau,
               COUNT(DISTINCT CASE WHEN month = first_m THEN customer_id END) AS new_users,
               COUNT(DISTINCT CASE WHEN month != first_m THEN customer_id END) AS returning_users
        FROM monthly GROUP BY month ORDER BY month
    """)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    axes[0].plot(df["month"], df["mau"], marker="o", color="#1f77b4", linewidth=2, label="MAU")
    axes[0].tick_params(axis="x", rotation=45)
    axes[0].set_title("Monthly Active Users (MAU)", fontweight="bold")
    axes[0].set_ylabel("Users")

    axes[1].bar(df["month"], df["new_users"],       label="New Users",       color="#2ca02c", alpha=0.85)
    axes[1].bar(df["month"], df["returning_users"], label="Returning Users", color="#1f77b4", alpha=0.85,
                bottom=df["new_users"])
    axes[1].tick_params(axis="x", rotation=45)
    axes[1].set_title("New vs Returning Users per Month", fontweight="bold")
    axes[1].legend()

    plt.tight_layout()
    save(fig, "06_user_trends")
    return df


# -------------------------------------------------------
# 7. SUCCESS RATE & RETRY ANALYSIS
# -------------------------------------------------------
def plot_success_retry():
    df = query("""
        SELECT retry_count,
               COUNT(*) AS total,
               SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END) AS success_cnt,
               ROUND(SUM(CASE WHEN status='SUCCESS' THEN 1.0 ELSE 0 END) / COUNT(*) * 100, 2) AS success_rate
        FROM fact_transactions
        GROUP BY retry_count ORDER BY retry_count
    """)

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    axes[0].bar(df["retry_count"].astype(str), df["success_rate"], color="#1f77b4", alpha=0.85)
    axes[0].set_title("Success Rate by Retry Count", fontweight="bold")
    axes[0].set_xlabel("Retry Count")
    axes[0].set_ylabel("Success Rate %")

    status_df = query("""
        SELECT status, COUNT(*) AS cnt
        FROM fact_transactions GROUP BY status
    """)
    axes[1].pie(status_df["cnt"], labels=status_df["status"], autopct="%1.1f%%",
                colors=["#2ca02c", "#d62728", "#ff7f0e"])
    axes[1].set_title("Transaction Status Distribution", fontweight="bold")

    plt.tight_layout()
    save(fig, "07_success_retry")


# -------------------------------------------------------
# 8. CASHBACK ANALYSIS
# -------------------------------------------------------
def plot_cashback():
    df = query("""
        SELECT STRFTIME('%Y-%m', txn_date) AS month,
               SUM(cashback_amt) AS total_cashback,
               SUM(amount) AS gmv,
               SUM(cashback_amt) / SUM(amount) * 100 AS cashback_rate_pct,
               SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS net_revenue
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY month ORDER BY month
    """)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    axes[0].plot(df["month"], df["cashback_rate_pct"], marker="o", color="#d62728", linewidth=2)
    axes[0].set_title("Cashback Rate % of GMV over Time", fontweight="bold")
    axes[0].set_ylabel("Cashback %")
    axes[0].tick_params(axis="x", rotation=45)
    ax2 = axes[0].twinx()
    ax2.bar(df["month"], df["total_cashback"] / 1000, alpha=0.3, color="#d62728", label="Cashback ₹K")
    ax2.set_ylabel("Total Cashback (₹K)")

    axes[1].scatter(df["total_cashback"] / 1000, df["net_revenue"] / 1000,
                    color="#ff7f0e", s=80, edgecolors="black", linewidths=0.5)
    for _, row in df.iterrows():
        axes[1].annotate(row["month"], (row["total_cashback"]/1000, row["net_revenue"]/1000),
                         fontsize=7, textcoords="offset points", xytext=(4, 4))
    axes[1].set_xlabel("Total Cashback (₹K)")
    axes[1].set_ylabel("Net Revenue (₹K)")
    axes[1].set_title("Cashback vs Net Revenue (per month)", fontweight="bold")

    plt.tight_layout()
    save(fig, "08_cashback_analysis")


# -------------------------------------------------------
# 9. HOUR-OF-DAY HEATMAP
# -------------------------------------------------------
def plot_hour_heatmap():
    df = query("""
        SELECT CAST(STRFTIME('%H', txn_ts) AS INT) AS hour,
               CAST(STRFTIME('%m', txn_date) AS INT) AS month_num,
               COUNT(*) AS txn_count
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY hour, month_num
    """)

    pivot = df.pivot(index="hour", columns="month_num", values="txn_count").fillna(0)
    fig, ax = plt.subplots(figsize=(14, 8))
    sns.heatmap(pivot, ax=ax, cmap="YlOrRd", linewidths=0.3,
                cbar_kws={"label": "Transaction Count"})
    ax.set_title("Transaction Volume — Hour of Day × Month", fontweight="bold", fontsize=13)
    ax.set_xlabel("Month")
    ax.set_ylabel("Hour of Day (0–23)")
    plt.tight_layout()
    save(fig, "09_hour_month_heatmap")


# -------------------------------------------------------
# MAIN
# -------------------------------------------------------
if __name__ == "__main__":
    print("=" * 55)
    print("  UPI Analytics — Exploratory Data Analysis")
    print("=" * 55)

    plot_gmv_revenue_trend()
    plot_mom_growth()
    plot_channel_mix()
    plot_geo_gmv()
    plot_amount_distribution()
    plot_user_trends()
    plot_success_retry()
    plot_cashback()
    plot_hour_heatmap()

    print("\n  ✓ All EDA charts saved to outputs/eda/")
