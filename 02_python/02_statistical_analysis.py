"""
UPI Transaction Analytics Project
Script: 02_statistical_analysis.py
Purpose: Statistical tests, confidence intervals (bootstrap),
         cohort retention heatmap, RFM segmentation chart,
         CLV distribution, churn funnel — NO ML/AI/DL.
"""

import sqlite3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import seaborn as sns
from scipy import stats
import warnings
import os

warnings.filterwarnings("ignore")
os.makedirs("outputs/stats", exist_ok=True)

DB_PATH = "../upi_analytics.db"
sns.set_theme(style="whitegrid")
plt.rcParams.update({"figure.dpi": 130})
ANALYSIS_DATE = "2025-12-31"


def query(sql: str) -> pd.DataFrame:
    with sqlite3.connect(DB_PATH) as conn:
        return pd.read_sql_query(sql, conn)


def save(fig, name: str):
    path = f"outputs/stats/{name}.png"
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print(f"  ✓ Saved → {path}")


# ============================================================
# 1. BOOTSTRAP CONFIDENCE INTERVAL FOR MARGIN %
# ============================================================
def bootstrap_margin_ci(n_boot: int = 2000):
    """
    Bootstrap 95% CI for margin %.
    Pure resampling — no distribution assumptions.
    """
    print("\n--- Bootstrap CI: Margin % ---")
    df = query("""
        SELECT amount, mdr_pct, cashback_amt, processing_fee_amt
        FROM fact_transactions WHERE status='SUCCESS'
    """)

    df["net_rev"] = (df["mdr_pct"] / 100.0) * df["amount"] - df["cashback_amt"] - df["processing_fee_amt"]
    observed_margin = df["net_rev"].sum() / df["amount"].sum() * 100

    rng = np.random.default_rng(42)
    margins = []
    for _ in range(n_boot):
        idx    = rng.integers(0, len(df), size=len(df))
        sample = df.iloc[idx]
        m      = sample["net_rev"].sum() / sample["amount"].sum() * 100
        margins.append(m)

    ci_low, ci_med, ci_high = np.percentile(margins, [2.5, 50, 97.5])
    print(f"  Observed Margin  : {observed_margin:.4f}%")
    print(f"  Bootstrap Median : {ci_med:.4f}%")
    print(f"  95% CI           : [{ci_low:.4f}%, {ci_high:.4f}%]")

    fig, ax = plt.subplots(figsize=(9, 4))
    ax.hist(margins, bins=60, color="#1f77b4", edgecolor="white", alpha=0.8)
    ax.axvline(observed_margin, color="black",   linestyle="--", linewidth=1.5, label=f"Observed: {observed_margin:.3f}%")
    ax.axvline(ci_low,          color="#d62728", linestyle=":",  linewidth=1.5, label=f"95% CI Low: {ci_low:.3f}%")
    ax.axvline(ci_high,         color="#d62728", linestyle=":",  linewidth=1.5, label=f"95% CI High: {ci_high:.3f}%")
    ax.set_title("Bootstrap Distribution of Margin %  (2000 samples)", fontsize=12, fontweight="bold")
    ax.set_xlabel("Margin %")
    ax.set_ylabel("Frequency")
    ax.legend()
    plt.tight_layout()
    save(fig, "01_bootstrap_margin_ci")
    return observed_margin, (ci_low, ci_high)


# ============================================================
# 2. COHORT RETENTION HEATMAP
# ============================================================
def plot_cohort_heatmap():
    print("\n--- Cohort Retention Heatmap ---")
    df = query("""
        SELECT customer_id, txn_date
        FROM fact_transactions WHERE status='SUCCESS'
    """)
    df["txn_date"] = pd.to_datetime(df["txn_date"])
    df["month"] = df["txn_date"].dt.to_period("M")

    cohort_min = df.groupby("customer_id")["month"].min().rename("cohort_month")
    df = df.join(cohort_min, on="customer_id")

    df["months_since"] = (df["month"] - df["cohort_month"]).apply(lambda x: x.n)
    pivot = df.groupby(["cohort_month", "months_since"])["customer_id"].nunique().unstack(fill_value=0)

    # Convert to retention %
    cohort_sizes = pivot[0]
    retention    = pivot.div(cohort_sizes, axis=0) * 100
    retention    = retention.iloc[:, :12]          # cap at 12 months

    fig, ax = plt.subplots(figsize=(14, 8))
    sns.heatmap(
        retention,
        ax=ax,
        fmt=".0f",
        annot=True,
        cmap="YlOrRd_r",
        linewidths=0.4,
        vmin=0, vmax=100,
        cbar_kws={"label": "Retention %"},
        annot_kws={"size": 8},
    )
    ax.set_title("Cohort Retention Heatmap  (Month 0 = 100%)", fontsize=13, fontweight="bold")
    ax.set_xlabel("Months Since First Transaction")
    ax.set_ylabel("Cohort (First Transaction Month)")
    plt.tight_layout()
    save(fig, "02_cohort_retention_heatmap")
    return retention


