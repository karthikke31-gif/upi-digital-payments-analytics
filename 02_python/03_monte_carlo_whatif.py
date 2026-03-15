"""
UPI Transaction Analytics Project
Script: 03_monte_carlo_whatif.py
Purpose: Monte Carlo simulation for What-If scenarios:
         - MDR rate change impact on revenue
         - Cashback reduction impact on margin
         - GMV sensitivity to processing cost reduction
         NO ML / AI / DL. Pure statistical simulation.
"""

import sqlite3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import warnings
import os

warnings.filterwarnings("ignore")
os.makedirs("outputs/whatif", exist_ok=True)

DB_PATH = "../upi_analytics.db"
sns.set_theme(style="whitegrid")
plt.rcParams.update({"figure.dpi": 130})
N_SIMULATIONS = 5000
RNG           = np.random.default_rng(42)


def query(sql: str) -> pd.DataFrame:
    with sqlite3.connect(DB_PATH) as conn:
        return pd.read_sql_query(sql, conn)


def save(fig, name: str):
    path = f"outputs/whatif/{name}.png"
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)
    print(f"  ✓ Saved → {path}")


# ============================================================
# BASE METRICS  (reused across all scenarios)
# ============================================================
def load_base():
    df = query("""
        SELECT amount, mdr_pct, cashback_amt, processing_fee_amt, channel_id
        FROM fact_transactions WHERE status='SUCCESS'
    """)
    df["net_rev"] = (df["mdr_pct"] / 100) * df["amount"] - df["cashback_amt"] - df["processing_fee_amt"]
    base_gmv     = df["amount"].sum()
    base_rev     = df["net_rev"].sum()
    base_margin  = base_rev / base_gmv * 100
    base_cashback = df["cashback_amt"].sum()
    base_processing = df["processing_fee_amt"].sum()
    print(f"\n  Base GMV           : ₹{base_gmv:,.0f}")
    print(f"  Base Net Revenue   : ₹{base_rev:,.2f}")
    print(f"  Base Margin %      : {base_margin:.4f}%")
    print(f"  Base Cashback Cost : ₹{base_cashback:,.2f}")
    print(f"  Base Processing    : ₹{base_processing:,.2f}")
    return df, base_gmv, base_rev, base_margin


# ============================================================
# SCENARIO 1: MDR RATE CHANGE
# Monte Carlo adds random noise to simulate price negotiation
# variability across merchants / acquirers.
# ============================================================
def mdr_scenario(df, base_gmv, base_rev):
    print("\n--- What-If Scenario 1: MDR Rate Change ---")

    mdr_deltas = np.arange(-0.5, 1.51, 0.25)    # -0.5% to +1.5% step 0.25
    rows = []
    for delta in mdr_deltas:
        revenues = []
        for _ in range(N_SIMULATIONS):
            sample = df.sample(frac=1, replace=True)
            # Add noise: ±0.05% uncertainty in MDR realisation
            noise = RNG.normal(0, 0.05, len(sample))
            adj_mdr = sample["mdr_pct"] + delta + noise
            rev = ((adj_mdr / 100) * sample["amount"] - sample["cashback_amt"] - sample["processing_fee_amt"]).sum()
            revenues.append(rev)
        lo, med, hi = np.percentile(revenues, [2.5, 50, 97.5])
        rows.append({
            "mdr_delta": delta,
            "rev_median": med,
            "rev_ci_low": lo,
            "rev_ci_high": hi,
            "rev_change_pct": (med - base_rev) / base_rev * 100,
        })

    result = pd.DataFrame(rows)
    print(result[["mdr_delta", "rev_median", "rev_change_pct"]].to_string(index=False))

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].plot(result["mdr_delta"], result["rev_median"] / 1000, marker="o", color="#1f77b4", linewidth=2)
    axes[0].fill_between(result["mdr_delta"],
                         result["rev_ci_low"]  / 1000,
                         result["rev_ci_high"] / 1000,
                         alpha=0.2, color="#1f77b4", label="95% CI")
    axes[0].axhline(base_rev / 1000, color="red", linestyle="--", linewidth=1, label=f"Base: ₹{base_rev/1000:.1f}K")
    axes[0].set_title("Net Revenue vs MDR Change\n(Monte Carlo 5000 iterations)", fontweight="bold")
    axes[0].set_xlabel("MDR Change (% points)")
    axes[0].set_ylabel("Net Revenue (₹ K)")
    axes[0].legend()

    axes[1].bar(result["mdr_delta"].round(2).astype(str),
                result["rev_change_pct"],
                color=["#2ca02c" if v >= 0 else "#d62728" for v in result["rev_change_pct"]],
                alpha=0.85)
    axes[1].axhline(0, color="black", linewidth=0.8)
    axes[1].set_title("Net Revenue Change % vs MDR Adjustment", fontweight="bold")
    axes[1].set_xlabel("MDR Change (% points)")
    axes[1].set_ylabel("Revenue Change %")

    fig.suptitle("Scenario 1: MDR Rate Sensitivity Analysis", fontsize=13, fontweight="bold")
    plt.tight_layout()
    save(fig, "01_mdr_scenario")
    return result


