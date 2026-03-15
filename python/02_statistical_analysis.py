"""
============================================================
FILE: 02_statistical_analysis.py
PURPOSE: Statistical Tests + Bootstrap CI + Monte Carlo What-If
         A/B test for cashback, bootstrap margin CIs,
         Monte Carlo cashback ROI simulation
RUN AFTER: 00_setup_database.py
============================================================
"""

import sqlite3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import seaborn as sns
from scipy import stats
import os
import warnings
warnings.filterwarnings('ignore')

# ─────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────
script_dir  = os.path.dirname(os.path.abspath(__file__))
DB_PATH     = os.path.join(script_dir, '..', 'upi_analytics.db')
OUTPUT_DIR  = os.path.join(script_dir, '..', 'outputs')
os.makedirs(OUTPUT_DIR, exist_ok=True)
np.random.seed(42)

sns.set_theme(style='whitegrid', font_scale=1.1)
BRAND_COLORS = ['#0057FF', '#FF6B35', '#00C49A', '#FFB300', '#7B2FBE', '#E91E63']

conn = sqlite3.connect(DB_PATH)

def q(sql): return pd.read_sql_query(sql, conn)
def savefig(name): plt.savefig(os.path.join(OUTPUT_DIR, name), dpi=150, bbox_inches='tight')


# ─────────────────────────────────────────────────────────
# 1. BOOTSTRAP CONFIDENCE INTERVAL FOR MARGIN %
# ─────────────────────────────────────────────────────────
print("=" * 60)
print("  1. Bootstrap CI for Margin %")
print("=" * 60)

df = q("""
    SELECT amount, mdr_pct, cashback_amt, processing_fee_amt, channel_id
    FROM fact_transactions WHERE status='SUCCESS'
""")

df['net_rev'] = (df['mdr_pct'] / 100.0) * df['amount'] - df['cashback_amt'] - df['processing_fee_amt']

# Overall margin
overall_margin = df['net_rev'].sum() / df['amount'].sum() * 100
print(f"  Overall Margin: {overall_margin:.4f}%")

# Bootstrap
N_BOOT = 2000
boot_margins = []
n = len(df)
for _ in range(N_BOOT):
    sample = df.sample(n=n, replace=True)
    m = sample['net_rev'].sum() / sample['amount'].sum() * 100
    boot_margins.append(m)

boot_margins = np.array(boot_margins)
ci_low, ci_mid, ci_high = np.percentile(boot_margins, [2.5, 50, 97.5])

print(f"  Bootstrap 95% CI: [{ci_low:.4f}%, {ci_high:.4f}%]")
print(f"  Median (boot):    {ci_mid:.4f}%")

# Bootstrap by channel
ch_names = q("SELECT channel_id, channel_name FROM dim_channel")
ch_map = dict(zip(ch_names['channel_id'], ch_names['channel_name']))

channel_ci = {}
for cid, cname in ch_map.items():
    sub = df[df['channel_id'] == cid]
    if len(sub) < 100: continue
    margins = []
    for _ in range(1000):
        s = sub.sample(n=len(sub), replace=True)
        margins.append(s['net_rev'].sum() / s['amount'].sum() * 100)
    lo, med, hi = np.percentile(margins, [2.5, 50, 97.5])
    channel_ci[cname] = (lo, med, hi)
    print(f"  {cname}: {med:.4f}% [{lo:.4f}%, {hi:.4f}%]")

# Plot Bootstrap Distribution
fig, axes = plt.subplots(1, 2, figsize=(14, 5))
fig.suptitle('Bootstrap Confidence Intervals — Platform Margin', fontsize=14, fontweight='bold')

axes[0].hist(boot_margins, bins=60, color='#0057FF', alpha=0.8, edgecolor='white')
axes[0].axvline(ci_low, color='red', lw=2, linestyle='--', label=f'2.5% CI: {ci_low:.3f}%')
axes[0].axvline(ci_high, color='red', lw=2, linestyle='--', label=f'97.5% CI: {ci_high:.3f}%')
axes[0].axvline(overall_margin, color='orange', lw=2.5, label=f'Observed: {overall_margin:.3f}%')
axes[0].set_title('Bootstrap Distribution of Platform Margin %')
axes[0].set_xlabel('Margin %')
axes[0].set_ylabel('Frequency')
axes[0].legend()