# ============================================================
# 3. RFM SEGMENTATION — BAR CHART
# ============================================================
def plot_rfm_segments():
    print("\n--- RFM Segmentation ---")
    df = query("""
        SELECT customer_id,
               MAX(txn_date) AS last_txn,
               COUNT(*) AS frequency,
               SUM(amount) AS monetary
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY customer_id
    """)

    df["last_txn"] = pd.to_datetime(df["last_txn"])
    ref_date = pd.Timestamp(ANALYSIS_DATE)
    df["recency_days"] = (ref_date - df["last_txn"]).dt.days

    df["r_score"] = pd.qcut(df["recency_days"].rank(method="first"), 4, labels=[4, 3, 2, 1]).astype(int)
    df["f_score"] = pd.qcut(df["frequency"].rank(method="first"),    4, labels=[1, 2, 3, 4]).astype(int)
    df["m_score"] = pd.qcut(df["monetary"].rank(method="first"),     4, labels=[1, 2, 3, 4]).astype(int)

    def label(row):
        r, f, m = row["r_score"], row["f_score"], row["m_score"]
        if r == 4 and f == 4 and m == 4:  return "Champions"
        if r >= 3 and f >= 3:             return "Loyal Customers"
        if r == 4 and f <= 2:             return "Recent Customers"
        if r >= 2 and f >= 2 and m >= 2:  return "Needs Attention"
        if r == 2 and f <= 2:             return "At Risk"
        if r == 1 and f >= 2:             return "Cannot Lose"
        if r == 1 and f == 1:             return "Lost"
        return "Hibernating"

    df["segment"] = df.apply(label, axis=1)
    seg_summary = df.groupby("segment").agg(
        users=("customer_id", "count"),
        total_gmv=("monetary", "sum"),
        avg_gmv=("monetary", "mean"),
        avg_recency=("recency_days", "mean"),
    ).reset_index().sort_values("total_gmv", ascending=False)

    fig, axes = plt.subplots(1, 2, figsize=(16, 6))

    palette = sns.color_palette("Set2", len(seg_summary))
    axes[0].barh(seg_summary["segment"], seg_summary["users"], color=palette)
    axes[0].invert_yaxis()
    axes[0].set_title("RFM Segment — User Count", fontweight="bold")
    axes[0].set_xlabel("Number of Users")

    axes[1].barh(seg_summary["segment"], seg_summary["total_gmv"] / 1e6, color=palette)
    axes[1].invert_yaxis()
    axes[1].set_title("RFM Segment — Total GMV (₹ M)", fontweight="bold")
    axes[1].set_xlabel("Total GMV (₹ Million)")

    fig.suptitle("RFM Customer Segmentation", fontsize=14, fontweight="bold")
    plt.tight_layout()
    save(fig, "03_rfm_segments")

    print(seg_summary.to_string(index=False))
    return df, seg_summary


