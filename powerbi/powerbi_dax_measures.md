# ============================================================
# FILE: powerbi_dax_measures.md
# PURPOSE: All DAX Measures + Data Model Setup for Power BI
# DASHBOARDS: Executive KPI | Customer Behavior | Revenue Efficiency
# ============================================================

## 1. DATA MODEL SETUP IN POWER BI

### Tables to Import
- fact_transactions (from SQLite DB or CSV)
- dim_customer
- dim_merchant
- dim_channel
- dim_city
- dim_date

### Relationships (Star Schema)
```
fact_transactions[customer_id]  → dim_customer[customer_id]    (Many-to-1)
fact_transactions[merchant_id]  → dim_merchant[merchant_id]    (Many-to-1)
fact_transactions[channel_id]   → dim_channel[channel_id]      (Many-to-1)
fact_transactions[city_id]      → dim_city[city_id]            (Many-to-1)
fact_transactions[txn_date]     → dim_date[date]               (Many-to-1)
```
**Cross filter direction: Single for all relationships**

---

## 2. CORE DAX MEASURES

### A. GMV & Revenue Measures
```dax
-- Total GMV
Total GMV = 
CALCULATE(
    SUMX(fact_transactions, fact_transactions[amount]),
    fact_transactions[status] = "SUCCESS"
)

-- Gross MDR Income
Gross MDR Income = 
CALCULATE(
    SUMX(fact_transactions, (fact_transactions[mdr_pct] / 100) * fact_transactions[amount]),
    fact_transactions[status] = "SUCCESS"
)

-- Total Cashback Cost
Total Cashback = 
CALCULATE(
    SUM(fact_transactions[cashback_amt]),
    fact_transactions[status] = "SUCCESS"
)

-- Total Processing Cost
Total Processing Cost = 
CALCULATE(
    SUM(fact_transactions[processing_fee_amt]),
    fact_transactions[status] = "SUCCESS"
)

-- Net Revenue
Net Revenue = [Gross MDR Income] - [Total Cashback] - [Total Processing Cost]

-- Margin %
Margin % = 
DIVIDE([Net Revenue], [Total GMV], 0) * 100

-- Avg Transaction Value
Avg Ticket Size = 
CALCULATE(
    AVERAGEX(fact_transactions, fact_transactions[amount]),
    fact_transactions[status] = "SUCCESS"
)
```

### B. User Activity Measures
```dax
-- MAU (Monthly Active Users)
MAU = 
CALCULATE(
    DISTINCTCOUNT(fact_transactions[customer_id]),
    fact_transactions[status] = "SUCCESS",
    DATESINPERIOD(dim_date[date], MAX(dim_date[date]), -30, DAY)
)

-- Total Unique Customers
Unique Customers = 
CALCULATE(
    DISTINCTCOUNT(fact_transactions[customer_id]),
    fact_transactions[status] = "SUCCESS"
)

-- Daily Active Users (for selected day)
DAU = 
CALCULATE(
    DISTINCTCOUNT(fact_transactions[customer_id]),
    fact_transactions[status] = "SUCCESS"
)

-- Average DAU in period
Avg DAU = 
AVERAGEX(
    VALUES(dim_date[date]),
    CALCULATE(
        DISTINCTCOUNT(fact_transactions[customer_id]),
        fact_transactions[status] = "SUCCESS"
    )
)

-- Stickiness Ratio
Stickiness % = 
DIVIDE([Avg DAU], [Unique Customers], 0) * 100

-- Total Transactions
Total Transactions = 
CALCULATE(
    COUNT(fact_transactions[transaction_id]),
    fact_transactions[status] = "SUCCESS"
)

-- Transactions per User
Txns Per User = 
DIVIDE([Total Transactions], [Unique Customers], 0)
```

