"""
============================================================
UPI TRANSACTION ANALYTICS PROJECT
FILE: 04_export_for_powerbi.py
PURPOSE: Generate all Power BI ready CSV exports and
         create a summary report
============================================================
Run LAST — after 01, 02, 03 scripts
python3 04_export_for_powerbi.py
"""

import pandas as pd
import numpy as np
import os

DATA_DIR   = "../data"
OUTPUT_DIR = "../outputs"
os.makedirs(f"{OUTPUT_DIR}/powerbi_exports", exist_ok=True)

print("=" * 60)
print("EXPORTING POWER BI READY CSV FILES")
print("=" * 60)

# ── LOAD ──────────────────────────────────────────────────
ft  = pd.read_csv(f"{DATA_DIR}/fact_transactions.csv", parse_dates=['txn_date'])
dc  = pd.read_csv(f"{DATA_DIR}/dim_customer.csv",     parse_dates=['signup_date'])
dm  = pd.read_csv(f"{DATA_DIR}/dim_merchant.csv")
dch = pd.read_csv(f"{DATA_DIR}/dim_channel.csv")
dci = pd.read_csv(f"{DATA_DIR}/dim_city.csv")
dd  = pd.read_csv(f"{DATA_DIR}/dim_date.csv",         parse_dates=['date'])

suc = ft[ft['status'] == 'SUCCESS'].copy()
suc['mdr_revenue'] = (suc['mdr_pct']/100.0) * suc['amount']
suc['net_revenue'] = suc['mdr_revenue'] - suc['cashback_amt'] - suc['processing_fee_amt']
suc['txn_month']   = suc['txn_date'].dt.to_period('M')
REF_DATE           = suc['txn_date'].max()

# ─────────────────────────────────────────
# EXPORT 1: Monthly KPI Summary (Dashboard 1 — Executive)
# ─────────────────────────────────────────
monthly = suc.groupby('txn_month').agg(
    txn_count       = ('transaction_id', 'count'),
    gmv             = ('amount', 'sum'),
    gross_mdr_rev   = ('mdr_revenue', 'sum'),
    cashback_cost   = ('cashback_amt', 'sum'),
    processing_cost = ('processing_fee_amt', 'sum'),
    net_revenue     = ('net_revenue', 'sum'),
    mau             = ('customer_id', 'nunique')
).reset_index()

monthly['margin_pct']         = monthly['net_revenue'] / monthly['gmv'] * 100
monthly['gmv_mom_growth_pct'] = monthly['gmv'].pct_change() * 100
monthly['rev_mom_growth_pct'] = monthly['net_revenue'].pct_change() * 100
monthly['mau_mom_growth_pct'] = monthly['mau'].pct_change() * 100
monthly['txn_month']          = monthly['txn_month'].astype(str)

monthly.to_csv(f"{OUTPUT_DIR}/powerbi_exports/01_monthly_kpi.csv", index=False)
print("  ✅ 01_monthly_kpi.csv")


# ─────────────────────────────────────────
# EXPORT 2: Channel Performance (Dashboard 1 & 3)
# ─────────────────────────────────────────
suc_ch = suc.merge(dch, on='channel_id', how='left')
channel = suc_ch.groupby(['channel_name']).agg(
    txn_count      = ('transaction_id', 'count'),
    gmv            = ('amount', 'sum'),
    net_revenue    = ('net_revenue', 'sum'),
    cashback_cost  = ('cashback_amt', 'sum'),
    processing_cost= ('processing_fee_amt', 'sum'),
    unique_users   = ('customer_id', 'nunique')
).reset_index()
channel['margin_pct']       = channel['net_revenue'] / channel['gmv'] * 100
channel['total_cost']       = channel['cashback_cost'] + channel['processing_cost']
channel['efficiency_ratio'] = channel['net_revenue'] / channel['total_cost'].replace(0, np.nan)
channel['gmv_share_pct']    = channel['gmv'] / channel['gmv'].sum() * 100