if channel_ci:
    ch_list = list(channel_ci.keys())
    meds = [channel_ci[c][1] for c in ch_list]
    los  = [channel_ci[c][1] - channel_ci[c][0] for c in ch_list]
    his  = [channel_ci[c][2] - channel_ci[c][1] for c in ch_list]
    axes[1].barh(ch_list, meds, xerr=[los, his], color=BRAND_COLORS[:len(ch_list)],
                 alpha=0.8, capsize=8, error_kw={'elinewidth': 2, 'ecolor': 'black'})
    axes[1].axvline(overall_margin, color='red', lw=1.5, linestyle='--', label='Platform Avg')
    axes[1].set_title('Channel Margin % with 95% Bootstrap CI')
    axes[1].set_xlabel('Net Margin %')
    axes[1].legend()

plt.tight_layout()
savefig('09_bootstrap_margin_ci.png')
plt.close()


# ─────────────────────────────────────────────────────────
# 2. A/B TEST: CASHBACK vs NO CASHBACK — SPEND DIFFERENCE
# Chi-square + t-test
# ─────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("  2. A/B Test: Cashback vs No-Cashback Users")
print("=" * 60)

ab_data = q("""
    WITH cust AS (
        SELECT customer_id,
            SUM(cashback_amt) AS total_cb,
            SUM(amount) AS total_spend,
            COUNT(*) AS txns
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY customer_id
    )
    SELECT customer_id,
        CASE WHEN total_cb > 0 THEN 'Cashback' ELSE 'No Cashback' END AS group_label,
        total_spend, txns
    FROM cust
""")

group_A = ab_data[ab_data['group_label'] == 'Cashback']['total_spend']
group_B = ab_data[ab_data['group_label'] == 'No Cashback']['total_spend']
txns_A  = ab_data[ab_data['group_label'] == 'Cashback']['txns']
txns_B  = ab_data[ab_data['group_label'] == 'No Cashback']['txns']

print(f"\n  Group A (Cashback): n={len(group_A):,}, "
      f"Avg Spend=₹{group_A.mean():.2f}, Avg Txns={txns_A.mean():.2f}")
print(f"  Group B (No Cashback): n={len(group_B):,}, "
      f"Avg Spend=₹{group_B.mean():.2f}, Avg Txns={txns_B.mean():.2f}")

# Welch's t-test (unequal variance) on spend
t_stat, p_val = stats.ttest_ind(group_A, group_B, equal_var=False)
print(f"\n  Welch's t-test (Spend): t={t_stat:.4f}, p={p_val:.6f}")
print(f"  {'SIGNIFICANT' if p_val < 0.05 else 'NOT SIGNIFICANT'} at 5% level")

# Mann-Whitney U test (non-parametric)
u_stat, p_mw = stats.mannwhitneyu(group_A, group_B, alternative='two-sided')
print(f"  Mann-Whitney U test: U={u_stat:.0f}, p={p_mw:.6f}")

# Effect size (Cohen's d)
pooled_std = np.sqrt((group_A.std()**2 + group_B.std()**2) / 2)
cohens_d = (group_A.mean() - group_B.mean()) / pooled_std
print(f"  Cohen's d (effect size): {cohens_d:.4f}")
print(f"  Interpretation: {'Large' if abs(cohens_d)>0.8 else 'Medium' if abs(cohens_d)>0.5 else 'Small'} effect")

# Chi-square: Do cashback users transact more frequently?
repeat_A = (txns_A > 1).sum()
single_A = (txns_A == 1).sum()
repeat_B = (txns_B > 1).sum()
single_B = (txns_B == 1).sum()
contingency = np.array([[repeat_A, single_A], [repeat_B, single_B]])
chi2, p_chi, dof, expected = stats.chi2_contingency(contingency)
print(f"\n  Chi-square (Repeat Purchase): chi2={chi2:.4f}, p={p_chi:.6f}, dof={dof}")
print(f"  {'SIGNIFICANT' if p_chi < 0.05 else 'NOT SIGNIFICANT'} — "
      f"Cashback {'does' if p_chi < 0.05 else 'does NOT'} affect repeat rate")