### C. MoM Growth Measures
```dax
-- Previous Month GMV
Prev Month GMV = 
CALCULATE(
    [Total GMV],
    DATEADD(dim_date[date], -1, MONTH)
)

-- GMV MoM Growth %
GMV MoM Growth % = 
DIVIDE(
    [Total GMV] - [Prev Month GMV],
    [Prev Month GMV],
    BLANK()
) * 100

-- Previous Month Revenue
Prev Month Revenue = 
CALCULATE(
    [Net Revenue],
    DATEADD(dim_date[date], -1, MONTH)
)

-- Revenue MoM Growth %
Revenue MoM Growth % = 
DIVIDE(
    [Net Revenue] - [Prev Month Revenue],
    [Prev Month Revenue],
    BLANK()
) * 100

-- Previous Month MAU
Prev Month MAU = 
CALCULATE(
    [Unique Customers],
    DATEADD(dim_date[date], -1, MONTH)
)

-- MAU MoM Growth %
MAU MoM Growth % = 
DIVIDE(
    [Unique Customers] - [Prev Month MAU],
    [Prev Month MAU],
    BLANK()
) * 100
```

### D. Channel Efficiency Measures
```dax
-- Net Revenue by Channel
Channel Net Revenue = 
CALCULATE(
    [Net Revenue],
    ALLEXCEPT(dim_channel, dim_channel[channel_name])
)

-- Channel Cost
Channel Total Cost = [Total Cashback] + [Total Processing Cost]

-- Channel Efficiency Ratio
Channel Efficiency Ratio = 
DIVIDE([Net Revenue], [Channel Total Cost], 0)

-- Channel GMV Share %
Channel GMV Share % = 
DIVIDE([Total GMV], CALCULATE([Total GMV], ALL(dim_channel)), 0) * 100
```

### E. Cashback ROI Measures
```dax
-- GMV per Cashback Rupee
GMV per Cashback Rupee = 
DIVIDE([Total GMV], [Total Cashback], 0)

-- Cashback Rate %
Cashback Rate % = 
DIVIDE([Total Cashback], [Total GMV], 0) * 100

-- Transactions with Cashback
Cashback Transactions = 
CALCULATE(
    COUNT(fact_transactions[transaction_id]),
    fact_transactions[status] = "SUCCESS",
    fact_transactions[cashback_amt] > 0
)

-- Cashback Coverage %
Cashback Coverage % = 
DIVIDE([Cashback Transactions], [Total Transactions], 0) * 100
```

### F. What-If Parameters (Power BI Parameter Sliders)
```dax
-- Create What-If Parameter: "MDR Change" from -1 to +1, increment 0.1
-- This creates: MDR Change[MDR Change Value]

-- Simulated Net Revenue with MDR Change
Simulated Net Revenue = 
SUMX(
    FILTER(fact_transactions, fact_transactions[status] = "SUCCESS"),
    ((fact_transactions[mdr_pct] + 'MDR Change'[MDR Change Value]) / 100) 
    * fact_transactions[amount]
    - fact_transactions[cashback_amt]
    - fact_transactions[processing_fee_amt]
)

-- Create What-If Parameter: "Cashback Reduction" from 0 to 50%, increment 5%
-- This creates: Cashback Reduction[Cashback Reduction Value]

-- Simulated Revenue with Cashback Reduction
Simulated Revenue CB Reduction = 
SUMX(
    FILTER(fact_transactions, fact_transactions[status] = "SUCCESS"),
    (fact_transactions[mdr_pct] / 100) * fact_transactions[amount]
    - fact_transactions[cashback_amt] * (1 - 'Cashback Reduction'[Cashback Reduction Value] / 100)
    - fact_transactions[processing_fee_amt]
)

-- Simulated Margin %
Simulated Margin % = 
DIVIDE([Simulated Revenue CB Reduction], [Total GMV], 0) * 100

-- Revenue Uplift vs Base
Revenue Uplift = [Simulated Revenue CB Reduction] - [Net Revenue]
```

---

## 3. DASHBOARD LAYOUT GUIDE