channel.to_csv(f"{OUTPUT_DIR}/powerbi_exports/02_channel_performance.csv", index=False)
print("  ✅ 02_channel_performance.csv")


# ─────────────────────────────────────────
# EXPORT 3: Monthly Channel Trend
# ─────────────────────────────────────────
monthly_channel = suc_ch.groupby(['txn_month', 'channel_name']).agg(
    txn_count  = ('transaction_id', 'count'),
    gmv        = ('amount', 'sum'),
    net_revenue= ('net_revenue', 'sum')
).reset_index()
monthly_channel['txn_month'] = monthly_channel['txn_month'].astype(str)

monthly_channel.to_csv(f"{OUTPUT_DIR}/powerbi_exports/03_monthly_channel_trend.csv", index=False)
print("  ✅ 03_monthly_channel_trend.csv")


# ─────────────────────────────────────────
# EXPORT 4: Geo GMV (State + Tier)
# ─────────────────────────────────────────
suc_ci = suc.merge(dci, on='city_id', how='left')

geo_state = suc_ci.groupby(['state', 'tier']).agg(
    txn_count    = ('transaction_id', 'count'),
    gmv          = ('amount', 'sum'),
    net_revenue  = ('net_revenue', 'sum'),
    unique_users = ('customer_id', 'nunique')
).reset_index()
geo_state['gmv_share_pct'] = geo_state['gmv'] / geo_state['gmv'].sum() * 100

geo_state.to_csv(f"{OUTPUT_DIR}/powerbi_exports/04_geo_gmv.csv", index=False)
print("  ✅ 04_geo_gmv.csv")


# ─────────────────────────────────────────
# EXPORT 5: DAU/MAU Stickiness
# ─────────────────────────────────────────
dau = suc.groupby('txn_date')['customer_id'].nunique().reset_index(name='dau')
dau['txn_month'] = dau['txn_date'].dt.to_period('M')
mau = suc.groupby('txn_month')['customer_id'].nunique().reset_index(name='mau')
avg_dau = dau.groupby('txn_month')['dau'].mean().reset_index(name='avg_dau')

stickiness = avg_dau.merge(mau, on='txn_month')
stickiness['stickiness_pct'] = stickiness['avg_dau'] / stickiness['mau'] * 100
stickiness['txn_month']      = stickiness['txn_month'].astype(str)

stickiness.to_csv(f"{OUTPUT_DIR}/powerbi_exports/05_dau_mau_stickiness.csv", index=False)
print("  ✅ 05_dau_mau_stickiness.csv")


# ─────────────────────────────────────────
# EXPORT 6: Cohort Retention Matrix
# ─────────────────────────────────────────
first_txn  = suc.groupby('customer_id')['txn_month'].min().reset_index(name='cohort_month')
cohort_size = first_txn.groupby('cohort_month').size().reset_index(name='cohort_size')
suc_coh    = suc.merge(first_txn, on='customer_id')
suc_coh['months_since_start'] = (
    (suc_coh['txn_date'].dt.year  - suc_coh['cohort_month'].apply(lambda p: p.year)) * 12 +
    (suc_coh['txn_date'].dt.month - suc_coh['cohort_month'].apply(lambda p: p.month))
)
coh_ret = (suc_coh.groupby(['cohort_month','months_since_start'])['customer_id']
           .nunique().reset_index(name='active_users'))
coh_ret = coh_ret.merge(cohort_size, on='cohort_month')
coh_ret['retention_pct'] = coh_ret['active_users'] / coh_ret['cohort_size'] * 100
coh_ret['cohort_month']  = coh_ret['cohort_month'].astype(str)
coh_ret = coh_ret[coh_ret['months_since_start'] <= 11]

coh_ret.to_csv(f"{OUTPUT_DIR}/powerbi_exports/06_cohort_retention.csv", index=False)
print("  ✅ 06_cohort_retention.csv")


