# ============================================================
# UPI TRANSACTION ANALYTICS — POWER BI DASHBOARD GUIDE
# ============================================================
# File: powerbi_setup_guide.md
# This file tells you EXACTLY what to build in Power BI
# ============================================================


## STEP 1: IMPORT CSV FILES INTO POWER BI

Open Power BI Desktop → Get Data → Text/CSV

Import these files FROM /outputs/powerbi_exports/:
1. 01_monthly_kpi.csv
2. 02_channel_performance.csv
3. 03_monthly_channel_trend.csv
4. 04_geo_gmv.csv
5. 05_dau_mau_stickiness.csv
6. 06_cohort_retention.csv
7. 07_rfm_segments.csv
8. 08_clv_table.csv
9. 09_churn_risk.csv
10. 10_merchant_category.csv
11. 11_cashback_roi.csv
12. 12_whatif_scenarios.csv


## STEP 2: CREATE THESE DAX MEASURES (in any table)

In Power BI → "Modeling" tab → "New Measure"

--- CORE KPIs ---

Total GMV =
    SUM('01_monthly_kpi'[gmv])

Total Net Revenue =
    SUM('01_monthly_kpi'[net_revenue])

Overall Margin % =
    DIVIDE([Total Net Revenue], [Total GMV]) * 100

Total Cashback Cost =
    SUM('01_monthly_kpi'[cashback_cost])

Total Processing Cost =
    SUM('01_monthly_kpi'[processing_cost])

--- USER METRICS ---

Total MAU =
    SUM('01_monthly_kpi'[mau])

Average MAU =
    AVERAGE('01_monthly_kpi'[mau])

Average Stickiness % =
    AVERAGE('05_dau_mau_stickiness'[stickiness_pct])

--- CHANNEL METRICS ---

UPI GMV Share % =
    DIVIDE(
        CALCULATE(SUM('02_channel_performance'[gmv]),
                  '02_channel_performance'[channel_name] = "UPI"),
        SUM('02_channel_performance'[gmv])
    ) * 100

Best Efficiency Channel =
    TOPN(1,
        SUMMARIZE('02_channel_performance',
                  '02_channel_performance'[channel_name],
                  "Eff", AVERAGE('02_channel_performance'[efficiency_ratio])),
        [Eff], DESC)

--- CASHBACK ROI ---

Cashback ROI (GMV per ₹1 Cashback) =
    DIVIDE(
        SUM('11_cashback_roi'[gmv]),
        SUM('11_cashback_roi'[cashback_cost])
    )

--- GROWTH ---

Latest Month MoM Revenue Growth % =
    LASTNONBLANK('01_monthly_kpi'[rev_mom_growth_pct],
                 '01_monthly_kpi'[rev_mom_growth_pct])

--- CHURN ---

High Risk Customer Count =
    CALCULATE(
        COUNT('09_churn_risk'[customer_id]),
        '09_churn_risk'[churn_risk] = "High Risk"
    )

At Risk GMV (High Risk) =
    CALCULATE(
        SUM('09_churn_risk'[total_gmv]),
        '09_churn_risk'[churn_risk] = "High Risk"
    )

--- WHAT-IF (use Power BI What-If Parameter) ---

-- Create a What-If parameter: "Cashback_Reduction" (0 to 50, increment 5)
-- Create a What-If parameter: "MDR_Increase" (0 to 1, increment 0.25)

Projected Net Revenue (What-If) =
    CALCULATE(
        AVERAGE('12_whatif_scenarios'[projected_net_revenue]),
        '12_whatif_scenarios'[cashback_reduction_pct] = [Cashback_Reduction Value],
        '12_whatif_scenarios'[mdr_increase_pct] = [MDR_Increase Value]
    )


## STEP 3: BUILD THE 3 DASHBOARD PAGES

=================================================================
DASHBOARD 1: EXECUTIVE KPI OVERVIEW (Main Dashboard — Most Important)
=================================================================

