"""
============================================================
UPI TRANSACTION ANALYTICS PROJECT
FILE: 02_customer_analytics.py
PURPOSE: Cohort retention, RFM segmentation, CLV distribution,
         Churn risk funnel, DAU/MAU stickiness
============================================================
Run: python3 02_customer_analytics.py
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
import seaborn as sns
import os
import warnings

warnings.filterwarnings('ignore')
sns.set_theme(style="whitegrid")
plt.rcParams.update({'figure.dpi': 130, 'font.size': 10})
CHART_DIR = "../outputs/charts"
os.makedirs(CHART_DIR, exist_ok=True)

# ─────────────────────────────────────────
# LOAD DATA
# ─────────────────────────────────────────
DATA_DIR = "../data"
ft  = pd.read_csv(f"{DATA_DIR}/fact_transactions.csv", parse_dates=['txn_date'])
dc  = pd.read_csv(f"{DATA_DIR}/dim_customer.csv",     parse_dates=['signup_date', 'first_txn_date'])
dci = pd.read_csv(f"{DATA_DIR}/dim_city.csv")

suc = ft[ft['status'] == 'SUCCESS'].copy()
suc['net_revenue']  = (suc['mdr_pct']/100.0)*suc['amount'] - suc['cashback_amt'] - suc['processing_fee_amt']
suc['txn_month']    = suc['txn_date'].dt.to_period('M')
REF_DATE            = suc['txn_date'].max()

# ─────────────────────────────────────────
# SECTION 1: DAU / MAU STICKINESS
# ─────────────────────────────────────────
print("=" * 60)
print("SECTION 1: DAU / MAU STICKINESS")
print("=" * 60)

dau = suc.groupby('txn_date')['customer_id'].nunique().reset_index(name='dau')
dau['txn_month'] = dau['txn_date'].dt.to_period('M')
mau = suc.groupby('txn_month')['customer_id'].nunique().reset_index(name='mau')
avg_dau_per_month = dau.groupby('txn_month')['dau'].mean().reset_index(name='avg_dau')

stickiness = avg_dau_per_month.merge(mau, on='txn_month')
stickiness['stickiness_pct'] = stickiness['avg_dau'] / stickiness['mau'] * 100
stickiness['month_str'] = stickiness['txn_month'].astype(str)

print("\n Stickiness Ratio by Month (DAU/MAU %):")
print(stickiness[['month_str','avg_dau','mau','stickiness_pct']].to_string(index=False))

fig, axes = plt.subplots(1, 2, figsize=(14, 5))
fig.suptitle('User Engagement — DAU / MAU & Stickiness', fontsize=13, fontweight='bold')

axes[0].plot(stickiness['month_str'], stickiness['avg_dau'],
             marker='o', label='Avg DAU', color='steelblue', linewidth=2)
axes[0].plot(stickiness['month_str'], stickiness['mau'],
             marker='s', label='MAU', color='darkorange', linewidth=2)
axes[0].set_title('DAU vs MAU by Month')
axes[0].set_xlabel('Month')
axes[0].tick_params(axis='x', rotation=45)
axes[0].legend()
axes[0].set_ylabel('Users')

axes[1].bar(stickiness['month_str'], stickiness['stickiness_pct'],
            color='mediumseagreen', alpha=0.85)
axes[1].axhline(stickiness['stickiness_pct'].mean(), color='red',
                linestyle='--', linewidth=1.5, label=f"Avg: {stickiness['stickiness_pct'].mean():.1f}%")
axes[1].set_title('Stickiness Ratio % (DAU/MAU)')
axes[1].set_xlabel('Month')
axes[1].tick_params(axis='x', rotation=45)
axes[1].legend()
axes[1].set_ylabel('Stickiness %')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/06_dau_mau_stickiness.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 06_dau_mau_stickiness.png")

# ─────────────────────────────────────────
# SECTION 2: COHORT RETENTION (Month 1, 3, 6)
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 2: COHORT RETENTION")
print("=" * 60)

# Assign cohort = first transaction month
first_txn = suc.groupby('customer_id')['txn_month'].min().reset_index(name='cohort_month')
suc_cohort = suc.merge(first_txn, on='customer_id')

# Months since cohort start
suc_cohort['months_since_start'] = (
    suc_cohort['txn_month'].dt.start_time.dt.to_period('M').astype(int) -
    suc_cohort['cohort_month'].dt.start_time.dt.to_period('M').astype(int)
)
# Fix: use year/month offset approach
suc_cohort['months_since_start'] = (
    (suc_cohort['txn_date'].dt.year - suc_cohort['cohort_month'].apply(lambda p: p.year)) * 12 +
    (suc_cohort['txn_date'].dt.month - suc_cohort['cohort_month'].apply(lambda p: p.month))
)

cohort_size = first_txn.groupby('cohort_month').size().reset_index(name='cohort_size')

cohort_retention = (
    suc_cohort.groupby(['cohort_month', 'months_since_start'])['customer_id']
    .nunique()
    .reset_index(name='active_users')
)
cohort_retention = cohort_retention.merge(cohort_size, on='cohort_month')
cohort_retention['retention_pct'] = (
    cohort_retention['active_users'] / cohort_retention['cohort_size'] * 100
)
cohort_retention['cohort_str'] = cohort_retention['cohort_month'].astype(str)

# Pivot for heatmap (months 0–11)
pivot = cohort_retention[cohort_retention['months_since_start'] <= 11].pivot_table(
    index='cohort_str',
    columns='months_since_start',
    values='retention_pct'
)

# Average retention at months 1, 3, 6
avg_ret = cohort_retention[cohort_retention['months_since_start'].isin([1, 3, 6])].groupby(
    'months_since_start')['retention_pct'].mean()

print("\n Average Retention Across All Cohorts:")
for m, v in avg_ret.items():
    print(f"  Month {m:>2}: {v:.1f}%")

# Cohort Heatmap
fig, ax = plt.subplots(figsize=(14, 7))
mask = pivot.isnull()
sns.heatmap(pivot, annot=True, fmt='.1f', cmap='YlGnBu',
            linewidths=0.5, ax=ax, mask=mask, vmin=0, vmax=100)
ax.set_title('Cohort Retention Heatmap (%) — Month Since First Transaction',
             fontsize=13, fontweight='bold')
ax.set_xlabel('Months Since First Transaction')
ax.set_ylabel('Cohort (First Transaction Month)')
plt.tight_layout()
plt.savefig(f"{CHART_DIR}/07_cohort_retention_heatmap.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 07_cohort_retention_heatmap.png")

# ─────────────────────────────────────────
# SECTION 3: RFM SEGMENTATION
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 3: RFM SEGMENTATION")
print("=" * 60)

rfm = suc.groupby('customer_id').agg(
    last_txn_date = ('txn_date', 'max'),
    frequency     = ('transaction_id', 'count'),
    monetary      = ('amount', 'sum'),
    net_revenue   = ('net_revenue', 'sum')
).reset_index()

rfm['recency_days'] = (REF_DATE - rfm['last_txn_date']).dt.days

# Score R, F, M using NTILE(5) — percentile rank
rfm['r_score'] = pd.qcut(rfm['recency_days'], 5, labels=[5,4,3,2,1]).astype(int)
rfm['f_score'] = pd.qcut(rfm['frequency'].rank(method='first'), 5, labels=[1,2,3,4,5]).astype(int)
rfm['m_score'] = pd.qcut(rfm['monetary'].rank(method='first'), 5, labels=[1,2,3,4,5]).astype(int)
rfm['rfm_total'] = rfm['r_score'] + rfm['f_score'] + rfm['m_score']

def label_rfm(row):
    r, f, m = row['r_score'], row['f_score'], row['m_score']
    if r >= 4 and f >= 4 and m >= 4:   return 'Champions'
    elif r >= 3 and f >= 3:             return 'Loyal Users'
    elif r >= 4 and f <= 2:             return 'New Customers'
    elif r >= 3 and f <= 2:             return 'Potential Loyalists'
    elif r <= 2 and f >= 3:             return 'At Risk'
    elif r <= 2 and f <= 2 and m >= 3:  return 'Cannot Lose Them'
    elif r == 1 and f == 1:             return 'Lost Customers'
    else:                               return 'Hibernating'

rfm['rfm_segment'] = rfm.apply(label_rfm, axis=1)

rfm_summary = rfm.groupby('rfm_segment').agg(
    customer_count  = ('customer_id', 'count'),
    avg_recency     = ('recency_days', 'mean'),
    avg_frequency   = ('frequency', 'mean'),
    avg_monetary    = ('monetary', 'mean'),
    total_revenue   = ('net_revenue', 'sum')
).reset_index().sort_values('total_revenue', ascending=False)

print("\n RFM Segment Summary:")
print(rfm_summary.to_string(index=False))

# RFM chart — treemap style via bar chart
fig, axes = plt.subplots(1, 2, figsize=(14, 6))
fig.suptitle('RFM Customer Segmentation', fontsize=13, fontweight='bold')

colors = plt.cm.Set3(np.linspace(0, 1, len(rfm_summary)))
axes[0].barh(rfm_summary['rfm_segment'], rfm_summary['customer_count'], color=colors)
axes[0].set_title('Customers per RFM Segment')
axes[0].set_xlabel('Customer Count')
axes[0].invert_yaxis()

axes[1].barh(rfm_summary['rfm_segment'], rfm_summary['total_revenue'] / 1e3, color=colors)
axes[1].set_title('Net Revenue per RFM Segment (₹K)')
axes[1].set_xlabel('Net Revenue (₹ Thousands)')
axes[1].invert_yaxis()

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/08_rfm_segmentation.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 08_rfm_segmentation.png")

# ─────────────────────────────────────────
# SECTION 4: CLV DISTRIBUTION
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 4: CLV DISTRIBUTION")
print("=" * 60)

clv = suc.groupby('customer_id').agg(
    total_txns    = ('transaction_id', 'count'),
    total_gmv     = ('amount', 'sum'),
    lifetime_value= ('net_revenue', 'sum')
).reset_index()

clv = clv.merge(dc[['customer_id','segment_tag']], on='customer_id', how='left')

p25 = clv['lifetime_value'].quantile(0.25)
p50 = clv['lifetime_value'].quantile(0.50)
p75 = clv['lifetime_value'].quantile(0.75)
p90 = clv['lifetime_value'].quantile(0.90)

print(f"\n CLV Percentiles:")
print(f"  P25  : ₹{p25:,.2f}")
print(f"  P50  : ₹{p50:,.2f}  (Median)")
print(f"  P75  : ₹{p75:,.2f}")
print(f"  P90  : ₹{p90:,.2f}")
print(f"  Mean : ₹{clv['lifetime_value'].mean():,.2f}")

top10_pct_threshold = clv['lifetime_value'].quantile(0.90)
top10_pct_customers = clv[clv['lifetime_value'] >= top10_pct_threshold]
top10_pct_rev_share = top10_pct_customers['lifetime_value'].sum() / clv['lifetime_value'].sum() * 100
print(f"\n  Top 10% customers generate: {top10_pct_rev_share:.1f}% of total net revenue")

# CLV by Segment
clv_segment = clv.groupby('segment_tag').agg(
    customer_count = ('customer_id', 'count'),
    avg_clv        = ('lifetime_value', 'mean'),
    total_revenue  = ('lifetime_value', 'sum')
).reset_index()
print("\n CLV by Customer Segment:")
print(clv_segment.to_string(index=False))

fig, axes = plt.subplots(1, 2, figsize=(13, 5))
fig.suptitle('Customer Lifetime Value (CLV) Distribution', fontsize=13, fontweight='bold')

# Histogram
axes[0].hist(clv['lifetime_value'], bins=50, color='steelblue', edgecolor='white', alpha=0.85)
axes[0].axvline(p50, color='red', linestyle='--', linewidth=1.5, label=f'Median ₹{p50:.0f}')
axes[0].axvline(p90, color='green', linestyle='--', linewidth=1.5, label=f'P90 ₹{p90:.0f}')
axes[0].set_title('CLV Distribution (all customers)')
axes[0].set_xlabel('Lifetime Value (₹)')
axes[0].set_ylabel('Customer Count')
axes[0].legend()

# By segment
axes[1].bar(clv_segment['segment_tag'], clv_segment['avg_clv'],
            color=['#E74C3C','#3498DB','#2ECC71','#F39C12'])
axes[1].set_title('Average CLV by Customer Segment')
axes[1].set_xlabel('Segment')
axes[1].set_ylabel('Avg CLV (₹)')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/09_clv_distribution.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 09_clv_distribution.png")

# ─────────────────────────────────────────
# SECTION 5: CHURN RISK FUNNEL
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 5: CHURN RISK FUNNEL")
print("=" * 60)

cust_activity = suc.groupby('customer_id').agg(
    last_txn_date = ('txn_date', 'max'),
    txn_last_90d  = ('txn_date', lambda x: (x >= REF_DATE - pd.Timedelta(days=90)).sum()),
    txn_last_30d  = ('txn_date', lambda x: (x >= REF_DATE - pd.Timedelta(days=30)).sum()),
    total_txns    = ('transaction_id', 'count'),
    total_gmv     = ('amount', 'sum')
).reset_index()

cust_activity['days_inactive'] = (REF_DATE - cust_activity['last_txn_date']).dt.days

def churn_risk(row):
    if row['days_inactive'] > 60 and row['txn_last_90d'] < 2:     return 'High Risk'
    elif row['days_inactive'] > 30 and row['txn_last_90d'] < 5:   return 'Medium Risk'
    elif row['txn_last_30d'] == 0:                                 return 'Slipping Away'
    else:                                                          return 'Active'

cust_activity['churn_risk'] = cust_activity.apply(churn_risk, axis=1)

churn_summary = cust_activity.groupby('churn_risk').agg(
    customer_count = ('customer_id', 'count'),
    avg_days_inactive = ('days_inactive', 'mean'),
    at_risk_gmv    = ('total_gmv', 'sum')
).reset_index()
churn_order = ['High Risk', 'Medium Risk', 'Slipping Away', 'Active']
churn_summary['sort_order'] = churn_summary['churn_risk'].map({v:i for i,v in enumerate(churn_order)})
churn_summary = churn_summary.sort_values('sort_order')

print("\n Churn Risk Funnel:")
print(churn_summary[['churn_risk','customer_count','avg_days_inactive','at_risk_gmv']].to_string(index=False))

fig, axes = plt.subplots(1, 2, figsize=(12, 5))
fig.suptitle('Churn Risk Funnel', fontsize=13, fontweight='bold')

colors_churn = ['#E74C3C','#F39C12','#F1C40F','#2ECC71']
axes[0].bar(churn_summary['churn_risk'], churn_summary['customer_count'], color=colors_churn)
axes[0].set_title('Users by Churn Risk Tier')
axes[0].set_ylabel('Customer Count')

axes[1].bar(churn_summary['churn_risk'], churn_summary['at_risk_gmv'] / 1e6, color=colors_churn)
axes[1].set_title('At-Risk GMV by Churn Tier (₹M)')
axes[1].set_ylabel('GMV (₹ Millions)')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/10_churn_risk_funnel.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 10_churn_risk_funnel.png")

# ─────────────────────────────────────────
# SECTION 6: NEW vs RETURNING USER SPLIT
# ─────────────────────────────────────────
first_txn_month = suc.groupby('customer_id')['txn_month'].min().reset_index(name='first_month')
suc2 = suc.merge(first_txn_month, on='customer_id')
suc2['user_type'] = np.where(suc2['txn_month'] == suc2['first_month'], 'New', 'Returning')

user_type_monthly = suc2.groupby(['txn_month','user_type'])['customer_id'].nunique().unstack(fill_value=0).reset_index()
user_type_monthly['month_str'] = user_type_monthly['txn_month'].astype(str)

fig, ax = plt.subplots(figsize=(12, 5))
x = range(len(user_type_monthly))
ax.bar(x, user_type_monthly.get('New', 0), label='New Users', color='#3498DB', alpha=0.85)
ax.bar(x, user_type_monthly.get('Returning', 0), bottom=user_type_monthly.get('New', 0),
       label='Returning Users', color='#2ECC71', alpha=0.85)
ax.set_xticks(x)
ax.set_xticklabels(user_type_monthly['month_str'], rotation=45)
ax.set_title('Monthly Active Users — New vs Returning', fontsize=12, fontweight='bold')
ax.set_ylabel('Unique Users')
ax.legend()
plt.tight_layout()
plt.savefig(f"{CHART_DIR}/11_new_vs_returning_users.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 11_new_vs_returning_users.png")

# Export RFM & CLV tables for Power BI
rfm.to_csv("../outputs/rfm_segments.csv", index=False)
clv.to_csv("../outputs/clv_table.csv",    index=False)
churn_summary.to_csv("../outputs/churn_risk_funnel.csv", index=False)
print("\n  Exported: rfm_segments.csv, clv_table.csv, churn_risk_funnel.csv")

print("\n" + "=" * 60)
print("02_customer_analytics.py  ✅  COMPLETE")
print("=" * 60)