# ─────────────────────────────────────────
# EXPORT 7: RFM Segmentation
# ─────────────────────────────────────────
rfm = suc.groupby('customer_id').agg(
    last_txn_date = ('txn_date', 'max'),
    frequency     = ('transaction_id', 'count'),
    monetary      = ('amount', 'sum'),
    net_revenue   = ('net_revenue', 'sum')
).reset_index()
rfm['recency_days'] = (REF_DATE - rfm['last_txn_date']).dt.days

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
rfm_export = rfm.merge(dc[['customer_id','segment_tag']], on='customer_id', how='left')
rfm_export['last_txn_date'] = rfm_export['last_txn_date'].astype(str)

rfm_export.to_csv(f"{OUTPUT_DIR}/powerbi_exports/07_rfm_segments.csv", index=False)
print("  ✅ 07_rfm_segments.csv")


# ─────────────────────────────────────────
# EXPORT 8: CLV by Customer
# ─────────────────────────────────────────
clv = suc.groupby('customer_id').agg(
    total_txns     = ('transaction_id', 'count'),
    total_gmv      = ('amount', 'sum'),
    lifetime_value = ('net_revenue', 'sum'),
    first_txn      = ('txn_date', 'min'),
    last_txn       = ('txn_date', 'max')
).reset_index()
clv['active_days']  = (clv['last_txn'] - clv['first_txn']).dt.days
clv['clv_bucket'] = pd.qcut(clv['lifetime_value'], [0, .5, .75, .90, 1.0],
                             labels=['Bottom 50%','Top 25%','Top 10%','Top 1%'])
clv = clv.merge(dc[['customer_id','segment_tag']], on='customer_id', how='left')
clv['first_txn'] = clv['first_txn'].astype(str)
clv['last_txn']  = clv['last_txn'].astype(str)

clv.to_csv(f"{OUTPUT_DIR}/powerbi_exports/08_clv_table.csv", index=False)
print("  ✅ 08_clv_table.csv")


# ─────────────────────────────────────────
# EXPORT 9: Churn Risk Funnel
# ─────────────────────────────────────────
cust_act = suc.groupby('customer_id').agg(
    last_txn_date = ('txn_date', 'max'),
    txn_last_90d  = ('txn_date', lambda x: (x >= REF_DATE - pd.Timedelta(days=90)).sum()),
    txn_last_30d  = ('txn_date', lambda x: (x >= REF_DATE - pd.Timedelta(days=30)).sum()),
    total_txns    = ('transaction_id', 'count'),
    total_gmv     = ('amount', 'sum'),
    lifetime_value= ('net_revenue', 'sum')
).reset_index()
cust_act['days_inactive'] = (REF_DATE - cust_act['last_txn_date']).dt.days

def churn_risk(row):
    if row['days_inactive'] > 60 and row['txn_last_90d'] < 2:    return 'High Risk'
    elif row['days_inactive'] > 30 and row['txn_last_90d'] < 5:  return 'Medium Risk'
    elif row['txn_last_30d'] == 0:                                return 'Slipping Away'
    else:                                                         return 'Active'

cust_act['churn_risk']    = cust_act.apply(churn_risk, axis=1)
cust_act['last_txn_date'] = cust_act['last_txn_date'].astype(str)

cust_act.to_csv(f"{OUTPUT_DIR}/powerbi_exports/09_churn_risk.csv", index=False)
print("  ✅ 09_churn_risk.csv")


# ─────────────────────────────────────────
# EXPORT 10: Merchant Category Summary
# ─────────────────────────────────────────
suc_m = suc.merge(dm, on='merchant_id', how='left')
merch = suc_m.groupby('category').agg(
    txn_count   = ('transaction_id', 'count'),
    gmv         = ('amount', 'sum'),
    net_revenue = ('net_revenue', 'sum'),
    cashback    = ('cashback_amt', 'sum'),
    unique_users= ('customer_id', 'nunique')
).reset_index()
merch['margin_pct'] = merch['net_revenue'] / merch['gmv'] * 100
merch['gmv_share']  = merch['gmv'] / merch['gmv'].sum() * 100