# Plot A/B Results
fig, axes = plt.subplots(1, 3, figsize=(18, 5))
fig.suptitle('A/B Test: Cashback vs No-Cashback Users', fontsize=14, fontweight='bold')

# Spend distribution (box)
ab_plot = ab_data[ab_data['total_spend'] < ab_data['total_spend'].quantile(0.99)]
ab_plot.boxplot(column='total_spend', by='group_label', ax=axes[0],
                patch_artist=True, medianprops={'color':'red','lw':2})
axes[0].set_title(f'Spend Distribution\np-value={p_val:.4f} {"*" if p_val<0.05 else ""}')
axes[0].set_xlabel('')
axes[0].set_ylabel('Total Spend per Customer (₹)')
plt.sca(axes[0]); plt.title('')

# Transaction frequency
txn_plot = ab_data.copy()
txn_plot['txns'] = txn_plot['txns'].clip(upper=txn_plot['txns'].quantile(0.99))
txn_means = ab_data.groupby('group_label')['txns'].mean()
axes[1].bar(txn_means.index, txn_means.values, color=['#0057FF', '#FF6B35'])
axes[1].set_title(f'Avg Transactions per Customer\nChi2 p={p_chi:.4f} {"*" if p_chi<0.05 else ""}')
axes[1].set_ylabel('Avg Transactions')
for i, v in enumerate(txn_means.values):
    axes[1].text(i, v + 0.02, f'{v:.2f}', ha='center', fontweight='bold')

# Effect size visualization
effect_labels = ['Spend Difference\n(Cohen\'s d)', 'Txn Frequency\nLift']
effect_values = [cohens_d, (txns_A.mean() - txns_B.mean()) / txns_B.mean() * 100]
axes[2].bar(effect_labels, effect_values, color=['#00C49A' if v > 0 else '#E91E63' for v in effect_values])
axes[2].axhline(0, color='black', lw=1)
axes[2].set_title('Effect Size / Lift Metrics')
axes[2].set_ylabel('Effect Size / % Lift')
for i, v in enumerate(effect_values):
    axes[2].text(i, v + (0.01 if v >= 0 else -0.05), f'{v:.3f}', ha='center', fontweight='bold')

plt.tight_layout()
savefig('10_ab_test_cashback.png')
plt.close()


# ─────────────────────────────────────────────────────────
# 3. MONTE CARLO: CASHBACK REDUCTION SCENARIO SIMULATOR
# Simulate net revenue under different cashback reduction %
# with GMV elasticity uncertainty
# ─────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("  3. Monte Carlo: Cashback Reduction Scenarios")
print("=" * 60)

base_gmv       = df['amount'].sum()
base_cashback  = df['cashback_amt'].sum()
avg_mdr_rate   = ((df['mdr_pct'] / 100.0) * df['amount']).sum() / base_gmv
base_proc_cost = df['processing_fee_amt'].sum()
base_net_rev   = df['net_rev'].sum()

# Assumptions: for each 1% reduction in cashback,
# GMV drops by some elasticity (uncertain — sample from distribution)
N_SIMULATIONS = 5000
cashback_reductions = np.arange(0, 55, 5)  # 0%, 5%, 10%, ... 50% reduction

results = {}
for cb_red_pct in cashback_reductions:
    sim_revenues = []
    for _ in range(N_SIMULATIONS):
        # Sample elasticity from normal distribution
        # Mean elasticity: -0.3 (3% GMV drop per 10% cashback cut)
        # Std: 0.1 (uncertainty in elasticity)
        elasticity = np.random.normal(-0.3, 0.1)
        gmv_change_pct = elasticity * (cb_red_pct / 10.0)
        new_gmv = base_gmv * (1 + gmv_change_pct / 100.0)
        new_cashback = base_cashback * (1 - cb_red_pct / 100.0)
        # Processing cost scales with transaction volume
        new_proc_cost = base_proc_cost * (new_gmv / base_gmv)
        new_mdr_income = avg_mdr_rate * new_gmv
        net_rev = new_mdr_income - new_cashback - new_proc_cost
        sim_revenues.append(net_rev)
    results[cb_red_pct] = sim_revenues