# ============================================================
# SCENARIO 2: CASHBACK REDUCTION
# Assumption: elasticity = -0.3 (GMV drops 0.3% per 1% cashback cut)
# You can calibrate this from cohort SQL analysis
# ============================================================
def cashback_scenario(df, base_gmv, base_rev):
    print("\n--- What-If Scenario 2: Cashback Reduction ---")

    ELASTICITY = -0.30    # domain assumption: validate from cohort A/B analysis
    reductions = np.arange(0, 61, 10)   # 0% to 60% cashback reduction
    rows = []
    for red_pct in reductions:
        revenues = []
        for _ in range(N_SIMULATIONS):
            sample = df.sample(frac=1, replace=True)
            gmv_adj       = base_gmv * (1 + ELASTICITY * (red_pct / 100) / 100 * sample["amount"].sum() / base_gmv)
            scale         = gmv_adj / base_gmv
            new_amount    = sample["amount"] * scale
            new_cashback  = sample["cashback_amt"] * (1 - red_pct / 100)
            rev = ((sample["mdr_pct"] / 100) * new_amount - new_cashback - sample["processing_fee_amt"]).sum()
            revenues.append(rev)
        lo, med, hi = np.percentile(revenues, [2.5, 50, 97.5])
        rows.append({
            "cashback_reduction_pct": red_pct,
            "rev_median":  med,
            "rev_ci_low":  lo,
            "rev_ci_high": hi,
            "rev_change_pct": (med - base_rev) / base_rev * 100,
        })

    result = pd.DataFrame(rows)
    print(result[["cashback_reduction_pct", "rev_median", "rev_change_pct"]].to_string(index=False))

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    axes[0].plot(result["cashback_reduction_pct"], result["rev_median"] / 1000,
                 marker="o", color="#ff7f0e", linewidth=2)
    axes[0].fill_between(result["cashback_reduction_pct"],
                          result["rev_ci_low"]  / 1000,
                          result["rev_ci_high"] / 1000,
                          alpha=0.2, color="#ff7f0e", label="95% CI")
    axes[0].axhline(base_rev / 1000, color="red", linestyle="--", linewidth=1, label="Base Revenue")
    axes[0].set_title("Net Revenue vs Cashback Reduction\n(elasticity assumption = -0.30)",
                       fontweight="bold")
    axes[0].set_xlabel("Cashback Reduction %")
    axes[0].set_ylabel("Net Revenue (₹ K)")
    axes[0].legend()

    axes[1].bar(result["cashback_reduction_pct"].astype(str) + "%",
                result["rev_change_pct"],
                color=["#2ca02c" if v >= 0 else "#d62728" for v in result["rev_change_pct"]],
                alpha=0.85)
    axes[1].axhline(0, color="black", linewidth=0.8)
    axes[1].set_title("Revenue Change % at Different Cashback Cuts", fontweight="bold")
    axes[1].set_xlabel("Cashback Reduction %")
    axes[1].set_ylabel("Revenue Change %")

    fig.suptitle("Scenario 2: Cashback Reduction Sensitivity", fontsize=13, fontweight="bold")
    plt.tight_layout()
    save(fig, "02_cashback_scenario")
    return result