LAYOUT:
┌─────────────────────────────────────────────────────────────┐
│  SLICERS: Month (multi-select)  |  Channel  |  City Tier    │
├────────────┬────────────┬────────────┬────────────┬──────────┤
│  Total GMV │ Net Revenue│  Margin %  │    MAU     │ Sticky % │
│  ₹14.27M   │  ₹42.5K   │  0.30%     │  ~1,200    │  xx.x%  │
├────────────┴────────────┴────────────┴────────────┴──────────┤
│  [LINE CHART] GMV & Net Revenue by Month (dual axis)         │
│  Left axis = GMV bars, Right axis = Net Revenue line         │
├───────────────────────────────┬─────────────────────────────┤
│  [BAR CHART] MoM GMV Growth % │ [PIE CHART] Channel Mix GMV │
│  Color: Green=positive         │ UPI / CARD / WALLET / NB   │
│         Red=negative           │                             │
├───────────────────────────────┴─────────────────────────────┤
│  [MAP or BAR] Geo GMV by State — Top 10 States Horizontal    │
└─────────────────────────────────────────────────────────────┘

VISUALS TO USE:
1. KPI Cards (5x) — GMV, Net Revenue, Margin%, MAU, Stickiness
2. Clustered Bar + Line (combo) — Monthly GMV trend
3. Bar Chart — MoM Growth %
4. Donut Chart — Channel GMV Share
5. Bar Chart — Top 10 States GMV
6. Slicers — Month, Channel, Tier

DATA SOURCES:
- 01_monthly_kpi.csv → all trend charts
- 02_channel_performance.csv → channel pie
- 04_geo_gmv.csv → geo bar


=================================================================
DASHBOARD 2: CUSTOMER BEHAVIOR & RETENTION
=================================================================

LAYOUT:
┌─────────────────────────────────────────────────────────────┐
│  SLICERS: Month  |  Segment Tag  |  City Tier               │
├───────────────┬──────────────────┬──────────────────────────┤
│  Total Active │ High Churn Risk  │  Avg Stickiness %        │
│  Users        │ Customers        │                          │
├───────────────┴──────────────────┴──────────────────────────┤
│  [MATRIX/HEATMAP] Cohort Retention — Use Conditional Format  │
│  Rows = Cohort Month, Cols = Months Since Start (0–11)       │
│  Values = Retention %, Color scale: Red (low) → Green (high)│
├───────────────────────────────┬─────────────────────────────┤
│  [STACKED BAR] New vs Returning│  [BAR] RFM Segments         │
│  Users per Month               │  Customer Count by Segment │
├───────────────────────────────┴─────────────────────────────┤
│  [FUNNEL CHART] Churn Risk Funnel                            │
│  Active → Slipping → Medium Risk → High Risk                 │
└─────────────────────────────────────────────────────────────┘

VISUALS TO USE:
1. KPI Cards (3x) — Active Users, High Risk Count, Stickiness
2. Matrix with Conditional Formatting — Cohort Retention Heatmap
3. Stacked Bar — New vs Returning Users
4. Bar Chart — RFM Segment Customer Count
5. Funnel — Churn Risk progression
6. Scatter Plot (optional) — CLV vs Frequency per customer