# ============================================================
# 4. CLV DISTRIBUTION
# ============================================================
def plot_clv_distribution():
    print("\n--- CLV Distribution ---")
    df = query("""
        SELECT customer_id,
               SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS clv
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY customer_id
    """)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].hist(df["clv"], bins=60, color="#ff7f0e", edgecolor="white", alpha=0.85)
    axes[0].axvline(df["clv"].mean(),   color="red",   linestyle="--", linewidth=1.5,
                    label=f"Mean: ₹{df['clv'].mean():.2f}")
    axes[0].axvline(df["clv"].median(), color="green", linestyle="--", linewidth=1.5,
                    label=f"Median: ₹{df['clv'].median():.2f}")
    axes[0].set_title("CLV Distribution (Net Revenue per Customer)", fontweight="bold")
    axes[0].set_xlabel("Customer Lifetime Value (₹)")
    axes[0].legend()

    # Lorenz curve (inequality of CLV)
    sorted_clv = np.sort(df["clv"].values)
    cum_clv    = np.cumsum(sorted_clv) / sorted_clv.sum()
    axes[1].plot(np.linspace(0, 1, len(cum_clv)), cum_clv,
                 color="#1f77b4", linewidth=2, label="Actual")
    axes[1].plot([0, 1], [0, 1], "r--", linewidth=1, label="Perfect equality")
    axes[1].fill_between(np.linspace(0, 1, len(cum_clv)), cum_clv,
                          np.linspace(0, 1, len(cum_clv)), alpha=0.2, color="#1f77b4")
    axes[1].set_title("Lorenz Curve — CLV Inequality", fontweight="bold")
    axes[1].set_xlabel("Cumulative % of Customers")
    axes[1].set_ylabel("Cumulative % of Revenue")
    axes[1].legend()

    print(f"  Mean CLV  : ₹{df['clv'].mean():.4f}")
    print(f"  Median CLV: ₹{df['clv'].median():.4f}")
    print(f"  Top 20% users own: "
          f"{df.nlargest(int(len(df)*0.2), 'clv')['clv'].sum() / df['clv'].sum() * 100:.1f}% of revenue")

    plt.tight_layout()
    save(fig, "04_clv_distribution")
    return df


# ============================================================
# 5. CHURN RISK FUNNEL
# ============================================================
def plot_churn_funnel():
    print("\n--- Churn Risk Funnel ---")
    df = query("""
        SELECT customer_id, MAX(txn_date) AS last_txn,
               COUNT(CASE WHEN txn_date >= DATE('2025-12-31', '-90 days') THEN 1 END) AS txns_90d
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY customer_id
    """)
    df["last_txn"]  = pd.to_datetime(df["last_txn"])
    ref             = pd.Timestamp(ANALYSIS_DATE)
    df["days_since"] = (ref - df["last_txn"]).dt.days

    def classify(row):
        if row["days_since"] > 90 and row["txns_90d"] == 0:   return "Churned"
        if 61 <= row["days_since"] <= 90 and row["txns_90d"] < 2: return "High Risk"
        if 31 <= row["days_since"] <= 60:                      return "Medium Risk"
        if row["txns_90d"] >= 3:                               return "Active"
        return "Low Risk"

    df["risk"] = df.apply(classify, axis=1)
    funnel = df["risk"].value_counts().reindex(
        ["Active", "Low Risk", "Medium Risk", "High Risk", "Churned"], fill_value=0
    )

    fig, ax = plt.subplots(figsize=(9, 5))
    colors = ["#2ca02c", "#98df8a", "#ffbb78", "#ff7f0e", "#d62728"]
    bars = ax.bar(funnel.index, funnel.values, color=colors, edgecolor="white")
    for bar, val in zip(bars, funnel.values):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 20,
                f"{val:,}", ha="center", va="bottom", fontsize=10, fontweight="bold")
    ax.set_title("Churn Risk Funnel — Customer Distribution", fontsize=13, fontweight="bold")
    ax.set_ylabel("Number of Customers")
    plt.tight_layout()
    save(fig, "05_churn_risk_funnel")

    print(funnel.to_string())
    return df