# ============================================================
# SCENARIO 3: PROCESSING COST REDUCTION (PSP Renegotiation)
# ============================================================
def processing_cost_scenario(df, base_rev):
    print("\n--- What-If Scenario 3: Processing Cost Reduction ---")

    reductions = np.arange(0, 26, 5)    # 0% to 25% reduction
    rows = []
    for red_pct in reductions:
        revenues = []
        for _ in range(N_SIMULATIONS):
            sample = df.sample(frac=1, replace=True)
            adj_proc = sample["processing_fee_amt"] * (1 - red_pct / 100)
            rev = ((sample["mdr_pct"] / 100) * sample["amount"] - sample["cashback_amt"] - adj_proc).sum()
            revenues.append(rev)
        lo, med, hi = np.percentile(revenues, [2.5, 50, 97.5])
        rows.append({
            "processing_cut_pct": red_pct,
            "rev_median":  med,
            "rev_ci_low":  lo,
            "rev_ci_high": hi,
            "rev_change_pct": (med - base_rev) / base_rev * 100,
        })

    result = pd.DataFrame(rows)
    print(result[["processing_cut_pct", "rev_median", "rev_change_pct"]].to_string(index=False))

    fig, ax = plt.subplots(figsize=(9, 5))
    ax.plot(result["processing_cut_pct"], result["rev_median"] / 1000,
            marker="s", color="#2ca02c", linewidth=2, label="Median Revenue")
    ax.fill_between(result["processing_cut_pct"],
                    result["rev_ci_low"]  / 1000,
                    result["rev_ci_high"] / 1000,
                    alpha=0.2, color="#2ca02c", label="95% CI")
    ax.axhline(base_rev / 1000, color="red", linestyle="--", linewidth=1, label="Base Revenue")
    ax.set_title("Revenue Uplift from Processing Cost Reduction\n(PSP renegotiation scenario)",
                 fontsize=12, fontweight="bold")
    ax.set_xlabel("Processing Cost Reduction %")
    ax.set_ylabel("Net Revenue (₹ K)")
    ax.legend()
    plt.tight_layout()
    save(fig, "03_processing_cost_scenario")
    return result


# ============================================================
# SCENARIO 4: COMBINED — MDR UP + CASHBACK DOWN
# ============================================================
def combined_scenario(df, base_rev):
    print("\n--- What-If Scenario 4: Combined MDR+0.5% & Cashback-25% ---")

    rows = []
    # Grid of MDR delta × cashback reduction
    for mdr_d in [0, 0.25, 0.5]:
        for cb_r in [0, 10, 25, 50]:
            revenues = []
            for _ in range(N_SIMULATIONS // 5):
                sample = df.sample(frac=1, replace=True)
                adj_mdr  = sample["mdr_pct"] + mdr_d
                adj_cb   = sample["cashback_amt"] * (1 - cb_r / 100)
                rev = ((adj_mdr / 100) * sample["amount"] - adj_cb - sample["processing_fee_amt"]).sum()
                revenues.append(rev)
            med = np.median(revenues)
            rows.append({
                "mdr_delta": mdr_d,
                "cashback_cut": cb_r,
                "rev_median": med,
                "rev_change_pct": (med - base_rev) / base_rev * 100,
            })

    result = pd.DataFrame(rows)
    pivot  = result.pivot(index="mdr_delta", columns="cashback_cut", values="rev_change_pct")

    fig, ax = plt.subplots(figsize=(9, 5))
    sns.heatmap(pivot, ax=ax, annot=True, fmt=".1f", cmap="RdYlGn",
                center=0, cbar_kws={"label": "Revenue Change %"},
                linewidths=0.4)
    ax.set_title("Revenue Change % — MDR Increase × Cashback Cut Grid\n"
                 "(Green = Revenue Up, Red = Revenue Down)",
                 fontsize=11, fontweight="bold")
    ax.set_xlabel("Cashback Reduction %")
    ax.set_ylabel("MDR Increase (% points)")
    plt.tight_layout()
    save(fig, "04_combined_mdr_cashback_grid")

    print(pivot.to_string())
    return result


# ============================================================
# MAIN
# ============================================================
if __name__ == "__main__":
    print("=" * 60)
    print("  UPI Analytics — Monte Carlo What-If Analysis")
    print(f"  Simulations per scenario: {N_SIMULATIONS:,}")
    print("=" * 60)

    df, base_gmv, base_rev, base_margin = load_base()

    mdr_scenario(df, base_gmv, base_rev)
    cashback_scenario(df, base_gmv, base_rev)
    processing_cost_scenario(df, base_rev)
    combined_scenario(df, base_rev)

    print("\n  ✓ All What-If charts saved to outputs/whatif/")
    print("\n  KEY TAKEAWAYS:")
    print("  • Review MDR scenario chart to find revenue-maximising MDR adjustment.")
    print("  • Use cashback scenario to quantify safe reduction without GMV cannibalism.")
    print("  • Processing cost renegotiation directly improves margin with zero GMV risk.")
    print("  • Combined heatmap shows optimal operating point for MDR + cashback levers.")
