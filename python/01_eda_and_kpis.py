"""
============================================================
UPI TRANSACTION ANALYTICS PROJECT
FILE: 01_eda_and_kpis.py
PURPOSE: Data loading, EDA, core KPI calculation,
         visualizations for all platform metrics
============================================================
Run: python3 01_eda_and_kpis.py
Outputs: saves charts to ../outputs/charts/
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
import warnings
import os

warnings.filterwarnings('ignore')

# ── Style config ───────────────────────────────────────────
sns.set_theme(style="whitegrid", palette="muted")
plt.rcParams.update({'figure.dpi': 130, 'font.size': 10, 'axes.titlesize': 12})
CHART_DIR = "../outputs/charts"
os.makedirs(CHART_DIR, exist_ok=True)

# ─────────────────────────────────────────
# SECTION 1: LOAD DATA
# ─────────────────────────────────────────
print("=" * 60)
print("SECTION 1: LOADING DATA")
print("=" * 60)

DATA_DIR = "../data"
ft  = pd.read_csv(f"{DATA_DIR}/fact_transactions.csv", parse_dates=['txn_date', 'txn_ts', 'settlement_date'])
dc  = pd.read_csv(f"{DATA_DIR}/dim_customer.csv",     parse_dates=['signup_date', 'first_txn_date'])
dm  = pd.read_csv(f"{DATA_DIR}/dim_merchant.csv")
dch = pd.read_csv(f"{DATA_DIR}/dim_channel.csv")
dci = pd.read_csv(f"{DATA_DIR}/dim_city.csv")
dd  = pd.read_csv(f"{DATA_DIR}/dim_date.csv",         parse_dates=['date'])

print(f"fact_transactions : {ft.shape[0]:,} rows × {ft.shape[1]} cols")
print(f"dim_customer      : {dc.shape[0]:,} rows")
print(f"dim_merchant      : {dm.shape[0]:,} rows")
print(f"dim_channel       : {dch.shape[0]:,} rows")
print(f"dim_city          : {dci.shape[0]:,} rows")
print(f"dim_date          : {dd.shape[0]:,} rows")

# ─────────────────────────────────────────
# SECTION 2: DATA QUALITY SUMMARY
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 2: DATA QUALITY CHECKS")
print("=" * 60)

suc = ft[ft['status'] == 'SUCCESS'].copy()

print(f"\n Status Distribution:")
print(ft['status'].value_counts(normalize=True).mul(100).round(2).to_string())

print(f"\n Null counts in fact_transactions:")
print(ft.isnull().sum()[ft.isnull().sum() > 0])

print(f"\n Date range: {ft['txn_date'].min().date()} → {ft['txn_date'].max().date()}")
print(f" Unique customers : {ft['customer_id'].nunique():,}")
print(f" Unique merchants : {ft['merchant_id'].nunique():,}")
print(f" Negative amounts : {(ft['amount'] <= 0).sum()}")
print(f" MDR out of range : {((ft['mdr_pct'] < 0) | (ft['mdr_pct'] > 5)).sum()}")

# ─────────────────────────────────────────
# SECTION 3: COMPUTE DERIVED COLUMNS
# ─────────────────────────────────────────
suc['mdr_revenue']   = (suc['mdr_pct'] / 100.0) * suc['amount']
suc['net_revenue']   = suc['mdr_revenue'] - suc['cashback_amt'] - suc['processing_fee_amt']
suc['txn_month']     = suc['txn_date'].dt.to_period('M')

# Join dims for enriched analysis
suc_ch = suc.merge(dch, on='channel_id', how='left')
suc_ci = suc.merge(dci, on='city_id',    how='left')
suc_m  = suc.merge(dm,  on='merchant_id',how='left')
suc_cu = suc.merge(dc,  on='customer_id',how='left')

# ─────────────────────────────────────────
# SECTION 4: CORE KPIs
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 4: CORE KPIs (PLATFORM LEVEL)")
print("=" * 60)

total_gmv        = suc['amount'].sum()
total_mdr_rev    = suc['mdr_revenue'].sum()
total_cashback   = suc['cashback_amt'].sum()
total_proc_cost  = suc['processing_fee_amt'].sum()
total_net_rev    = suc['net_revenue'].sum()
margin_pct       = total_net_rev / total_gmv * 100
total_txns       = len(suc)
unique_customers = suc['customer_id'].nunique()
avg_txn_value    = suc['amount'].mean()
success_rate     = len(suc) / len(ft) * 100

print(f"\n  Total GMV             : ₹{total_gmv:>15,.2f}")
print(f"  Gross MDR Revenue     : ₹{total_mdr_rev:>15,.2f}")
print(f"  Total Cashback Spent  : ₹{total_cashback:>15,.2f}")
print(f"  Total Processing Cost : ₹{total_proc_cost:>15,.2f}")
print(f"  Net Revenue           : ₹{total_net_rev:>15,.2f}")
print(f"  Margin %              : {margin_pct:>15.4f}%")
print(f"  Total Txns (Success)  : {total_txns:>15,}")
print(f"  Unique Customers      : {unique_customers:>15,}")
print(f"  Avg Transaction Value : ₹{avg_txn_value:>15,.2f}")
print(f"  Success Rate          : {success_rate:>15.2f}%")
print(f"  Avg Processing Fee    : ₹{suc['processing_fee_amt'].mean():>15.4f}")

# ─────────────────────────────────────────
# SECTION 5: MONTHLY TREND — GMV, Revenue, MAU, MoM Growth
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 5: MONTHLY TRENDS & MoM GROWTH")
print("=" * 60)

monthly = suc.groupby('txn_month').agg(
    txn_count       = ('transaction_id', 'count'),
    gmv             = ('amount', 'sum'),
    net_revenue     = ('net_revenue', 'sum'),
    mau             = ('customer_id', 'nunique'),
    cashback_spent  = ('cashback_amt', 'sum'),
    processing_cost = ('processing_fee_amt', 'sum')
).reset_index()

monthly['margin_pct']           = monthly['net_revenue'] / monthly['gmv'] * 100
monthly['gmv_mom_growth_pct']   = monthly['gmv'].pct_change() * 100
monthly['rev_mom_growth_pct']   = monthly['net_revenue'].pct_change() * 100
monthly['mau_mom_growth_pct']   = monthly['mau'].pct_change() * 100
monthly['txn_month_str']        = monthly['txn_month'].astype(str)

print("\n Monthly Performance Table:")
print(monthly[['txn_month_str','gmv','net_revenue','margin_pct','mau',
               'gmv_mom_growth_pct','rev_mom_growth_pct']].to_string(index=False))

# ─────────────────────────────────────────
# CHART 1: GMV & Net Revenue Monthly Trend
# ─────────────────────────────────────────
fig, axes = plt.subplots(2, 2, figsize=(14, 9))
fig.suptitle('UPI Platform — Executive KPI Dashboard', fontsize=14, fontweight='bold')

months = monthly['txn_month_str']
ax = axes[0, 0]
ax.bar(months, monthly['gmv'] / 1e6, color='steelblue', alpha=0.8, label='GMV (₹M)')
ax2 = ax.twinx()
ax2.plot(months, monthly['net_revenue'] / 1e3, color='darkorange', marker='o', linewidth=2, label='Net Revenue (₹K)')
ax.set_title('Monthly GMV vs Net Revenue')
ax.set_xlabel('Month'); ax.set_ylabel('GMV (₹ Millions)')
ax2.set_ylabel('Net Revenue (₹ Thousands)')
ax.tick_params(axis='x', rotation=45)
ax.legend(loc='upper left'); ax2.legend(loc='upper right')

ax = axes[0, 1]
colors = ['green' if x >= 0 else 'red' for x in monthly['gmv_mom_growth_pct'].fillna(0)]
ax.bar(months, monthly['gmv_mom_growth_pct'].fillna(0), color=colors, alpha=0.8)
ax.axhline(0, color='black', linewidth=0.8)
ax.set_title('MoM GMV Growth %')
ax.set_xlabel('Month'); ax.set_ylabel('Growth %')
ax.tick_params(axis='x', rotation=45)

ax = axes[1, 0]
ax.plot(months, monthly['mau'], marker='s', color='purple', linewidth=2, markersize=5)
ax.fill_between(range(len(months)), monthly['mau'], alpha=0.15, color='purple')
ax.set_title('Monthly Active Users (MAU)')
ax.set_xlabel('Month'); ax.set_ylabel('Unique Users')
ax.set_xticks(range(len(months))); ax.set_xticklabels(months, rotation=45)

ax = axes[1, 1]
ax.plot(months, monthly['margin_pct'], marker='^', color='teal', linewidth=2)
ax.fill_between(range(len(months)), monthly['margin_pct'], alpha=0.15, color='teal')
ax.set_title('Margin % by Month')
ax.set_xlabel('Month'); ax.set_ylabel('Margin %')
ax.set_xticks(range(len(months))); ax.set_xticklabels(months, rotation=45)

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/01_executive_kpi_trend.png", bbox_inches='tight')
plt.close()
print(f"\n  Chart saved: 01_executive_kpi_trend.png")

# ─────────────────────────────────────────
# SECTION 6: CHANNEL ANALYSIS
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 6: CHANNEL ANALYSIS")
print("=" * 60)

channel = suc_ch.groupby('channel_name').agg(
    txn_count   = ('transaction_id', 'count'),
    gmv         = ('amount', 'sum'),
    net_revenue = ('net_revenue', 'sum'),
    cashback    = ('cashback_amt', 'sum'),
    proc_cost   = ('processing_fee_amt', 'sum'),
    unique_users= ('customer_id', 'nunique')
).reset_index()

channel['margin_pct']        = channel['net_revenue'] / channel['gmv'] * 100
channel['efficiency_ratio']  = channel['net_revenue'] / (channel['cashback'] + channel['proc_cost'])
channel['gmv_share_pct']     = channel['gmv'] / channel['gmv'].sum() * 100

print("\n Channel Performance:")
print(channel[['channel_name','gmv','net_revenue','margin_pct','efficiency_ratio','gmv_share_pct']].to_string(index=False))

# Chart 2: Channel mix
fig, axes = plt.subplots(1, 3, figsize=(15, 5))
fig.suptitle('Channel Analysis', fontsize=13, fontweight='bold')

axes[0].pie(channel['gmv'], labels=channel['channel_name'], autopct='%1.1f%%',
            colors=['#2196F3','#FF9800','#4CAF50','#9C27B0'], startangle=90)
axes[0].set_title('GMV Share by Channel')

axes[1].bar(channel['channel_name'], channel['margin_pct'],
            color=['#2196F3','#FF9800','#4CAF50','#9C27B0'])
axes[1].set_title('Margin % by Channel')
axes[1].set_ylabel('Margin %')

axes[2].bar(channel['channel_name'], channel['efficiency_ratio'],
            color=['#2196F3','#FF9800','#4CAF50','#9C27B0'])
axes[2].set_title('Channel Efficiency Ratio\n(Net Rev / Total Cost)')
axes[2].set_ylabel('Efficiency Ratio')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/02_channel_analysis.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 02_channel_analysis.png")

# ─────────────────────────────────────────
# SECTION 7: GEO ANALYSIS
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 7: GEO-WISE GMV ANALYSIS")
print("=" * 60)

geo_state = suc_ci.groupby('state').agg(
    txn_count   = ('transaction_id', 'count'),
    gmv         = ('amount', 'sum'),
    net_revenue = ('net_revenue', 'sum'),
    unique_users= ('customer_id', 'nunique')
).reset_index().sort_values('gmv', ascending=False)

geo_tier = suc_ci.groupby('tier').agg(
    gmv         = ('amount', 'sum'),
    txn_count   = ('transaction_id', 'count'),
    unique_users= ('customer_id', 'nunique')
).reset_index()

print("\n Top 10 States by GMV:")
print(geo_state.head(10)[['state','gmv','unique_users','txn_count']].to_string(index=False))

print("\n GMV by City Tier:")
print(geo_tier.to_string(index=False))

fig, axes = plt.subplots(1, 2, figsize=(14, 6))
fig.suptitle('Geographic GMV Distribution', fontsize=13, fontweight='bold')

top_states = geo_state.head(10)
axes[0].barh(top_states['state'], top_states['gmv'] / 1e6, color='steelblue')
axes[0].set_title('Top 10 States by GMV')
axes[0].set_xlabel('GMV (₹ Millions)')
axes[0].invert_yaxis()

axes[1].bar(geo_tier['tier'], geo_tier['gmv'] / 1e6,
            color=['#E74C3C','#3498DB','#2ECC71'])
axes[1].set_title('GMV by City Tier')
axes[1].set_ylabel('GMV (₹ Millions)')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/03_geo_analysis.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 03_geo_analysis.png")

# ─────────────────────────────────────────
# SECTION 8: TRANSACTION FAILURE & RETRY ANALYSIS
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("SECTION 8: FAILURE & RETRY ANALYSIS")
print("=" * 60)

retry = ft.groupby('retry_count').agg(
    txn_count   = ('transaction_id', 'count'),
    success_cnt = ('status', lambda x: (x == 'SUCCESS').sum()),
    avg_proc_fee= ('processing_fee_amt', 'mean')
).reset_index()
retry['success_rate'] = retry['success_cnt'] / retry['txn_count'] * 100

print("\n Retry Analysis:")
print(retry.to_string(index=False))

device = ft[ft['status'] == 'SUCCESS'].groupby('device_os').agg(
    txn_count   = ('transaction_id', 'count'),
    gmv         = ('amount', 'sum')
).reset_index()
device['gmv_share_pct'] = device['gmv'] / device['gmv'].sum() * 100

print("\n Device OS Split:")
print(device.to_string(index=False))

fig, axes = plt.subplots(1, 2, figsize=(12, 5))
fig.suptitle('Operational Metrics', fontsize=13, fontweight='bold')

axes[0].plot(retry['retry_count'], retry['success_rate'],
             marker='o', color='crimson', linewidth=2)
axes[0].set_title('Success Rate vs Retry Count')
axes[0].set_xlabel('Retry Count')
axes[0].set_ylabel('Success Rate %')

axes[1].pie(device['txn_count'], labels=device['device_os'],
            autopct='%1.1f%%', colors=['#3498DB','#E67E22','#95A5A6'])
axes[1].set_title('Transaction Share by Device OS')

plt.tight_layout()
plt.savefig(f"{CHART_DIR}/04_operational_metrics.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 04_operational_metrics.png")

# ─────────────────────────────────────────
# SECTION 9: MERCHANT CATEGORY ANALYSIS
# ─────────────────────────────────────────
merch_cat = suc_m.groupby('category').agg(
    gmv         = ('amount', 'sum'),
    net_revenue = ('net_revenue', 'sum'),
    txn_count   = ('transaction_id', 'count')
).reset_index()
merch_cat['margin_pct'] = merch_cat['net_revenue'] / merch_cat['gmv'] * 100
merch_cat = merch_cat.sort_values('gmv', ascending=False)

print("\n" + "=" * 60)
print("SECTION 9: MERCHANT CATEGORY GMV")
print("=" * 60)
print(merch_cat[['category','gmv','net_revenue','margin_pct','txn_count']].to_string(index=False))

fig, ax = plt.subplots(figsize=(10, 5))
bars = ax.bar(merch_cat['category'], merch_cat['gmv'] / 1e6,
              color=sns.color_palette("Set2", len(merch_cat)))
ax2  = ax.twinx()
ax2.plot(merch_cat['category'], merch_cat['margin_pct'],
         marker='D', color='darkred', linewidth=2, label='Margin %')
ax.set_title('GMV & Margin % by Merchant Category', fontsize=12, fontweight='bold')
ax.set_ylabel('GMV (₹ Millions)')
ax2.set_ylabel('Margin %')
ax2.legend(loc='upper right')
plt.tight_layout()
plt.savefig(f"{CHART_DIR}/05_merchant_category.png", bbox_inches='tight')
plt.close()
print(f"  Chart saved: 05_merchant_category.png")

print("\n" + "=" * 60)
print("01_eda_and_kpis.py  ✅  COMPLETE")
print(f"Charts saved to: {CHART_DIR}/")
print("=" * 60)