CONDITIONAL FORMAT FOR COHORT HEATMAP:
- In Matrix visual → Retention % values
- Format → Background color → Color scale
  Min: 0% = Red (#E74C3C)
  Mid: 50% = Yellow (#F39C12)
  Max: 100% = Green (#2ECC71)

DATA SOURCES:
- 06_cohort_retention.csv → heatmap
- 07_rfm_segments.csv → RFM bars
- 09_churn_risk.csv → funnel
- 05_dau_mau_stickiness.csv → stickiness card


=================================================================
DASHBOARD 3: REVENUE & COST EFFICIENCY
=================================================================

LAYOUT:
┌─────────────────────────────────────────────────────────────┐
│  SLICERS: Month  |  Channel  |  Merchant Category           │
├──────────────┬──────────────┬──────────────┬────────────────┤
│  Total       │  Cashback    │  Processing  │  Cashback ROI  │
│  Cashback    │  as % GMV    │  Cost/Txn    │  (GMV/Cashback)│
├──────────────┴──────────────┴──────────────┴────────────────┤
│  [CLUSTERED BAR] Channel: Net Revenue vs Cost               │
│  Two bars per channel: Net Revenue (blue) vs Total Cost (red)│
├───────────────────────────────┬─────────────────────────────┤
│  [TABLE] Channel Efficiency   │  [LINE] Cashback ROI Trend  │
│  Channel | Net Rev | Cost |   │  x=Month, y=GMV per ₹1 Cash │
│  Efficiency Ratio | Margin %  │                             │
├───────────────────────────────┴─────────────────────────────┤
│  [WHAT-IF SECTION]                                           │
│  Sliders: Cashback Reduction % | MDR Increase %             │
│  KPI Cards: Projected Revenue | Projected Margin | Uplift   │
└─────────────────────────────────────────────────────────────┘

VISUALS TO USE:
1. KPI Cards (4x) — Cashback Total, Cashback % GMV, Cost/Txn, ROI
2. Clustered Bar — Channel Revenue vs Cost comparison
3. Table — Channel Efficiency with Conditional Format on margin%
4. Line Chart — Cashback ROI trend monthly
5. What-If sliders → Projected Revenue KPI card
6. Bar Chart — Merchant Category Margin %

WHAT-IF SLICERS SETUP:
- Go to Modeling → New Parameter
- Name: Cashback_Reduction, Range: 0 to 50, Step: 5
- Name: MDR_Increase, Range: 0 to 1, Step: 0.25
- These auto-create a slicer — connect to 12_whatif_scenarios.csv

DATA SOURCES:
- 02_channel_performance.csv → channel efficiency table & bars
- 11_cashback_roi.csv → cashback ROI line chart
- 10_merchant_category.csv → merchant bar chart
- 12_whatif_scenarios.csv → what-if section


## STEP 4: FORMATTING TIPS FOR PROFESSIONAL LOOK

COLORS TO USE (Fintech dark theme):
- Primary: #1E3A5F (Navy Blue)
- Accent 1: #00C4B4 (Teal/Green) — positive metrics
- Accent 2: #FF6B6B (Coral/Red) — negative/risk metrics
- Neutral: #F5F6FA (Light background)
- Text: #2C3E50

FONT:
- Title: Segoe UI Bold, 14pt
- KPI Values: DIN Bold, 24pt
- Table text: Segoe UI, 10pt

KPI CARD FORMAT:
- Large number (center) + subtitle below
- Conditional icon: ▲ green for growth, ▼ red for decline
- Thin border, shadow off

SLICER STYLE:
- Style: Tile (pill shape) — looks modern
- Or Dropdown for months with many values

PAGE NAVIGATION:
- Add 3 navigation buttons at top of each page
- "Executive Overview" | "User Behavior" | "Revenue Efficiency"
- Bookmark Actions for smooth navigation


## STEP 5: INTERVIEW TALKING POINTS

When presenting Dashboard 1:
"GMV grew consistently with UPI dominating at 70% of volume.
 However, margin is compressed due to cashback costs,
 which I analyzed in detail in the Revenue dashboard."

When presenting Dashboard 2:
"Cohort retention shows [X]% of users return after month 3.
 RFM shows Champions generate disproportionate revenue —
 18% of customers generate 62% of net revenue.
 High-risk churn segment holds ₹6.6M in at-risk GMV."

When presenting Dashboard 3:
"UPI is cheapest to process but the Efficiency Ratio shows
 Cards generate better net margin per cost rupee.
 The What-If shows reducing cashback by 20% + raising MDR
 by 0.5% would add ~₹X in net revenue with minimal GMV impact."
