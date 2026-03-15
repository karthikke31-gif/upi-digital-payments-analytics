"""
============================================================
UPI TRANSACTION ANALYTICS PROJECT
FILE: 03_statistical_analysis.py
PURPOSE: Bootstrap Confidence Intervals, A/B Test Analysis
         (cashback impact), Monte Carlo What-If simulations
         — ZERO ML, ZERO AI — pure statistics
============================================================
Run: python3 03_statistical_analysis.py
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import seaborn as sns
from scipy import stats
import os
import warnings

warnings.filterwarnings('ignore')
sns.set_theme(style="whitegrid")
plt.rcParams.update({'figure.dpi': 130, 'font.size': 10})
np.random.seed(42)
CHART_DIR = "../outputs/charts"
os.makedirs(CHART_DIR, exist_ok=True)

# ─────────────────────────────────────────
# LOAD DATA
# ─────────────────────────────────────────
DATA_DIR = "../data"
ft  = pd.read_csv(f"{DATA_DIR}/fact_transactions.csv", parse_dates=['txn_date'])
dch = pd.read_csv(f"{DATA_DIR}/dim_channel.csv")

suc = ft[ft['status'] == 'SUCCESS'].copy()
suc['net_revenue'] = (suc['mdr_pct']/100.0)*suc['amount'] - suc['cashback_amt'] - suc['processing_fee_amt']
suc_ch = suc.merge(dch, on='channel_id', how='left')

# ─────────────────────────────────────────
# SECTION 1: BOOTSTRAP CONFIDENCE INTERVALS
# Purpose: Measure uncertainty in key metrics
# ─────────────────────────────────────────
print("=" * 60)
print("SECTION 1: BOOTSTRAP CONFIDENCE INTERVALS")
print("=" * 60)

def bootstrap_ci(data_series, stat_func=np.mean, n_boot=2000, ci=95):
    """Compute bootstrap confidence interval for a statistic."""
    boot_stats = []
    n = len(data_series)
    arr = data_series.values
    for _ in range(n_boot):
        sample = arr[np.random.randint(0, n, n)]
        boot_stats.append(stat_func(sample))
    alpha = (100 - ci) / 2
    return (
        np.percentile(boot_stats, alpha),
        np.percentile(boot_stats, 50),
        np.percentile(boot_stats, 100 - alpha)
    )

# 1a. Bootstrap CI for platform margin %
def margin_pct(df_arr):
    """df_arr = array of [net_rev, amount] pairs; returns margin %"""
    return df_arr[:, 0].sum() / df_arr[:, 1].sum() * 100

suc_arr = suc[['net_revenue', 'amount']].values
boot_margins = []
n = len(suc_arr)
for _ in range(2000):
    idx = np.random.randint(0, n, n)
    s = suc_arr[idx]
    boot_margins.append(s[:, 0].sum() / s[:, 1].sum() * 100)

margin_ci = (np.percentile(boot_margins, 2.5),
             np.percentile(boot_margins, 50),
             np.percentile(boot_margins, 97.5))

print(f"\n Bootstrap CI for Platform Margin % (95%, n=2000 iterations):")
print(f"  Lower  : {margin_ci[0]:.4f}%")
print(f"  Median : {margin_ci[1]:.4f}%")
print(f"  Upper  : {margin_ci[2]:.4f}%")
print(f"  Observed: {suc['net_revenue'].sum() / suc['amount'].sum() * 100:.4f}%")

# 1b. Bootstrap CI for Avg Transaction Value
lower, med, upper = bootstrap_ci(suc['amount'], stat_func=np.mean, n_boot=2000)
print(f"\n Bootstrap CI for Avg Transaction Value (95%):")
print(f"  [{lower:.2f}, {med:.2f}, {upper:.2f}]")
print(f"  Observed mean: ₹{suc['amount'].mean():.2f}")

# 1c. Bootstrap CI by Channel
print(f"\n Bootstrap CI for Margin % by Channel:")
for ch_name, grp in suc_ch.groupby('channel_name'):
    arr = grp[['net_revenue','amount']].values
    boots = []
    ng = len(arr)
    for _ in range(1000):
        idx = np.random.randint(0, ng, ng)
        s = arr[idx]
        boots.append(s[:,0].sum() / s[:,1].sum() * 100)
    lo, hi = np.percentile(boots, [2.5, 97.5])
    obs = grp['net_revenue'].sum() / grp['amount'].sum() * 100
    print(f"  {ch_name:<12}: {obs:.4f}%  CI=({lo:.4f}%, {hi:.4f}%)")

# Bootstrap Margin Distribution Plot
fig, axes = plt.subplots(1, 2, figsize=(13, 5))
fig.suptitle('Bootstrap Confidence Intervals', fontsize=13, fontweight='bold')

axes[0].hist(boot_margins, bins=60, color='steelblue', edgecolor='white', alpha=0.8)
axes[0].axvline(margin_ci[0], color='red', linestyle='--', linewidth=1.5, label='2.5th pct')
axes[0].axvline(margin_ci[2], color='red', linestyle='--', linewidth=1.5, label='97.5th pct')
axes[0].axvline(margin_ci[1], color='darkgreen', linestyle='-', linewidth=2, label='Median')
axes[0].set_title('Bootstrap Distribution — Margin %')
axes[0].set_xlabel('Margin %')
axes[0].set_ylabel('Frequency')
axes[0].legend()

# Per-channel CI bar chart
channel_ci_data = []
for ch_name, grp in suc_ch.groupby('channel_name'):
    arr = grp[['net_revenue','amount']].values
    boots = []
    ng = len(arr)
    for _ in range(1000):
        idx = np.random.randint(0, ng, ng)
        s = arr[idx]
        boots.append(s[:,0].sum() / s[:,1].sum() * 100)
    obs = grp['net_revenue'].sum() / grp['amount'].sum() * 100
    lo, hi = np.percentile(boots, [2.5, 97.5])
    channel_ci_data.append({'channel': ch_name, 'observed': obs, 'lo': lo, 'hi': hi})

ci_df = pd.DataFrame(channel_ci_data)
axes[1].bar(ci_df['channel'], ci_df['observed'], color='mediumseagreen', alpha=0.85, label='Observed')
axes[1].errorbar(ci_df['channel'],
                 ci_df['observed'],
                 yerr=[ci_df['observed'] - ci_df['lo'], ci_df['hi'] - ci_df['observed']],
                 fmt='none', color='black', capsize=5, linewidth=2, label='95% CI')
axes[1].set_title('Margin % by Channel with 95% CI')
axes[1].set_ylabel('Margin %')
axes[1].legend()

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/12_bootstrap_ci.png", bbox_inches='tight')
plt.close()
print(f"\n  Chart saved: 12_bootstrap_ci.png")


# ─────────────────────────────────────────
# SECTION 2: A/B TEST — CASHBACK IMPACT ON REPEAT RATE
# Setup: Group A = no cashback txns, Group B = cashback txns
# Question: Does cashback significantly increase repeat transactions?
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 2: A/B TEST — CASHBACK vs NO CASHBACK")
print("=" * 60)

# Label each customer as "cashback received" or not in a given month
# Using month 2025-06 to 2025-09 as observation window
obs_window = suc[suc['txn_date'].between('2025-06-01', '2025-09-30')].copy()
obs_window['txn_month'] = obs_window['txn_date'].dt.to_period('M')

# Define group: any cashback > 0 in first observed month = "treated"
first_month_txns = obs_window[obs_window['txn_month'] == obs_window['txn_month'].min()]
cashback_customers = set(first_month_txns[first_month_txns['cashback_amt'] > 0]['customer_id'])
no_cashback_customers = set(first_month_txns[first_month_txns['cashback_amt'] == 0]['customer_id'])

print(f"\n Group sizes:")
print(f"  Cashback Group (B)    : {len(cashback_customers):,} customers")
print(f"  No Cashback Group (A) : {len(no_cashback_customers):,} customers")

# Count repeat transactions in subsequent months
subsequent = obs_window[obs_window['txn_month'] > obs_window['txn_month'].min()]

def repeat_rate(cust_set):
    """% of customers who made a txn in subsequent months"""
    subsequent_customers = set(subsequent['customer_id'])
    repeaters = cust_set & subsequent_customers
    return len(repeaters) / len(cust_set) * 100 if cust_set else 0

repeat_b = repeat_rate(cashback_customers)     # Cashback group
repeat_a = repeat_rate(no_cashback_customers)  # No cashback group

print(f"\n Repeat Rate:")
print(f"  Group A (No Cashback) : {repeat_a:.2f}%")
print(f"  Group B (Cashback)    : {repeat_b:.2f}%")
print(f"  Lift                  : {repeat_b - repeat_a:.2f} percentage points")

# Chi-square test (binary: repeated or not)
repeaters_b = len(cashback_customers & set(subsequent['customer_id']))
non_repeaters_b = len(cashback_customers) - repeaters_b
repeaters_a = len(no_cashback_customers & set(subsequent['customer_id']))
non_repeaters_a = len(no_cashback_customers) - repeaters_a

contingency = np.array([[repeaters_a, non_repeaters_a],
                         [repeaters_b, non_repeaters_b]])
chi2, p_val, dof, expected = stats.chi2_contingency(contingency)

print(f"\n Chi-Square Test Result:")
print(f"  χ² statistic : {chi2:.4f}")
print(f"  p-value      : {p_val:.6f}")
print(f"  Degrees of Freedom : {dof}")
if p_val < 0.05:
    print(f"  ✅ SIGNIFICANT — Cashback has a statistically significant effect on repeat rate (α=0.05)")
else:
    print(f"  ⚠️  NOT SIGNIFICANT — Cashback effect not statistically confirmed (α=0.05)")

# Also: t-test on average transaction amounts
grp_b_amounts = obs_window[obs_window['customer_id'].isin(cashback_customers)]['amount']
grp_a_amounts = obs_window[obs_window['customer_id'].isin(no_cashback_customers)]['amount']
t_stat, t_pval = stats.ttest_ind(grp_b_amounts, grp_a_amounts, equal_var=False)  # Welch's t-test

print(f"\n Welch's t-Test on Avg Transaction Amount:")
print(f"  Group A (no cashback) avg: ₹{grp_a_amounts.mean():.2f}")
print(f"  Group B (cashback) avg   : ₹{grp_b_amounts.mean():.2f}")
print(f"  t-statistic: {t_stat:.4f},  p-value: {t_pval:.6f}")
if t_pval < 0.05:
    print(f"  ✅ SIGNIFICANT — Cashback group has significantly different avg transaction amount")
else:
    print(f"  ⚠️  NOT SIGNIFICANT — No meaningful difference in avg transaction amounts")

# A/B Chart
fig, axes = plt.subplots(1, 2, figsize=(12, 5))
fig.suptitle('A/B Test — Cashback Impact Analysis', fontsize=13, fontweight='bold')

axes[0].bar(['No Cashback (A)', 'Cashback (B)'], [repeat_a, repeat_b],
            color=['#95A5A6', '#3498DB'], alpha=0.85, edgecolor='white', linewidth=1.2)
axes[0].set_title(f'Repeat Rate Comparison\n(p-value={p_val:.4f})')
axes[0].set_ylabel('Repeat Rate %')
for i, v in enumerate([repeat_a, repeat_b]):
    axes[0].text(i, v + 0.5, f'{v:.1f}%', ha='center', fontweight='bold')

axes[1].hist(grp_a_amounts, bins=40, alpha=0.6, label='No Cashback (A)', color='#95A5A6')
axes[1].hist(grp_b_amounts, bins=40, alpha=0.6, label='Cashback (B)',    color='#3498DB')
axes[1].axvline(grp_a_amounts.mean(), color='#7F8C8D', linestyle='--', linewidth=2)
axes[1].axvline(grp_b_amounts.mean(), color='#2980B9', linestyle='--', linewidth=2)
axes[1].set_title('Transaction Amount Distribution by Group')
axes[1].set_xlabel('Transaction Amount (₹)')
axes[1].legend()

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/13_ab_test_cashback.png", bbox_inches='tight')
plt.close()
print(f"\n  Chart saved: 13_ab_test_cashback.png")


# ─────────────────────────────────────────
# SECTION 3: MONTE CARLO WHAT-IF SIMULATION
# Simulates cashback reduction scenarios (0% to -50%)
# to find the optimal cashback level
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 3: MONTE CARLO WHAT-IF SIMULATION")
print("=" * 60)

base_gmv           = suc['amount'].sum()
base_cashback      = suc['cashback_amt'].sum()
base_processing    = suc['processing_fee_amt'].sum()
gross_mdr_revenue  = ((suc['mdr_pct']/100.0) * suc['amount']).sum()
base_net_revenue   = suc['net_revenue'].sum()
base_margin_pct    = base_net_revenue / base_gmv * 100

print(f"\n Base Metrics:")
print(f"  GMV             : ₹{base_gmv:,.2f}")
print(f"  Cashback        : ₹{base_cashback:,.2f}")
print(f"  Net Revenue     : ₹{base_net_revenue:,.2f}")
print(f"  Margin %        : {base_margin_pct:.4f}%")

# Elasticity assumption:
# For every 1% reduction in cashback rate, GMV drops by ~0.3%
# (conservative estimate — no ML; based on industry benchmarks)
ELASTICITY = -0.003   # GMV drops 0.3% per 1% cashback absolute reduction

# Monte Carlo: add uncertainty in elasticity
N_SIMULATIONS = 5000
cashback_reductions = list(range(0, 55, 5))   # 0% to 50% reduction scenarios

print(f"\n Monte Carlo Results (N={N_SIMULATIONS:,} simulations per scenario):")
print(f"  {'Reduction%':<15} {'Proj GMV ₹':>15} {'Proj Net Rev ₹':>18} {'New Margin%':>14} {'Revenue Uplift ₹':>18}")
print(f"  {'-'*80}")

scenario_results = []
for reduction_pct in cashback_reductions:
    sim_net_revenues = []
    for _ in range(N_SIMULATIONS):
        # Elasticity with random noise (±30% uncertainty around assumed elasticity)
        elas_noise = ELASTICITY * (1 + np.random.uniform(-0.30, 0.30))
        gmv_change_pct = elas_noise * reduction_pct
        proj_gmv = base_gmv * (1 + gmv_change_pct)
        # MDR revenue scales with GMV
        proj_mdr_revenue = gross_mdr_revenue * (proj_gmv / base_gmv)
        # Cashback cost reduces by reduction_pct
        proj_cashback = base_cashback * (1 - reduction_pct / 100.0)
        # Processing cost scales with GMV
        proj_processing = base_processing * (proj_gmv / base_gmv)
        proj_net_revenue = proj_mdr_revenue - proj_cashback - proj_processing
        sim_net_revenues.append(proj_net_revenue)

    sim_arr = np.array(sim_net_revenues)
    mean_nr = sim_arr.mean()
    proj_gmv_mean = base_gmv * (1 + ELASTICITY * reduction_pct)
    mean_margin = mean_nr / proj_gmv_mean * 100
    uplift = mean_nr - base_net_revenue

    scenario_results.append({
        'reduction_pct':    reduction_pct,
        'proj_gmv':         proj_gmv_mean,
        'proj_net_revenue': mean_nr,
        'new_margin_pct':   mean_margin,
        'revenue_uplift':   uplift,
        'ci_lower':         np.percentile(sim_arr, 5),
        'ci_upper':         np.percentile(sim_arr, 95),
    })
    print(f"  {reduction_pct:>4}%         ₹{proj_gmv_mean:>14,.0f}  ₹{mean_nr:>17,.0f}  {mean_margin:>13.4f}%  ₹{uplift:>17,.0f}")

sim_df = pd.DataFrame(scenario_results)

# Monte Carlo Chart
fig, axes = plt.subplots(1, 3, figsize=(15, 5))
fig.suptitle('Monte Carlo What-If: Cashback Reduction Impact', fontsize=13, fontweight='bold')

axes[0].plot(sim_df['reduction_pct'], sim_df['proj_net_revenue'] / 1e6,
             marker='o', color='steelblue', linewidth=2, label='Mean Net Revenue')
axes[0].fill_between(sim_df['reduction_pct'],
                     sim_df['ci_lower'] / 1e6, sim_df['ci_upper'] / 1e6,
                     alpha=0.25, color='steelblue', label='90% CI')
axes[0].axhline(base_net_revenue / 1e6, color='red', linestyle='--', linewidth=1.5, label='Current')
axes[0].set_title('Projected Net Revenue')
axes[0].set_xlabel('Cashback Reduction %')
axes[0].set_ylabel('Net Revenue (₹ Millions)')
axes[0].legend()

axes[1].plot(sim_df['reduction_pct'], sim_df['new_margin_pct'],
             marker='s', color='green', linewidth=2)
axes[1].axhline(base_margin_pct, color='red', linestyle='--', linewidth=1.5, label='Current')
axes[1].set_title('Projected Margin %')
axes[1].set_xlabel('Cashback Reduction %')
axes[1].set_ylabel('Margin %')
axes[1].legend()

colors_uplift = ['green' if x > 0 else 'red' for x in sim_df['revenue_uplift']]
axes[2].bar(sim_df['reduction_pct'], sim_df['revenue_uplift'] / 1e3,
            color=colors_uplift, alpha=0.85)
axes[2].axhline(0, color='black', linewidth=0.8)
axes[2].set_title('Revenue Uplift vs Base (₹K)')
axes[2].set_xlabel('Cashback Reduction %')
axes[2].set_ylabel('Uplift (₹ Thousands)')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/14_monte_carlo_whatif.png", bbox_inches='tight')
plt.close()
print(f"\n  Chart saved: 14_monte_carlo_whatif.png")


# ─────────────────────────────────────────
# SECTION 4: MDR INCREASE SCENARIO
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 4: MDR INCREASE SCENARIO (+0.1% to +1.0%)")
print("=" * 60)

mdr_scenarios = [i * 0.1 for i in range(0, 11)]
mdr_results = []
for mdr_increase in mdr_scenarios:
    additional_revenue = base_gmv * (mdr_increase / 100.0)
    new_net_revenue    = base_net_revenue + additional_revenue
    new_margin_pct     = new_net_revenue / base_gmv * 100
    mdr_results.append({
        'mdr_increase_pct': mdr_increase,
        'new_net_revenue':  new_net_revenue,
        'new_margin_pct':   new_margin_pct,
        'uplift':           additional_revenue
    })
    print(f"  MDR +{mdr_increase:.1f}% → Net Revenue: ₹{new_net_revenue:,.2f}  "
          f"Margin: {new_margin_pct:.4f}%  Uplift: ₹{additional_revenue:,.2f}")

mdr_df = pd.DataFrame(mdr_results)
mdr_df.to_csv("../outputs/mdr_scenario_results.csv", index=False)
sim_df.to_csv("../outputs/cashback_scenario_results.csv", index=False)


# ─────────────────────────────────────────
# SECTION 5: STATISTICAL DISTRIBUTION TESTS
# Test if transaction amounts follow known distributions
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 5: DESCRIPTIVE STATISTICS & NORMALITY TEST")
print("=" * 60)

amounts = suc['amount']
print(f"\n Transaction Amount Statistics:")
print(f"  Mean   : ₹{amounts.mean():.2f}")
print(f"  Median : ₹{amounts.median():.2f}")
print(f"  Std    : ₹{amounts.std():.2f}")
print(f"  Skew   : {amounts.skew():.4f}")
print(f"  Kurt   : {amounts.kurt():.4f}")
print(f"  Min    : ₹{amounts.min():.2f}")
print(f"  Max    : ₹{amounts.max():.2f}")

# Shapiro-Wilk on sample (max 5000 for efficiency)
sample = amounts.sample(min(5000, len(amounts)), random_state=42)
stat_sw, p_sw = stats.shapiro(sample)
print(f"\n Shapiro-Wilk Normality Test (sample n={len(sample)}):")
print(f"  Statistic: {stat_sw:.6f},  p-value: {p_sw:.6f}")
if p_sw < 0.05:
    print("  ❌ Transaction amounts are NOT normally distributed (expected — right-skewed in payments)")
else:
    print("  ✅ Cannot reject normality")

# Percentile table
pcts = [10, 25, 50, 75, 90, 95, 99]
print(f"\n Amount Percentile Table:")
for p in pcts:
    print(f"  P{p:<3}: ₹{np.percentile(amounts, p):.2f}")

print("\n" + "=" * 60)
print("03_statistical_analysis.py  ✅  COMPLETE")
print(f"Outputs saved to ../outputs/")
print("=" * 60)