### Dashboard 1: Executive KPI Overview (MAIN)
```
┌─────────────────────────────────────────────────────────────┐
│  FILTERS: [Date Range] [Channel] [City Tier]                │
├────────────┬────────────┬────────────┬────────────┬─────────┤
│  Total GMV │Net Revenue │  Margin %  │    MAU     │ MoM GMV │
│  ₹XXX.XM   │  ₹XX.XM   │   X.XX%    │   XX,XXX   │  +X.X%  │
├─────────────────────────────┬───────────────────────────────┤
│  LINE: Monthly GMV Trend    │  BAR: GMV by Channel (stacked)│
│  + Net Revenue overlay      │  UPI | CARD | WALLET | NB     │
├─────────────────────────────┼───────────────────────────────┤
│  AREA: MAU + DAU Trend      │  MAP: Geo GMV by State        │
│  + Stickiness line          │  (filled map, darker = more)  │
└─────────────────────────────┴───────────────────────────────┘
```

### Dashboard 2: Customer Behavior & Retention
```
┌─────────────────────────────────────────────────────────────┐
│  FILTERS: [Cohort Month] [Segment] [Channel]                │
├────────────┬────────────┬────────────┬────────────┬─────────┤
│New Customers│ Stickiness │ M1 Retent. │ M3 Retent. │ Churn % │
│   X,XXX    │   XX.X%    │   XX.X%    │   XX.X%    │  XX.X%  │
├─────────────────────────────┬───────────────────────────────┤
│  MATRIX: Cohort Heatmap     │  TREEMAP: RFM Segments        │
│  Rows=Cohort, Cols=Month+n  │  Champions | Loyal | New...   │
│  Color=Retention %          │  Size=Revenue, Color=Segment  │
├─────────────────────────────┼───────────────────────────────┤
│  BAR: New vs Returning      │  FUNNEL: Churn Risk           │
│  Users (stacked, monthly)   │  ACTIVE→AT_RISK→HIGH→CHURNED  │
└─────────────────────────────┴───────────────────────────────┘
```

### Dashboard 3: Revenue & Cost Efficiency
```
┌─────────────────────────────────────────────────────────────┐
│  FILTERS: [Date Range] [Channel] [Acquirer]                 │
├────────────┬────────────┬────────────┬────────────┬─────────┤
│Channel Eff.│ Cashback   │Processing  │ Rev/User   │Margin % │
│   X.XXx    │  ₹X.XM     │  ₹X.XM     │  ₹XXX      │  X.XX%  │
├─────────────────────────────┬───────────────────────────────┤
│ BAR: Margin % by Channel    │  WHAT-IF: Cashback Slider     │
│ (with platform avg line)    │  Slider → Simulated Revenue   │
│                             │  + Margin change card         │
├─────────────────────────────┼───────────────────────────────┤
│ STACKED BAR: GMV vs Cost    │  LINE: Cashback ROI trend     │
│ MDR Income | CB | Proc      │  GMV per ₹1 Cashback (monthly)│
└─────────────────────────────┴───────────────────────────────┘
```

---

## 4. WHAT-IF PARAMETER SETUP (Step by Step)

```
1. Go to Modeling tab → New Parameter
2. Name: "Cashback Reduction %"
   Min: 0, Max: 50, Increment: 5, Default: 0
3. Check "Add slicer to this page"
4. Use [Cashback Reduction Value] in DAX measures
5. Create KPI cards showing Simulated vs Baseline revenue
```

---

## 5. FORMATTING TIPS

### Color Theme
- Primary Blue: #0057FF
- Success Green: #00C49A
- Warning Orange: #FF6B35
- Accent Yellow: #FFB300
- Background: #F8F9FA
- Cards: White with subtle shadow

### KPI Cards
- Use conditional formatting: Green if MoM > 0, Red if < 0
- Add trend indicator arrows (▲ ▼)
- Format GMV as ₹X.XXM or ₹X.XXK

### Cohort Heatmap
- Use Matrix visual
- Apply diverging color scale (Red 0% → Yellow 50% → Green 100%)
- Add data labels showing retention %

### Slicers
- Channel: Dropdown (UPI/CARD/WALLET/NETBANKING/All)
- Date: Between date picker
- City Tier: Checkbox list (Tier-1/Tier-2/Tier-3)
```
