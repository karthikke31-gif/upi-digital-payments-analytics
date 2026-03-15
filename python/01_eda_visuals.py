"""
============================================================
FILE: 01_eda_visuals.py
PURPOSE: Exploratory Data Analysis + All KPI Visualizations
         GMV trends, Channel Mix, Geo analysis, Cohort Heatmap,
         RFM treemap, Churn funnel
RUN AFTER: 00_setup_database.py
============================================================
"""

import sqlite3
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.ticker as mticker
import seaborn as sns
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

BRAND_COLORS = ['#0057FF', '#FF6B35', '#00C49A', '#FFB300', '#7B2FBE', '#E91E63']
sns.set_theme(style='whitegrid', font_scale=1.1)

conn = sqlite3.connect(DB_PATH)

def q(sql): return pd.read_sql_query(sql, conn)
def savefig(name): plt.savefig(os.path.join(OUTPUT_DIR, name), dpi=150, bbox_inches='tight')


# ─────────────────────────────────────────────────────────
# FIGURE 1: EXECUTIVE DASHBOARD — GMV & Revenue Trends
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 1: GMV & Revenue Trends...")

monthly = q("""
    SELECT strftime('%Y-%m', txn_date) AS month,
        ROUND(SUM(amount), 2) AS gmv,
        ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt), 2) AS net_revenue,
        COUNT(DISTINCT customer_id) AS mau,
        COUNT(*) AS txns,
        ROUND(SUM(cashback_amt), 2) AS cashback,
        ROUND(SUM((mdr_pct/100.0)*amount - cashback_amt - processing_fee_amt)
              / NULLIF(SUM(amount),0)*100, 4) AS margin_pct
    FROM fact_transactions WHERE status='SUCCESS'
    GROUP BY month ORDER BY month
""")
monthly['gmv_mom'] = monthly['gmv'].pct_change()*100
monthly['rev_mom'] = monthly['net_revenue'].pct_change()*100

fig, axes = plt.subplots(2, 2, figsize=(16, 10))
fig.suptitle('UPI Platform — Executive KPI Dashboard', fontsize=18, fontweight='bold', y=1.01)

# GMV Trend
ax = axes[0, 0]
bars = ax.bar(monthly['month'], monthly['gmv']/1e6, color=BRAND_COLORS[0], alpha=0.8, label='GMV (₹M)')
ax2 = ax.twinx()
ax2.plot(monthly['month'], monthly['gmv_mom'], 'o--', color=BRAND_COLORS[1], lw=2, label='MoM Growth %')
ax2.axhline(0, color='grey', lw=0.5, linestyle='--')
ax.set_title('Monthly GMV & MoM Growth', fontweight='bold')
ax.set_ylabel('GMV (₹ Millions)')
ax2.set_ylabel('MoM Growth %')
ax.set_xticklabels(monthly['month'], rotation=45, ha='right', fontsize=8)
ax.legend(loc='upper left'); ax2.legend(loc='upper right')

# Net Revenue vs Cashback Cost
ax = axes[0, 1]
width = 0.4
x = range(len(monthly))
ax.bar([i - width/2 for i in x], monthly['net_revenue'], width=width, label='Net Revenue', color=BRAND_COLORS[2])
ax.bar([i + width/2 for i in x], monthly['cashback'], width=width, label='Cashback Cost', color=BRAND_COLORS[3])
ax.set_title('Net Revenue vs Cashback Cost (Monthly)', fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels(monthly['month'], rotation=45, ha='right', fontsize=8)
ax.set_ylabel('₹ Amount')
ax.legend()

# MAU Trend
ax = axes[1, 0]
ax.fill_between(monthly['month'], monthly['mau'], alpha=0.4, color=BRAND_COLORS[4])
ax.plot(monthly['month'], monthly['mau'], 'o-', color=BRAND_COLORS[4], lw=2)
ax.set_title('Monthly Active Users (MAU) Trend', fontweight='bold')
ax.set_ylabel('Unique Active Users')
ax.set_xticklabels(monthly['month'], rotation=45, ha='right', fontsize=8)
ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda x, _: f'{int(x):,}'))