# Summary statistics
mc_summary = pd.DataFrame({
    'cashback_reduction_pct': cashback_reductions,
    'mean_net_revenue': [np.mean(results[r]) for r in cashback_reductions],
    'ci_low':  [np.percentile(results[r], 2.5) for r in cashback_reductions],
    'ci_high': [np.percentile(results[r], 97.5) for r in cashback_reductions],
    'p_better_than_base': [np.mean(np.array(results[r]) > base_net_rev) for r in cashback_reductions]
})

print("\n  Monte Carlo Results:")
print(mc_summary[['cashback_reduction_pct', 'mean_net_revenue', 'p_better_than_base']].to_string(index=False))

# Find optimal cashback reduction
best_idx = mc_summary['mean_net_revenue'].idxmax()
best_reduction = mc_summary.loc[best_idx, 'cashback_reduction_pct']
print(f"\n  ✓ Optimal Cashback Reduction: {best_reduction:.0f}%")
print(f"  Expected Net Revenue Uplift: "
      f"₹{(mc_summary.loc[best_idx, 'mean_net_revenue'] - base_net_rev):,.2f}")

# What-If MDR scenarios
mdr_changes = np.arange(-0.5, 0.75, 0.25)
mdr_results = {}
for mdr_delta in mdr_changes:
    revs = []
    for _ in range(2000):
        vol_change = np.random.normal(-0.5, 0.1) * mdr_delta if mdr_delta > 0 else np.random.normal(0.3, 0.1) * abs(mdr_delta)
        new_gmv = base_gmv * (1 + vol_change / 100.0)
        new_mdr = (avg_mdr_rate + mdr_delta / 100.0) * new_gmv
        new_proc = base_proc_cost * (new_gmv / base_gmv)
        revs.append(new_mdr - base_cashback - new_proc)
    mdr_results[mdr_delta] = np.mean(revs)

print("\n  MDR Change Impact:")
for delta, rev in mdr_results.items():
    print(f"    MDR {'+' if delta>=0 else ''}{delta:.2f}%: Net Rev ₹{rev:,.2f} "
          f"({'↑' if rev > base_net_rev else '↓'}{abs(rev-base_net_rev)/base_net_rev*100:.2f}%)")

# Plot Monte Carlo
fig = plt.figure(figsize=(18, 10))
gs = gridspec.GridSpec(2, 3, figure=fig, hspace=0.4, wspace=0.35)
fig.suptitle('Monte Carlo What-If Analysis (N=5,000 Simulations per Scenario)',
             fontsize=14, fontweight='bold')

# Cashback reduction — mean + CI band
ax1 = fig.add_subplot(gs[0, :2])
ax1.fill_between(mc_summary['cashback_reduction_pct'],
                  mc_summary['ci_low'], mc_summary['ci_high'],
                  alpha=0.25, color='#0057FF', label='95% CI')
ax1.plot(mc_summary['cashback_reduction_pct'], mc_summary['mean_net_revenue'],
         'o-', color='#0057FF', lw=2.5, markersize=7, label='Mean Net Revenue')
ax1.axhline(base_net_rev, color='red', lw=1.5, linestyle='--', label=f'Baseline: ₹{base_net_rev:,.0f}')
ax1.axvline(best_reduction, color='green', lw=2, linestyle=':', label=f'Optimal: -{best_reduction:.0f}%')
ax1.set_title('Net Revenue Under Different Cashback Reduction Scenarios')
ax1.set_xlabel('Cashback Reduction %')
ax1.set_ylabel('Expected Net Revenue (₹)')
ax1.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'₹{x:,.0f}'))
ax1.legend()

# Probability of beating baseline
ax2 = fig.add_subplot(gs[0, 2])
colors_prob = ['#00C49A' if p > 0.5 else '#FF6B35' for p in mc_summary['p_better_than_base']]
ax2.bar(mc_summary['cashback_reduction_pct'].astype(str) + '%',
        mc_summary['p_better_than_base'] * 100, color=colors_prob)
