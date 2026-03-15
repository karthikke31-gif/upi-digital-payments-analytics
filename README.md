# UPI Transaction Analytics Project
### 70% SQL | 20% Python | 10% Power BI
#### Real-World Fintech Analytics — No ML, No AI, No DL

---

## Project Results (From Your Data)

| Metric | Value |
|---|---|
| Total GMV | ₹1,42,70,055 |
| Net Revenue | ₹42,531 |
| Platform Margin % | 0.298% |
| Total Transactions | 47,548 |
| Unique Customers | 14,379 |
| Avg Ticket Size | ₹300.12 |
| Cashback Rate | 1.13% of GMV |
| **Cashback A/B Test** | p < 0.0001 — Cashback users spend 43% more |
| **Bootstrap 95% CI** | Margin: [0.27%, 0.33%] |

---

## Folder Structure

```
upi_analytics/
├── README.md
├── upi_analytics.db              ← SQLite database (auto-generated)
│
├── data/                         ← Your CSV source files
│   ├── fact_transactions_50k.csv
│   ├── dim_customer_50k.csv
│   ├── dim_merchant_50k.csv
│   ├── dim_channel_50k.csv
│   ├── dim_city_50k.csv
│   └── dim_date_50k.csv
│
├── sql/                          ← 70% of project work
│   ├── 01_ddl_create_tables.sql
│   ├── 02_etl_data_quality.sql
│   ├── 03_core_kpis.sql
│   ├── 04_channel_geo_analysis.sql
│   ├── 05_cohort_retention.sql
│   ├── 06_rfm_clv_segmentation.sql
│   └── 07_cashback_roi_whatif.sql
│
├── python/                       ← 20% of project work
│   ├── 00_setup_database.py
│   ├── 01_eda_visuals.py
│   └── 02_statistical_analysis.py
│
├── powerbi/
│   └── powerbi_dax_measures.md
│
└── outputs/                      ← All generated files
    ├── kpi_results.xlsx
    ├── 01_executive_kpi_dashboard.png
    ├── 02_channel_analysis.png
    ├── 03_geo_analysis.png
    ├── 04_cohort_retention_heatmap.png
    ├── 05_rfm_segmentation.png
    ├── 06_churn_risk_funnel.png
    ├── 07_dau_mau_stickiness.png
    ├── 08_transaction_quality.png
    ├── 09_bootstrap_margin_ci.png
    ├── 10_ab_test_cashback.png
    ├── 11_monte_carlo_whatif.png
    └── 12_clv_analysis.png
```

---

## How to Run

```bash
# 1. Install dependencies
pip install pandas numpy matplotlib seaborn scipy openpyxl

# 2. Run in order
python python/00_setup_database.py   # Load CSVs → SQLite, export Excel
python python/01_eda_visuals.py      # 8 EDA charts
python python/02_statistical_analysis.py  # Stats + Monte Carlo
```

---

## SQL Files Coverage (70%)

| File | Business Question | SQL Concepts Used |
|---|---|---|
| 01_ddl | Schema design | CREATE, INDEX, FK |
| 02_etl | Data quality | NULL checks, DISTINCT, CASE WHEN |
| 03_kpis | GMV, Revenue, Margin, MAU, MoM | SUM, AVG, COUNT DISTINCT, LAG(), Window |
| 04_channel_geo | Channel Mix, Geo GMV, Efficiency | JOIN, GROUP BY, RANK(), NULLIF |
| 05_cohort | Retention M1/M3/M6, Churn funnel | Multi-CTE, JULIANDAY, date math |
| 06_rfm_clv | RFM Scoring, CLV Pareto | Percentile thresholds, NTILE concept |
| 07_whatif | Cashback ROI, What-If 6 scenarios | UNION ALL, CASE WHEN arithmetic |

---

## Python Coverage (20%)

| Script | What it does |
|---|---|
| 00_setup_database | Loads CSVs → SQLite, runs all SQL KPIs, exports Excel |
| 01_eda_visuals | 8 production-quality charts (GMV trends, channel, cohort heatmap, RFM, churn) |
| 02_statistical_analysis | Bootstrap CI, Welch's t-test, Mann-Whitney U, Cohen's d, Chi-square, Monte Carlo (5000 simulations), CLV Lorenz curve |

---

## Power BI (10%) — 3 Dashboards

| Dashboard | Purpose | Key Visuals |
|---|---|---|
| **1. Executive KPI** (MAIN) | Platform health at a glance | KPI cards, GMV trend, Channel mix pie, Geo map |
| **2. Customer Behavior** | Retention & engagement | Cohort heatmap, RFM treemap, Churn funnel |
| **3. Revenue Efficiency** | Profitability deep dive | Margin by channel, Cashback ROI, What-If slider |

See `powerbi/powerbi_dax_measures.md` for all DAX measures and layout wireframes.

---

## Key Findings (Interview-Ready)

1. **Cashback is driving real behavior**: A/B test shows cashback users spend 43% more (p < 0.0001, Cohen's d = 0.46). Chi-square confirms significantly higher repeat rate.

2. **Margin is thin (0.298%)**: Bootstrap CI [0.27%, 0.33%] — tight band, low volatility. MDR change of +0.5% would more than double net revenue.

3. **WALLET has highest margin** (0.326%) despite lower volume. CARD has lowest (0.274%).

4. **Monte Carlo shows cashback reduction is risky**: Assuming GMV elasticity to cashback exists, the model simulates impact with uncertainty bands.

5. **Top 10% of customers** generate disproportionate revenue (Lorenz curve — Pareto principle holds).

---

## Companies & Roles Targeting This Project

| Company | Role |
|---|---|
| PhonePe, Paytm, Google Pay | Product Analyst, Growth Analyst |
| JPMorgan, Citi, HSBC | Data Analyst — Payments |
| Razorpay, PayU, Pine Labs | Business Analyst |
| NPCI-related | Analytics / Ops Analyst |
| Consulting (EY, Deloitte, KPMG) | Analytics Consultant |