# Margin % Trend
ax = axes[1, 1]
ax.plot(monthly['month'], monthly['margin_pct'], 's-', color=BRAND_COLORS[5], lw=2.5, markersize=8)
ax.fill_between(monthly['month'], monthly['margin_pct'], alpha=0.2, color=BRAND_COLORS[5])
ax.set_title('Platform Margin % Trend', fontweight='bold')
ax.set_ylabel('Margin %')
ax.set_xticklabels(monthly['month'], rotation=45, ha='right', fontsize=8)
ax.axhline(monthly['margin_pct'].mean(), color='red', lw=1.5, linestyle='--', label=f'Avg: {monthly["margin_pct"].mean():.2f}%')
ax.legend()

plt.tight_layout()
savefig('01_executive_kpi_dashboard.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 2: CHANNEL MIX ANALYSIS
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 2: Channel Analysis...")

channel = q("""
    SELECT ch.channel_name,
        COUNT(*) AS txn_count,
        ROUND(SUM(f.amount), 2) AS gmv,
        ROUND(SUM(f.cashback_amt), 2) AS cashback,
        ROUND(SUM(f.processing_fee_amt), 2) AS proc_fee,
        ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue,
        ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
              / NULLIF(SUM(f.cashback_amt + f.processing_fee_amt), 0), 4) AS efficiency,
        ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
              / NULLIF(SUM(f.amount),0)*100, 4) AS margin_pct,
        ROUND(AVG(f.amount), 2) AS avg_ticket
    FROM fact_transactions f
    JOIN dim_channel ch ON f.channel_id = ch.channel_id
    WHERE f.status='SUCCESS'
    GROUP BY ch.channel_name ORDER BY gmv DESC
""")

fig, axes = plt.subplots(2, 3, figsize=(18, 10))
fig.suptitle('Channel Performance Analysis', fontsize=16, fontweight='bold')

# GMV Pie
axes[0, 0].pie(channel['gmv'], labels=channel['channel_name'], autopct='%1.1f%%',
               colors=BRAND_COLORS[:4], startangle=90, pctdistance=0.85)
axes[0, 0].set_title('GMV Share by Channel')

# Transaction Count Bar
axes[0, 1].barh(channel['channel_name'], channel['txn_count'], color=BRAND_COLORS[:4])
axes[0, 1].set_title('Transaction Count by Channel')
axes[0, 1].set_xlabel('Number of Transactions')
for i, v in enumerate(channel['txn_count']):
    axes[0, 1].text(v + 10, i, f'{v:,}', va='center', fontsize=9)

# Margin % by Channel
colors_margin = ['#00C49A' if m > channel['margin_pct'].mean() else '#FF6B35' for m in channel['margin_pct']]
axes[0, 2].bar(channel['channel_name'], channel['margin_pct'], color=colors_margin)
axes[0, 2].axhline(channel['margin_pct'].mean(), color='red', lw=1.5, linestyle='--', label='Platform Avg')
axes[0, 2].set_title('Margin % by Channel')
axes[0, 2].set_ylabel('Margin %')
axes[0, 2].legend()

# Net Revenue vs Cost Stacked
bottom = np.zeros(len(channel))
width = 0.5
axes[1, 0].bar(channel['channel_name'], channel['cashback'], width, label='Cashback Cost', color='#FFB300', alpha=0.9)
axes[1, 0].bar(channel['channel_name'], channel['proc_fee'], width, bottom=channel['cashback'], label='Processing Cost', color='#FF6B35', alpha=0.9)
ax2 = axes[1, 0].twinx()
ax2.plot(channel['channel_name'], channel['net_revenue'], 'D-', color='#0057FF', lw=2, markersize=8, label='Net Revenue')
axes[1, 0].set_title('Cost Breakdown vs Net Revenue')
axes[1, 0].set_ylabel('Costs (₹)')
ax2.set_ylabel('Net Revenue (₹)')
axes[1, 0].legend(loc='upper left'); ax2.legend(loc='upper right')

# Channel Efficiency Ratio
axes[1, 1].bar(channel['channel_name'], channel['efficiency'], color=BRAND_COLORS[:4])
axes[1, 1].set_title('Channel Efficiency Ratio\n(Net Revenue / Total Cost)')
axes[1, 1].set_ylabel('Efficiency Ratio')
for i, v in enumerate(channel['efficiency']):
    axes[1, 1].text(i, v + 0.01, f'{v:.2f}', ha='center', fontsize=10, fontweight='bold')

# Avg Ticket Size
axes[1, 2].bar(channel['channel_name'], channel['avg_ticket'], color=[BRAND_COLORS[i] for i in range(4)])
axes[1, 2].set_title('Average Ticket Size by Channel (₹)')
axes[1, 2].set_ylabel('Avg Transaction Value (₹)')
for i, v in enumerate(channel['avg_ticket']):
    axes[1, 2].text(i, v + 0.5, f'₹{v:,.0f}', ha='center', fontsize=10)

plt.tight_layout()
savefig('02_channel_analysis.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 3: GEO ANALYSIS
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 3: Geo Analysis...")

geo_state = q("""
    SELECT ci.state, ci.tier,
        COUNT(*) AS txn_count,
        ROUND(SUM(f.amount), 2) AS gmv,
        COUNT(DISTINCT f.customer_id) AS customers,
        ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt), 2) AS net_revenue
    FROM fact_transactions f
    JOIN dim_city ci ON f.city_id = ci.city_id
    WHERE f.status='SUCCESS'
    GROUP BY ci.state, ci.tier ORDER BY gmv DESC LIMIT 15
""")

tier = q("""
    SELECT ci.tier,
        COUNT(*) AS txn_count, COUNT(DISTINCT f.customer_id) AS customers,
        ROUND(SUM(f.amount), 2) AS gmv,
        ROUND(AVG(f.amount), 2) AS avg_ticket,
        ROUND(SUM((f.mdr_pct/100.0)*f.amount - f.cashback_amt - f.processing_fee_amt)
              / NULLIF(SUM(f.amount),0)*100, 4) AS margin_pct
    FROM fact_transactions f JOIN dim_city ci ON f.city_id = ci.city_id
    WHERE f.status='SUCCESS'
    GROUP BY ci.tier ORDER BY gmv DESC
""")

fig, axes = plt.subplots(1, 3, figsize=(20, 7))
fig.suptitle('Geo-wise Performance Analysis', fontsize=16, fontweight='bold')

# Top States by GMV (horizontal bar)
top15 = geo_state.head(15).sort_values('gmv')
color_map = {'Tier-1': '#0057FF', 'Tier-2': '#00C49A', 'Tier-3': '#FFB300'}
bar_colors = [color_map.get(t, '#999') for t in top15['tier']]
axes[0].barh(top15['state'], top15['gmv']/1e3, color=bar_colors)
axes[0].set_title('Top 15 States by GMV (₹ Thousands)')
axes[0].set_xlabel('GMV (₹K)')
patches = [mpatches.Patch(color=v, label=k) for k, v in color_map.items()]
axes[0].legend(handles=patches, title='City Tier')

# GMV by City Tier — Donut
wedges, texts, autotexts = axes[1].pie(
    tier['gmv'], labels=tier['tier'], autopct='%1.1f%%',
    colors=['#0057FF', '#00C49A', '#FFB300'], startangle=90,
    wedgeprops={'width': 0.5}
)
axes[1].set_title('GMV Distribution by City Tier')
axes[1].text(0, 0, f'Total\n₹{tier["gmv"].sum()/1e6:.1f}M', ha='center', va='center', fontweight='bold')

# Margin % and Avg Ticket by Tier
x = range(len(tier))
ax_left = axes[2]
ax_right = ax_left.twinx()
ax_left.bar([i - 0.2 for i in x], tier['margin_pct'], width=0.4, color='#0057FF', label='Margin %', alpha=0.85)
ax_right.bar([i + 0.2 for i in x], tier['avg_ticket'], width=0.4, color='#FF6B35', label='Avg Ticket', alpha=0.85)
ax_left.set_xticks(x); ax_left.set_xticklabels(tier['tier'])
ax_left.set_title('Margin % & Avg Ticket by City Tier')
ax_left.set_ylabel('Margin %')
ax_right.set_ylabel('Avg Ticket Size (₹)')
ax_left.legend(loc='upper left'); ax_right.legend(loc='upper right')

plt.tight_layout()
savefig('03_geo_analysis.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 4: COHORT RETENTION HEATMAP
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 4: Cohort Retention Heatmap...")

cohort_raw = q("""
    WITH first_txn AS (
        SELECT customer_id, strftime('%Y-%m', MIN(txn_date)) AS cohort_month
        FROM fact_transactions WHERE status='SUCCESS' GROUP BY customer_id
    ),
    activity AS (
        SELECT customer_id, strftime('%Y-%m', txn_date) AS activity_month
        FROM fact_transactions WHERE status='SUCCESS'
        GROUP BY customer_id, strftime('%Y-%m', txn_date)
    ),
    cohort_sizes AS (
        SELECT cohort_month, COUNT(*) AS sz FROM first_txn GROUP BY cohort_month
    )
    SELECT ft.cohort_month, cs.sz,
        (CAST(strftime('%Y', ca.activity_month||'-01') AS INT)*12 +
         CAST(strftime('%m', ca.activity_month||'-01') AS INT))
        - (CAST(strftime('%Y', ft.cohort_month||'-01') AS INT)*12 +
           CAST(strftime('%m', ft.cohort_month||'-01') AS INT)) AS m_offset,
        COUNT(DISTINCT ca.customer_id) AS active
    FROM first_txn ft
    JOIN activity ca ON ft.customer_id = ca.customer_id
    JOIN cohort_sizes cs ON ft.cohort_month = cs.cohort_month
    WHERE (CAST(strftime('%Y', ca.activity_month||'-01') AS INT)*12 +
           CAST(strftime('%m', ca.activity_month||'-01') AS INT))
          - (CAST(strftime('%Y', ft.cohort_month||'-01') AS INT)*12 +
             CAST(strftime('%m', ft.cohort_month||'-01') AS INT)) BETWEEN 0 AND 8
    GROUP BY ft.cohort_month, cs.sz, m_offset
""")

cohort_raw['retention_pct'] = cohort_raw['active'] / cohort_raw['sz'] * 100
pivot = cohort_raw.pivot(index='cohort_month', columns='m_offset', values='retention_pct')
pivot.columns = [f'M+{c}' for c in pivot.columns]

fig, ax = plt.subplots(figsize=(14, 7))
mask = pivot.isna()
sns.heatmap(pivot, annot=True, fmt='.0f', cmap='YlGnBu',
            linewidths=0.5, ax=ax, mask=mask,
            annot_kws={'size': 9}, vmin=0, vmax=100)
ax.set_title('Cohort Retention Heatmap (% of cohort still active)', fontsize=14, fontweight='bold')
ax.set_xlabel('Months Since First Transaction')
ax.set_ylabel('Cohort Month (First Transaction)')
plt.tight_layout()
savefig('04_cohort_retention_heatmap.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 5: RFM SEGMENTATION
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 5: RFM Segmentation...")

rfm = q("""
    WITH rfm AS (
        SELECT customer_id,
            CAST(JULIANDAY('2026-03-05') - JULIANDAY(MAX(txn_date)) AS INTEGER) AS recency_days,
            COUNT(*) AS frequency, ROUND(SUM(amount), 2) AS monetary
        FROM fact_transactions WHERE status='SUCCESS' GROUP BY customer_id
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
    SELECT CASE
            WHEN rs=4 AND fs=4 AND ms=4  THEN 'Champions'
            WHEN rs>=3 AND fs>=3          THEN 'Loyal Customers'
            WHEN rs=4 AND fs<=2           THEN 'New Customers'
            WHEN rs>=3 AND fs<=2 AND ms>=3 THEN 'Potential Loyalists'
            WHEN rs=2 AND fs>=3           THEN 'At Risk'
            WHEN rs<=2 AND fs<=2 AND ms>=3 THEN 'Cant Lose Them'
            WHEN rs<=2 AND fs<=2 AND ms<=2 THEN 'Lost Customers'
            WHEN rs=1                     THEN 'Hibernating'
            ELSE 'Needs Attention'
        END AS segment,
        COUNT(*) AS customers, ROUND(SUM(monetary), 2) AS revenue,
        ROUND(AVG(monetary), 2) AS avg_rev
    FROM scored GROUP BY segment ORDER BY revenue DESC
""")

fig, axes = plt.subplots(1, 2, figsize=(16, 7))
fig.suptitle('RFM Customer Segmentation', fontsize=16, fontweight='bold')

rfm_colors = ['#0057FF','#00C49A','#FFB300','#FF6B35','#E91E63','#7B2FBE','#607D8B','#FF5722','#795548']

# Customers per segment
axes[0].barh(rfm['segment'], rfm['customers'], color=rfm_colors[:len(rfm)])
axes[0].set_title('Customers per Segment')
axes[0].set_xlabel('Number of Customers')
for i, v in enumerate(rfm['customers']):
    axes[0].text(v + 5, i, f'{v:,}', va='center', fontsize=9)

# Revenue contribution (bubble-like bar)
axes[1].barh(rfm['segment'], rfm['revenue']/1e3, color=rfm_colors[:len(rfm)])
axes[1].set_title('Revenue Contribution (₹ Thousands)')
axes[1].set_xlabel('Revenue (₹K)')
for i, v in enumerate(rfm['revenue']/1e3):
    axes[1].text(v + 1, i, f'₹{v:,.0f}K', va='center', fontsize=9)

plt.tight_layout()
savefig('05_rfm_segmentation.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 6: CHURN RISK FUNNEL
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 6: Churn Risk Funnel...")

churn = q("""
    WITH ca AS (
        SELECT customer_id, MAX(txn_date) AS last_txn,
            COUNT(CASE WHEN txn_date >= date('2026-03-05', '-90 days') THEN 1 END) AS t90,
            COUNT(CASE WHEN txn_date >= date('2026-03-05', '-30 days') THEN 1 END) AS t30
        FROM fact_transactions WHERE status='SUCCESS' GROUP BY customer_id
    )
    SELECT CASE
            WHEN JULIANDAY('2026-03-05') - JULIANDAY(last_txn)>90 AND t90=0 THEN 'CHURNED'
            WHEN JULIANDAY('2026-03-05') - JULIANDAY(last_txn)>60 AND t90<2 THEN 'HIGH_RISK'
            WHEN JULIANDAY('2026-03-05') - JULIANDAY(last_txn)>30 AND t30=0 THEN 'AT_RISK'
            WHEN t30>=1 AND t90>=3 THEN 'ACTIVE'
            ELSE 'MODERATE_RISK'
        END AS segment,
        COUNT(*) AS users
    FROM ca GROUP BY segment ORDER BY users DESC
""")

fig, axes = plt.subplots(1, 2, figsize=(14, 6))
fig.suptitle('Churn Risk Funnel Analysis', fontsize=16, fontweight='bold')

churn_colors = {'ACTIVE': '#00C49A', 'MODERATE_RISK': '#FFB300',
                'AT_RISK': '#FF6B35', 'HIGH_RISK': '#E91E63', 'CHURNED': '#B71C1C'}
colors = [churn_colors.get(s, '#999') for s in churn['segment']]

# Bar chart
axes[0].bar(churn['segment'], churn['users'], color=colors)
axes[0].set_title('Users by Churn Risk Segment')
axes[0].set_ylabel('Number of Users')
axes[0].set_xlabel('Risk Segment')
for i, v in enumerate(churn['users']):
    axes[0].text(i, v + 5, f'{v:,}', ha='center', fontsize=10, fontweight='bold')

# Donut chart
axes[1].pie(churn['users'], labels=churn['segment'], autopct='%1.1f%%',
            colors=colors, startangle=90, wedgeprops={'width': 0.6})
axes[1].set_title('Churn Risk Distribution (%)')
axes[1].text(0, 0, f'{churn["users"].sum():,}\nTotal Users', ha='center', va='center', fontsize=10)

plt.tight_layout()
savefig('06_churn_risk_funnel.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 7: DAU / MAU STICKINESS
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 7: DAU/MAU Stickiness...")

stickiness = q("""
    WITH dau AS (
        SELECT strftime('%Y-%m', txn_date) AS month,
               ROUND(AVG(d), 2) AS avg_dau
        FROM (
            SELECT txn_date, COUNT(DISTINCT customer_id) AS d
            FROM fact_transactions WHERE status='SUCCESS' GROUP BY txn_date
        ) GROUP BY month
    ),
    mau AS (
        SELECT strftime('%Y-%m', txn_date) AS month,
               COUNT(DISTINCT customer_id) AS mau
        FROM fact_transactions WHERE status='SUCCESS' GROUP BY month
    )
    SELECT d.month, d.avg_dau, m.mau,
        ROUND(d.avg_dau / NULLIF(m.mau, 0) * 100, 2) AS stickiness_pct
    FROM dau d JOIN mau m ON d.month = m.month ORDER BY d.month
""")

fig, ax = plt.subplots(figsize=(14, 5))
ax2 = ax.twinx()
ax.bar(stickiness['month'], stickiness['mau'], alpha=0.5, color='#0057FF', label='MAU')
ax.bar(stickiness['month'], stickiness['avg_dau'], alpha=0.8, color='#00C49A', label='Avg DAU')
ax2.plot(stickiness['month'], stickiness['stickiness_pct'], 'D--', color='#FF6B35', lw=2.5, markersize=8, label='Stickiness %')
ax.set_title('DAU vs MAU — Stickiness Ratio by Month', fontsize=14, fontweight='bold')
ax.set_ylabel('Users')
ax2.set_ylabel('Stickiness % (DAU/MAU)')
ax.set_xticklabels(stickiness['month'], rotation=45, ha='right', fontsize=9)
ax.legend(loc='upper left'); ax2.legend(loc='upper right')
plt.tight_layout()
savefig('07_dau_mau_stickiness.png')
plt.close()


# ─────────────────────────────────────────────────────────
# FIGURE 8: TRANSACTION SUCCESS RATE & RETRY ANALYSIS
# ─────────────────────────────────────────────────────────
print("  Plotting Fig 8: Success Rate & Retry Analysis...")

retry = q("""
    SELECT retry_count,
        COUNT(*) AS txns,
        ROUND(100.0 * SUM(CASE WHEN status='SUCCESS' THEN 1 ELSE 0 END)/COUNT(*), 2) AS success_rate,
        ROUND(AVG(processing_fee_amt), 4) AS avg_fee
    FROM fact_transactions GROUP BY retry_count ORDER BY retry_count
""")

status_dist = q("""
    SELECT status, COUNT(*) AS cnt FROM fact_transactions GROUP BY status ORDER BY cnt DESC
""")

fig, axes = plt.subplots(1, 3, figsize=(18, 5))
fig.suptitle('Transaction Quality & Operational Metrics', fontsize=14, fontweight='bold')

# Status distribution
axes[0].pie(status_dist['cnt'], labels=status_dist['status'],
            autopct='%1.1f%%', colors=['#00C49A', '#FF6B35', '#FFB300'],
            startangle=90, wedgeprops={'width': 0.6})
axes[0].set_title('Transaction Status Distribution')

# Retry vs Success Rate
axes[1].bar(retry['retry_count'].astype(str), retry['success_rate'],
            color=['#00C49A' if s > 80 else '#FF6B35' for s in retry['success_rate']])
axes[1].set_title('Success Rate by Retry Count')
axes[1].set_xlabel('Number of Retries')
axes[1].set_ylabel('Success Rate %')
axes[1].axhline(80, color='red', lw=1.5, linestyle='--', label='80% threshold')
axes[1].legend()

# Processing Fee by Retry
axes[2].plot(retry['retry_count'], retry['avg_fee'], 'o-', color='#E91E63', lw=2.5, markersize=10)
axes[2].fill_between(retry['retry_count'], retry['avg_fee'], alpha=0.2, color='#E91E63')
axes[2].set_title('Avg Processing Fee by Retry Count')
axes[2].set_xlabel('Number of Retries')
axes[2].set_ylabel('Avg Processing Fee (₹)')

plt.tight_layout()
savefig('08_transaction_quality.png')
plt.close()

conn.close()
print("\n  All EDA visualizations saved to outputs/")
print("  Files: 01_executive_kpi_dashboard.png through 08_transaction_quality.png")