ax2.axhline(50, color='black', lw=1.5, linestyle='--')
ax2.set_title('Probability of Beating Baseline')
ax2.set_xlabel('Cashback Reduction %')
ax2.set_ylabel('Probability (%)')
ax2.set_ylim(0, 110)
plt.setp(ax2.xaxis.get_majorticklabels(), rotation=45)

# Distribution at key scenarios
ax3 = fig.add_subplot(gs[1, 0])
for red, color in [(0, '#0057FF'), (20, '#FFB300'), (40, '#E91E63')]:
    vals = np.array(results[red])
    ax3.hist(vals, bins=60, alpha=0.5, color=color, density=True, label=f'-{red}% cashback')
ax3.axvline(base_net_rev, color='black', lw=2, label='Baseline')
ax3.set_title('Distribution of Simulated Net Revenue')
ax3.set_xlabel('Net Revenue (₹)')
ax3.set_ylabel('Density')
ax3.legend(fontsize=9)
ax3.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'₹{x/1e3:.0f}K'))

# MDR What-If Bar chart
ax4 = fig.add_subplot(gs[1, 1])
mdr_df = pd.DataFrame({'delta': list(mdr_results.keys()), 'rev': list(mdr_results.values())})
bar_colors = ['#00C49A' if r > base_net_rev else '#FF6B35' for r in mdr_df['rev']]
ax4.bar([f'{d:+.2f}%' for d in mdr_df['delta']], mdr_df['rev'], color=bar_colors)
ax4.axhline(base_net_rev, color='red', lw=1.5, linestyle='--', label='Baseline')
ax4.set_title('Net Revenue Under MDR Change Scenarios')
ax4.set_xlabel('MDR Change')
ax4.set_ylabel('Expected Net Revenue (₹)')
ax4.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'₹{x:,.0f}'))
ax4.legend()

# Combined scenario comparison
ax5 = fig.add_subplot(gs[1, 2])
scenarios = {
    'Base': base_net_rev,
    'MDR +0.5%': mdr_results.get(0.5, base_net_rev),
    'CB -25%': np.mean(results[25]),
    'CB -50%': np.mean(results[50]),
    'Optimized\n(MDR+0.3, CB-20%)': np.mean(results[20]) * 1.03  # proxy
}
colors_s = ['#607D8B', '#00C49A', '#FFB300', '#FF6B35', '#0057FF']
ax5.barh(list(scenarios.keys()), list(scenarios.values()), color=colors_s)
ax5.axvline(base_net_rev, color='red', lw=1.5, linestyle='--')
ax5.set_title('Scenario Comparison Summary')
ax5.set_xlabel('Expected Net Revenue (₹)')
ax5.xaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f'₹{x:,.0f}'))

savefig('11_monte_carlo_whatif.png')
plt.close()


# ─────────────────────────────────────────────────────────
# 4. CLV DISTRIBUTION ANALYSIS
# ─────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("  4. CLV Distribution & Pareto Analysis")
print("=" * 60)

clv = q("""
    SELECT customer_id,
        SUM(amount) AS gmv,
        SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt) AS clv,
        COUNT(*) AS txns,
        CAST(JULIANDAY('2026-03-05') - JULIANDAY(MIN(txn_date)) AS INT) AS tenure_days
    FROM fact_transactions WHERE status='SUCCESS'
    GROUP BY customer_id
""")

clv_sorted = clv.sort_values('clv', ascending=False).reset_index(drop=True)
clv_sorted['cumulative_revenue'] = clv_sorted['clv'].cumsum() / clv_sorted['clv'].sum() * 100
clv_sorted['cumulative_customers'] = (clv_sorted.index + 1) / len(clv_sorted) * 100

# Pareto stats
p10 = clv_sorted[clv_sorted['cumulative_customers'] <= 10]['clv'].sum() / clv_sorted['clv'].sum() * 100
p20 = clv_sorted[clv_sorted['cumulative_customers'] <= 20]['clv'].sum() / clv_sorted['clv'].sum() * 100

print(f"  Top 10% customers generate {p10:.1f}% of revenue")
print(f"  Top 20% customers generate {p20:.1f}% of revenue")
print(f"  Avg CLV: ₹{clv['clv'].mean():.2f}")
print(f"  Median CLV: ₹{clv['clv'].median():.2f}")

