# UPI Digital Payments Analytics
---

## Project Summary

End-to-end analytics pipeline built on a synthetic UPI transaction dataset (~50K records). Covers schema design, ETL, KPI reporting, customer segmentation, cohort retention, statistical testing, and Power BI 
---

## Project Results (From the Data)

| Metric | Value |
|---|---|
| Total GMV | ₹ 15.02M |
| Net Revenue | ₹-136.15K |
| Platform Margin % | -0.91% |
| Total Transactions | 50.00K |
| Unique Customers | 14,379 |
| Avg Ticket Size | ₹300.12 |
| Cashback Rate | 1.13% of GMV |
| **Cashback A/B Test** | p < 0.0001 — Cashback users spend 43% more |
| **Bootstrap 95% CI** | Margin: [0.27%, 0.33%] |

---

# Power BI Dashboard Preview

### Enterprise Digital Performance Dashboard

![Enterprise Digital Performance Dashboard](https://raw.githubusercontent.com/karthikke31-gif/upi-digital-payments-analytics/4564a6f00ec35b3995d3b4f36c06744cc069cd65/Screenshot%202026-03-15%20at%205.48.49%E2%80%AFPM.png)

---

## Folder & File Structure

```
upi-digital-payments-analytics
│
├── dataset/
│   ├── dim_channel_50k.csv
│   ├── dim_city_50k.csv
│   ├── dim_customer_50k.csv
│   ├── dim_date_50k.csv
│   ├── dim_merchant_50k.csv
│   └── fact_transactions_50k.csv
│
├── 01_sql/
│   ├── 01_ddl_create_tables.sql
│   ├── 02_etl_load_data.sql
│   ├── 03_data_quality_checks.sql
│   ├── 04_core_kpis.sql
│   ├── 05_channel_analysis.sql
│   ├── 06_geo_analysis.sql
│   ├── 07_user_behavior_dau_mau.sql
│   ├── 08_cohort_retention.sql
│   ├── 09_rfm_segmentation.sql
│   ├── 10_clv_and_churn_risk.sql
│   └── 11_cashback_processing_retry_whatif.sql
│
├── 02_python/
│   ├── 00_setup_database.py
│   ├── 01_eda_analysis.py
│   ├── 02_statistical_analysis.py
│   ├── 03_monte_carlo_whatif.py
│   ├── upi_analytics.db
│   └── outputs/
│       ├── eda/
│       └── stats/
│
├── 03_powerbi/
│   └── powerbi_dax_and_dashboard_guide.md
│
├── outputs/
│   ├── 01_executive_kpi_dashboard.png
│   ├── 02_channel_analysis.png
│   └── 03_geo_analysis.png
│
└── README.md
```

---

## File-by-File Explanation

### `01_sql/` 

| File | Purpose | Key SQL Concepts |
|---|---|---|
| `01_ddl_create_tables.sql` | Defines the star-schema — fact and dimension tables for transactions, customers, merchants, channels, cities, and dates | `CREATE TABLE`, `PRIMARY KEY`, `FOREIGN KEY`, `INDEX` |
| `02_etl_load_data.sql` | Loads raw CSV data into the SQLite schema; handles type casting and null-safe inserts | `INSERT INTO`, `CAST`, `COALESCE` |
| `03_data_quality_checks.sql` | Validates completeness and accuracy — checks for nulls, duplicates, orphan keys, and out-of-range amounts | `COUNT DISTINCT`, `IS NULL`, `CASE WHEN`, integrity checks |
| `04_core_kpis.sql` | Computes platform-level KPIs: GMV, Net Revenue, Margin %, MAU, Avg Ticket Size, and Month-over-Month growth | `SUM`, `AVG`, `LAG()`, Window functions |
| `05_channel_analysis.sql` | Breaks down performance by payment channel (UPI, Wallet, Card, Net Banking) — volume, GMV, revenue, and margin per channel | `GROUP BY`, `RANK()`, `NULLIF`, `ROUND` |
| `06_geo_analysis.sql` | Geographic GMV and transaction distribution across cities and states; identifies top-performing and underperforming regions | `JOIN`, `GROUP BY`, `ORDER BY`, `DENSE_RANK()` |
| `07_user_behavior_dau_mau.sql` | Computes Daily Active Users (DAU), Monthly Active Users (MAU), and the DAU/MAU stickiness ratio over time | `COUNT DISTINCT`, date truncation, Window functions |
| `08_cohort_retention.sql` | Builds a month-0 cohort table and tracks user retention at M1, M3, and M6; feeds the cohort heatmap | Multi-CTE, `JULIANDAY`, date arithmetic |
| `09_rfm_segmentation.sql` | Scores every customer on Recency, Frequency, and Monetary value; assigns RFM tiers (Champions, At-Risk, Lost, etc.) | `NTILE`, percentile thresholds, `CASE WHEN` scoring |
| `10_clv_and_churn_risk.sql` | Estimates Customer Lifetime Value using historical ARPU and retention; flags churn-risk users based on recency thresholds | CTEs, conditional aggregation, `CASE WHEN` tiering |
| `11_cashback_processing_retry_whatif.sql` | Models cashback ROI, payment retry success impact, and six What-If pricing scenarios (MDR ±0.5%, cashback ±0.3%) | `UNION ALL`, `CASE WHEN` arithmetic, scenario modeling |

---

### `02_python/` 

| File | Purpose |
|---|---|
| `00_setup_database.py` | Bootstraps the project: reads CSVs, creates the SQLite DB, runs all SQL KPI scripts programmatically, and exports results to Excel |
| `01_eda_analysis.py` | Generates 9 EDA charts: GMV/revenue trend, MoM growth, channel mix, geo GMV bar chart, transaction amount distribution, user trends, success/retry rates, cashback analysis, and hour-vs-month heatmap |
| `02_statistical_analysis.py` | Runs rigorous statistics: Bootstrap 95% CI for margin, Welch's t-test + Mann-Whitney U for cashback A/B test, Cohen's d effect size, Chi-square repeat rate test, cohort retention heatmap, RFM scatter, CLV Lorenz curve, and churn funnel |
| `upi_analytics.db` | Auto-generated SQLite database — produced by `00_setup_database.py`; stores all fact/dim tables and intermediate query results |

#### `02_python/outputs/eda/` — EDA Charts
| Chart | What it shows |
|---|---|
| `01_gmv_revenue_trend.png` | Monthly GMV and net revenue over time |
| `02_mom_growth.png` | Month-over-month growth rate (%) |
| `03_channel_mix.png` | Transaction share by payment channel |
| `04_geo_gmv.png` | GMV by city/state |
| `05_amount_distribution.png` | Histogram of transaction amounts |
| `06_user_trends.png` | DAU/MAU stickiness over time |
| `07_success_retry.png` | Transaction success vs retry rates |
| `08_cashback_analysis.png` | Cashback spend vs non-cashback spend comparison |
| `09_hour_month_heatmap.png` | Transaction volume heatmap by hour and month |

#### `02_python/outputs/stats/` — Statistical Charts
| Chart | What it shows |
|---|---|
| `01_bootstrap_margin_ci.png` | Bootstrap distribution with 95% CI for platform margin |
| `02_cohort_retention_heatmap.png` | Cohort retention grid M0→M6 |
| `03_rfm_segments.png` | RFM segment scatter (Recency vs Frequency, sized by Monetary) |
| `04_clv_distribution.png` | Customer Lifetime Value distribution |
| `05_churn_risk_funnel.png` | Funnel of active → at-risk → churned users |
| `06_ab_cashback_repeat_rate.png` | A/B test result: repeat rate with vs without cashback |
| `07_channel_margin_ci.png` | Margin confidence intervals by payment channel |

---

### `03_powerbi/`

| File | Purpose |
|---|---|
| `powerbi_dax_and_dashboard_guide.md` | Complete Power BI reference: all DAX measures (GMV, Margin, MAU, Retention Rate, CLV), dashboard layout wireframes for 3 dashboards, and slicer/filter setup guide |

#### Power BI Dashboards (3 Pages)
| Dashboard | Purpose | Key Visuals |
|---|---|---|
| **1. Executive KPI** | Platform health at a glance | KPI cards, GMV trend line, channel mix donut, geo map |
| **2. Customer Behavior** | Retention and engagement deep dive | Cohort heatmap, RFM treemap, churn funnel |
| **3. Revenue Efficiency** | Profitability and scenario planning | Margin by channel, cashback ROI bar, What-If parameter slider |

---

### `outputs/` — Final Exports

| File | Description |
|---|---|
| `01_executive_kpi_dashboard.png` | Exported screenshot of Power BI Executive KPI dashboard |
| `02_channel_analysis.png` | Channel-wise performance breakdown visual |
| `03_geo_analysis.png` | Geographic GMV heatmap / bar chart |

---

## How to Run

```bash
# 1. Install Python dependencies
pip install pandas numpy matplotlib seaborn scipy openpyxl

# 2. Run scripts in order
python 02_python/00_setup_database.py        # Load CSVs → SQLite, export Excel
python 02_python/01_eda_analysis.py          # Generate 9 EDA charts
python 02_python/02_statistical_analysis.py  # Bootstrap, A/B test, CLV, RFM
python 02_python/03_monte_carlo_whatif.py    # Monte Carlo simulation (5,000 runs)

# 3. Open Power BI
# Import upi_analytics.db as a data source
# Apply DAX measures from 03_powerbi/powerbi_dax_and_dashboard_guide.md
```

---

## Key Analytical Findings

1. **Cashback drives measurable behavior change** — A/B test result: cashback users spend 43% more (p < 0.0001, Cohen's d = 0.46). Chi-square confirms a significantly higher repeat transaction rate.

2. **Margin is structurally thin at 0.298%** — Bootstrap 95% CI [0.27%, 0.33%] shows low volatility. A +0.5% MDR increase alone would more than double net revenue.

3. **WALLET channel is the most efficient** — Highest margin at 0.326% despite lower volume. CARD has the lowest margin at 0.274%, suggesting renegotiation opportunity.

4. **Cashback reduction carries real revenue risk** — Monte Carlo simulation shows high variance in net revenue outcomes if cashback is cut without accounting for GMV elasticity.

5. **Top 10% of customers generate disproportionate revenue** — The CLV Lorenz curve confirms Pareto distribution. Champions and Loyal segments (RFM) should be the primary retention investment.

---

## 💼 Business Impact


**1. 💰 Revenue Leakage Identification**
The What-If SQL module quantifies exactly how much revenue is left on the table under current MDR and cashback settings. A `+0.5% MDR` adjustment is shown to more than double net revenue — giving the pricing team a data-backed negotiation lever with merchants and banks.

**2. 🎯 Targeted Customer Retention at Scale**
RFM segmentation and CLV analysis identify which customers are worth retaining *(Champions, Loyalists)* vs which are already lost. This directly reduces wasted cashback spend on low-LTV users and enables hyper-personalized re-engagement campaigns.

**3. 📊 Cashback ROI Accountability**
The A/B test framework *(Welch's t-test + Chi-square)* proves cashback increases spend by **43%** with statistical confidence `(p < 0.0001)`. This transforms cashback from a cost center into a measurable growth lever — justifiable to CFOs with p-values and effect sizes.

**4. 🚨 Early Churn Signal for Proactive Intervention**
The cohort retention and churn risk funnel flag at-risk users before they fully disengage *(M1/M3 drop-off visible in heatmap)*. Product and CRM teams can trigger re-activation nudges at the right moment, improving 6-month retention rates.

**5. 🗺️ Channel Strategy Optimization**
Geo and channel analysis surfaces that `WALLET` generates the highest margin while `CARD` underperforms. This guides partnership prioritization — invest in wallet integrations, renegotiate card MDR, and allocate marketing budget to high-GMV cities with low penetration.

---