# ============================================================
# 6. A/B TEST: Cashback vs No-Cashback — Repeat Rate
# ============================================================
def ab_test_cashback():
    """
    Quasi-experiment: Compare repeat purchase rate between
    transactions WITH cashback vs WITHOUT cashback.
    Uses chi-square test (no ML).
    """
    print("\n--- A/B Test: Cashback Impact on Repeat Rate ---")
    df = query("""
        SELECT customer_id,
               MAX(CASE WHEN cashback_amt > 0 THEN 1 ELSE 0 END) AS had_cashback,
               COUNT(*) AS txn_count
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY customer_id
    """)

    df["repeat"] = (df["txn_count"] > 1).astype(int)

    ct  = pd.crosstab(df["had_cashback"], df["repeat"])
    chi2, p, dof, expected = stats.chi2_contingency(ct)

    cashback_repeat     = df[df["had_cashback"] == 1]["repeat"].mean() * 100
    no_cashback_repeat  = df[df["had_cashback"] == 0]["repeat"].mean() * 100

    print(f"  Cashback users repeat rate    : {cashback_repeat:.2f}%")
    print(f"  No-cashback users repeat rate : {no_cashback_repeat:.2f}%")
    print(f"  Chi-square statistic          : {chi2:.4f}")
    print(f"  p-value                       : {p:.6f}")
    print(f"  Significant (p < 0.05)        : {'YES ✓' if p < 0.05 else 'NO ✗'}")

    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(["No Cashback", "With Cashback"],
           [no_cashback_repeat, cashback_repeat],
           color=["#aec7e8", "#1f77b4"], width=0.5, edgecolor="white")
    ax.set_title(f"Repeat Purchase Rate: Cashback vs No-Cashback\n"
                 f"Chi-square p-value = {p:.4f} {'(Significant)' if p < 0.05 else '(Not Significant)'}",
                 fontweight="bold")
    ax.set_ylabel("Repeat Rate %")
    ax.set_ylim(0, 100)
    for i, v in enumerate([no_cashback_repeat, cashback_repeat]):
        ax.text(i, v + 1, f"{v:.1f}%", ha="center", fontweight="bold")
    plt.tight_layout()
    save(fig, "06_ab_cashback_repeat_rate")
    return chi2, p


# ============================================================
# 7. MARGIN % BY CHANNEL — WITH CI
# ============================================================
def plot_channel_margin_with_ci():
    print("\n--- Channel Margin with Bootstrap CI ---")
    df = query("""
        SELECT f.amount, f.mdr_pct, f.cashback_amt, f.processing_fee_amt, ch.channel_name
        FROM fact_transactions f
        JOIN dim_channel ch ON f.channel_id = ch.channel_id
        WHERE f.status = 'SUCCESS'
    """)
    df["net_rev"] = (df["mdr_pct"] / 100) * df["amount"] - df["cashback_amt"] - df["processing_fee_amt"]

    rng = np.random.default_rng(42)
    results = []
    for ch, grp in df.groupby("channel_name"):
        obs = grp["net_rev"].sum() / grp["amount"].sum() * 100
        margins = []
        for _ in range(1000):
            s = grp.sample(frac=1, replace=True)
            margins.append(s["net_rev"].sum() / s["amount"].sum() * 100)
        lo, hi = np.percentile(margins, [2.5, 97.5])
        results.append({"channel": ch, "margin": obs, "ci_low": lo, "ci_high": hi})

    res = pd.DataFrame(results).sort_values("margin", ascending=False)

    fig, ax = plt.subplots(figsize=(9, 4))
    x = range(len(res))
    ax.bar(x, res["margin"], color="#1f77b4", width=0.5, alpha=0.85, label="Margin %")
    ax.errorbar(
        x, res["margin"],
        yerr=[res["margin"] - res["ci_low"], res["ci_high"] - res["margin"]],
        fmt="none", color="black", capsize=5, linewidth=1.5, label="95% CI"
    )
    ax.set_xticks(list(x))
    ax.set_xticklabels(res["channel"].tolist())
    ax.set_title("Margin % by Channel with 95% Bootstrap CI", fontsize=12, fontweight="bold")
    ax.set_ylabel("Margin %")
    ax.legend()
    plt.tight_layout()
    save(fig, "07_channel_margin_ci")
    print(res.to_string(index=False))


# ============================================================
# MAIN
# ============================================================
if __name__ == "__main__":
    print("=" * 55)
    print("  UPI Analytics — Statistical Analysis")
    print("=" * 55)

    bootstrap_margin_ci()
    plot_cohort_heatmap()
    plot_rfm_segments()
    plot_clv_distribution()
    plot_churn_funnel()
    ab_test_cashback()
    plot_channel_margin_with_ci()

    print("\n  ✓ All statistical charts saved to outputs/stats/")