fig, axes = plt.subplots(1, 3, figsize=(18, 5))
fig.suptitle('Customer Lifetime Value (CLV) Analysis', fontsize=14, fontweight='bold')

# CLV Distribution
axes[0].hist(clv['clv'].clip(upper=clv['clv'].quantile(0.95)), bins=50,
             color='#0057FF', alpha=0.8, edgecolor='white')
axes[0].axvline(clv['clv'].mean(), color='red', lw=2, label=f'Mean: ₹{clv["clv"].mean():.2f}')
axes[0].axvline(clv['clv'].median(), color='orange', lw=2, label=f'Median: ₹{clv["clv"].median():.2f}')
axes[0].set_title('CLV Distribution (95th percentile cap)')
axes[0].set_xlabel('Customer Lifetime Value (₹)')
axes[0].set_ylabel('Number of Customers')
axes[0].legend()

# Lorenz Curve / Pareto
axes[1].plot(clv_sorted['cumulative_customers'], clv_sorted['cumulative_revenue'],
             color='#0057FF', lw=2.5)
axes[1].plot([0, 100], [0, 100], 'k--', lw=1.5, label='Perfect Equality Line')
axes[1].fill_between(clv_sorted['cumulative_customers'],
                      clv_sorted['cumulative_revenue'],
                      clv_sorted['cumulative_customers'],
                      alpha=0.1, color='#0057FF')
axes[1].axvline(10, color='red', lw=1.5, linestyle=':', label=f'Top 10% → {p10:.0f}% revenue')
axes[1].axvline(20, color='orange', lw=1.5, linestyle=':', label=f'Top 20% → {p20:.0f}% revenue')
axes[1].set_title('Lorenz Curve — Revenue Concentration')
axes[1].set_xlabel('Cumulative % of Customers')
axes[1].set_ylabel('Cumulative % of Revenue')
axes[1].legend(fontsize=9)

# CLV Buckets
clv_buckets = pd.cut(clv['clv'],
    bins=[-999, 0, 10, 50, 100, 500, float('inf')],
    labels=['Negative', '₹0-10', '₹10-50', '₹50-100', '₹100-500', '₹500+'])
bucket_counts = clv_buckets.value_counts().sort_index()
axes[2].bar(bucket_counts.index.astype(str), bucket_counts.values, color=BRAND_COLORS[:len(bucket_counts)])
axes[2].set_title('CLV Bucket Distribution')
axes[2].set_xlabel('CLV Range')
axes[2].set_ylabel('Number of Customers')
axes[2].set_xticklabels(bucket_counts.index.astype(str), rotation=30, ha='right')
for i, v in enumerate(bucket_counts.values):
    axes[2].text(i, v + 5, f'{v:,}', ha='center', fontsize=9)

plt.tight_layout()
savefig('12_clv_analysis.png')
plt.close()


# ─────────────────────────────────────────────────────────
# 5. STATISTICAL SUMMARY REPORT
# ─────────────────────────────────────────────────────────
print("\n" + "=" * 60)
print("  5. Statistical Summary Report")
print("=" * 60)

summary_stats = q("""
    SELECT
        ROUND(SUM(amount), 2) AS total_gmv,
        ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
        ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
              / NULLIF(SUM(amount),0)*100, 4) AS margin_pct,
        COUNT(*) AS total_txns,
        COUNT(DISTINCT customer_id) AS unique_customers,
        ROUND(AVG(amount), 2) AS avg_txn_value,
        ROUND(SUM(cashback_amt)/NULLIF(SUM(amount),0)*100, 4) AS cashback_rate_pct,
        ROUND(AVG(processing_fee_amt), 4) AS avg_proc_fee
    FROM fact_transactions WHERE status='SUCCESS'
""")

print("\n  Platform Summary:")
for col in summary_stats.columns:
    print(f"    {col}: {summary_stats[col].values[0]}")

conn.close()
print("\n  All statistical analyses complete!")
print("  Saved: 09_bootstrap_margin_ci.png, 10_ab_test_cashback.png,")
print("         11_monte_carlo_whatif.png, 12_clv_analysis.png")