merch.to_csv(f"{OUTPUT_DIR}/powerbi_exports/10_merchant_category.csv", index=False)
print("  ✅ 10_merchant_category.csv")


# ─────────────────────────────────────────
# EXPORT 11: Cashback ROI Monthly
# ─────────────────────────────────────────
cashback_roi = suc.groupby('txn_month').agg(
    gmv          = ('amount', 'sum'),
    cashback_cost= ('cashback_amt', 'sum'),
    net_revenue  = ('net_revenue', 'sum')
).reset_index()
cashback_roi['gmv_per_cashback'] = cashback_roi['gmv'] / cashback_roi['cashback_cost'].replace(0, np.nan)
cashback_roi['cashback_as_pct_gmv'] = cashback_roi['cashback_cost'] / cashback_roi['gmv'] * 100
cashback_roi['txn_month'] = cashback_roi['txn_month'].astype(str)

cashback_roi.to_csv(f"{OUTPUT_DIR}/powerbi_exports/11_cashback_roi.csv", index=False)
print("  ✅ 11_cashback_roi.csv")


# ─────────────────────────────────────────
# EXPORT 12: What-If Scenario Results
# ─────────────────────────────────────────
base_gmv        = suc['amount'].sum()
base_cashback   = suc['cashback_amt'].sum()
base_processing = suc['processing_fee_amt'].sum()
gross_mdr       = suc['mdr_revenue'].sum()
base_net_rev    = suc['net_revenue'].sum()

whatif_rows = []
for cb_red in range(0, 55, 5):
    for mdr_inc in [0.0, 0.25, 0.5, 1.0]:
        new_gmv      = base_gmv * (1 + (-0.003) * cb_red)
        new_cashback = base_cashback * (1 - cb_red/100)
        new_mdr_rev  = (gross_mdr / base_gmv) * new_gmv + new_gmv * (mdr_inc/100)
        new_proc     = (base_processing / base_gmv) * new_gmv
        new_net      = new_mdr_rev - new_cashback - new_proc
        new_margin   = new_net / new_gmv * 100
        whatif_rows.append({
            'cashback_reduction_pct': cb_red,
            'mdr_increase_pct':       mdr_inc,
            'projected_gmv':          round(new_gmv, 2),
            'projected_net_revenue':  round(new_net, 2),
            'projected_margin_pct':   round(new_margin, 4),
            'revenue_uplift':         round(new_net - base_net_rev, 2)
        })

pd.DataFrame(whatif_rows).to_csv(f"{OUTPUT_DIR}/powerbi_exports/12_whatif_scenarios.csv", index=False)
print("  ✅ 12_whatif_scenarios.csv")


# ─────────────────────────────────────────
# PRINT EXECUTIVE SUMMARY
# ─────────────────────────────────────────
print("\n" + "=" * 60)
print("EXECUTIVE SUMMARY — UPI ANALYTICS PROJECT")
print("=" * 60)
print(f"\n  Period          : {suc['txn_date'].min().date()} → {suc['txn_date'].max().date()}")
print(f"  Total GMV       : ₹{base_gmv:,.2f}")
print(f"  Net Revenue     : ₹{base_net_rev:,.2f}")
print(f"  Margin %        : {base_net_rev/base_gmv*100:.4f}%")
print(f"  Total Customers : {suc['customer_id'].nunique():,}")
print(f"  Success Rate    : {len(suc)/len(ft)*100:.2f}%")
print(f"\n  Cashback ROI    : ₹{base_gmv/base_cashback:.2f} GMV per ₹1 cashback")
print(f"  UPI GMV Share   : {suc_ch[suc_ch['channel_name']=='UPI']['amount'].sum()/base_gmv*100:.1f}%")

print(f"\n  All Power BI CSVs saved to: {OUTPUT_DIR}/powerbi_exports/")
print("\n" + "=" * 60)
print("04_export_for_powerbi.py  ✅  COMPLETE")
print("=" * 60)
