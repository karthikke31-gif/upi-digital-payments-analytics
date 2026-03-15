# UPI Analytics — Power BI Dashboard Guide
## DAX Measures, Page Layouts & Implementation Notes

---

## HOW TO IMPORT DATA INTO POWER BI

1. Open Power BI Desktop → **Get Data → Text/CSV**
2. Import these 6 files from the `data/` folder:
   - `fact_transactions.csv`
   - `dim_customer.csv`
   - `dim_merchant.csv`
   - `dim_channel.csv`
   - `dim_city.csv`
   - `dim_date.csv`
3. Go to **Model view** and create relationships:
   - `fact_transactions[channel_id]`   → `dim_channel[channel_id]`   (Many-to-One)
   - `fact_transactions[city_id]`      → `dim_city[city_id]`         (Many-to-One)
   - `fact_transactions[customer_id]`  → `dim_customer[customer_id]` (Many-to-One)
   - `fact_transactions[merchant_id]`  → `dim_merchant[merchant_id]` (Many-to-One)
   - `fact_transactions[txn_date]`     → `dim_date[date]`            (Many-to-One)

---

## ALL DAX MEASURES

Paste these into Power BI's "New Measure" dialog.

### Base Measures

```dax
Total GMV =
    CALCULATE(
        SUM(fact_transactions[amount]),
        fact_transactions[status] = "SUCCESS"
    )

Total Net Revenue =
    CALCULATE(
        SUMX(
            fact_transactions,
            (fact_transactions[mdr_pct] / 100) * fact_transactions[amount]
            - fact_transactions[cashback_amt]
            - fact_transactions[processing_fee_amt]
        ),
        fact_transactions[status] = "SUCCESS"
    )

Total Cashback =
    CALCULATE(
        SUM(fact_transactions[cashback_amt]),
        fact_transactions[status] = "SUCCESS"
    )

Total Processing Cost =
    CALCULATE(
        SUM(fact_transactions[processing_fee_amt]),
        fact_transactions[status] = "SUCCESS"
    )

Total Transactions =
    CALCULATE(
        COUNTROWS(fact_transactions),
        fact_transactions[status] = "SUCCESS"
    )
```

### KPI Measures

```dax
Margin % =
    DIVIDE([Total Net Revenue], [Total GMV], 0) * 100

Avg Transaction Value =
    DIVIDE([Total GMV], [Total Transactions], 0)

Success Rate % =
    DIVIDE(
        CALCULATE(COUNTROWS(fact_transactions), fact_transactions[status] = "SUCCESS"),
        COUNTROWS(fact_transactions),
        0
    ) * 100

Cashback % of GMV =
    DIVIDE([Total Cashback], [Total GMV], 0) * 100

Processing Cost % of GMV =
    DIVIDE([Total Processing Cost], [Total GMV], 0) * 100

Channel Efficiency Ratio =
    DIVIDE(
        [Total Net Revenue],
        [Total Cashback] + [Total Processing Cost],
        0
    )
```

### Time Intelligence Measures

```dax
MAU =
    CALCULATE(
        DISTINCTCOUNT(fact_transactions[customer_id]),
        fact_transactions[status] = "SUCCESS",
        DATESINPERIOD(dim_date[date], MAX(dim_date[date]), -30, DAY)
    )

DAU =
    CALCULATE(
        DISTINCTCOUNT(fact_transactions[customer_id]),
        fact_transactions[status] = "SUCCESS"
    )

Stickiness Ratio =
    DIVIDE([DAU], [MAU], 0) * 100

GMV MoM Growth % =
    VAR current_month_gmv = [Total GMV]
    VAR prev_month_gmv =
        CALCULATE(
            [Total GMV],
            DATEADD(dim_date[date], -1, MONTH)
        )
    RETURN
    DIVIDE(current_month_gmv - prev_month_gmv, prev_month_gmv, 0) * 100

Revenue MoM Growth % =
    VAR current = [Total Net Revenue]
    VAR prev =
        CALCULATE(
            [Total Net Revenue],
            DATEADD(dim_date[date], -1, MONTH)
        )
    RETURN
    DIVIDE(current - prev, prev, 0) * 100

GMV YTD =
    TOTALYTD([Total GMV], dim_date[date])

Revenue YTD =
    TOTALYTD([Total Net Revenue], dim_date[date])
```

### What-If Parameters (Create in Power BI)

```
1. Go to Modeling → New Parameter
2. Name: MDR Adjustment (%)
   Type: Decimal Number
   Min: -1, Max: 2, Increment: 0.25, Default: 0

3. Name: Cashback Reduction (%)
   Type: Whole Number
   Min: 0, Max: 50, Increment: 5, Default: 0
```

```dax
-- Use these measures with slicers:

Projected Revenue (MDR What-If) =
    CALCULATE(
        SUMX(
            FILTER(fact_transactions, fact_transactions[status] = "SUCCESS"),
            ((fact_transactions[mdr_pct] + 'MDR Adjustment (%)'[MDR Adjustment (%) Value]) / 100)
            * fact_transactions[amount]
            - fact_transactions[cashback_amt]
            - fact_transactions[processing_fee_amt]
        )
    )

Projected Revenue (Cashback What-If) =
    CALCULATE(
        SUMX(
            FILTER(fact_transactions, fact_transactions[status] = "SUCCESS"),
            (fact_transactions[mdr_pct] / 100) * fact_transactions[amount]
            - fact_transactions[cashback_amt] * (1 - 'Cashback Reduction (%)'[Cashback Reduction (%) Value] / 100)
            - fact_transactions[processing_fee_amt]
        )
    )

Revenue Uplift (What-If) =
    [Projected Revenue (Cashback What-If)] - [Total Net Revenue]
```

---

## DASHBOARD 1 — Executive KPI Overview ⭐ (MAIN)

### Layout (Left to Right, Top to Bottom):

```
Row 1: KPI Cards (6 cards, equal width)
  ┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐
  │  Total GMV   │ Net Revenue  │  Margin %    │     MAU      │     DAU      │  MoM Growth  │
  │  [Card]      │  [Card]      │  [Card]      │  [Card]      │  [Card]      │  [Card]      │
  └──────────────┴──────────────┴──────────────┴──────────────┴──────────────┴──────────────┘

Row 2: Charts (3 visuals)
  ┌─────────────────────────────┬─────────────────────┬─────────────────────┐
  │  Monthly GMV & Revenue      │  Channel GMV Mix    │  Geo Map            │
  │  (Line + Column combo)      │  (Donut Chart)      │  (Filled Map)       │
  │  X: Month, Y1: GMV, Y2: Rev │  Dim: channel_name  │  Field: state       │
  │  [Clustered Column + Line]  │  Value: Total GMV   │  Value: Total GMV   │
  └─────────────────────────────┴─────────────────────┴─────────────────────┘

Row 3: Table + Slicers
  ┌────────────────────────────────────────────┬──────────────────────────────────┐
  │  Monthly KPI Table                         │  Slicers                         │
  │  Cols: Month | GMV | Revenue | Margin% |   │  • Date (month slicer)           │
  │  MAU | MoM%                                │  • Channel (dropdown)            │
  │  [Table visual]                            │  • City Tier (checkbox)          │
  └────────────────────────────────────────────┴──────────────────────────────────┘
```

**Insight callout boxes to add:**
- "GMV highest in Q3 — peak season driven by UPI"
- "Margin % trend: declining due to cashback increase"

---

## DASHBOARD 2 — Customer Behavior & Retention

### Layout:

```
Row 1: KPI Cards
  ┌──────────────┬──────────────┬──────────────┬──────────────┐
  │  Total Users │  New Users   │ Return Users │  Stickiness  │
  └──────────────┴──────────────┴──────────────┴──────────────┘

Row 2: Main Charts
  ┌────────────────────────────────┬────────────────────────────┐
  │  Cohort Retention Heatmap      │  RFM Segmentation Treemap  │
  │  (Matrix visual)               │  (Treemap)                 │
  │  Rows: cohort month            │  Category: segment         │
  │  Cols: months_since (0–11)     │  Values: user count, GMV   │
  │  Values: retention %           │                            │
  └────────────────────────────────┴────────────────────────────┘

Row 3: Trend + Bar
  ┌────────────────────────────────┬────────────────────────────┐
  │  DAU/MAU Trend (Line Chart)    │  Churn Risk Funnel (Bar)   │
  │  X: Month, Y: DAU, MAU        │  Category: risk label      │
  │  Add: Stickiness % line        │  Values: user count        │
  └────────────────────────────────┴────────────────────────────┘
```

**NOTE on Cohort Matrix**: 
You'll need to create a calculated column for `cohort_month` and `months_since_first_txn` in Power Query (M language):

```m
// In Power Query - fact_transactions table:
// Step 1: Add cohort_month column
= Table.AddColumn(Source, "cohort_month", each
    Text.From(Date.Year([txn_date])) & "-" &
    Text.PadStart(Text.From(Date.Month([txn_date])), 2, "0"))
```

---

## DASHBOARD 3 — Revenue & Cost Efficiency

### Layout:

```
Row 1: KPI Cards
  ┌────────────────┬────────────────┬────────────────┬────────────────┐
  │  Net Revenue   │ Cashback Cost  │  Proc. Cost    │  Eff. Ratio    │
  └────────────────┴────────────────┴────────────────┴────────────────┘

Row 2: Main Charts
  ┌────────────────────────────┬────────────────────────────┐
  │  Margin % by Channel       │  Cashback vs Net Revenue   │
  │  (Bar Chart)               │  (Scatter Plot)            │
  │  X: channel_name           │  X: cashback_amt monthly   │
  │  Y: Margin %               │  Y: net_revenue monthly    │
  └────────────────────────────┴────────────────────────────┘

Row 3: What-If Simulation
  ┌────────────────────────────────────────────────────────────┐
  │  What-If Slicers + KPI Cards                               │
  │  • MDR Adjustment slicer → Projected Revenue card          │
  │  • Cashback Reduction slicer → Revenue Uplift card         │
  │  • Waterfall chart: Base Rev → Cashback Impact → Proj Rev  │
  └────────────────────────────────────────────────────────────┘

Row 4: Breakdown Table
  ┌────────────────────────────────────────────────────────────┐
  │  Channel Efficiency Table                                   │
  │  Cols: Channel | GMV | Net Revenue | Cashback | Proc Cost  │
  │        | Efficiency Ratio | Margin %                       │
  └────────────────────────────────────────────────────────────┘
```

---

## POWER BI FORMATTING TIPS

### Color Palette (consistent across all pages):
| Element               | Color     |
|-----------------------|-----------|
| UPI                   | #1f77b4   |
| CARD                  | #ff7f0e   |
| WALLET                | #2ca02c   |
| NB (Net Banking)      | #d62728   |
| Positive KPI / GMV    | #1f77b4   |
| Negative / Cost       | #d62728   |
| Neutral               | #aec7e8   |

### Conditional Formatting:
- Margin % card: Red if < 0.5%, Amber if 0.5%–1%, Green if > 1%
- MoM Growth card: Red if negative, Green if positive
- Cohort retention: Green (high) → Red (low) gradient

### Slicers to Add (all 3 pages):
- Date Hierarchy (Year → Month)
- Channel Name (dropdown)
- City Tier (checkbox)
- Device OS (dropdown)

---

## POWER QUERY TRANSFORMATIONS (M Language)

```m
// Add net_revenue column in Power Query
= Table.AddColumn(
    Source,
    "net_revenue",
    each ([mdr_pct] / 100) * [amount] - [cashback_amt] - [processing_fee_amt],
    type number
)

// Convert status to boolean success flag
= Table.AddColumn(
    Source,
    "is_success",
    each if [status] = "SUCCESS" then 1 else 0,
    Int64.Type
)
```

---

## INTERVIEW ANSWER TEMPLATE

When asked about your Power BI work:

> "I built three Power BI pages using data from a 50,000-row UPI transaction star schema.
> The first page is an Executive KPI overview with six KPI cards — GMV, Net Revenue, Margin,
> MAU, DAU, and MoM Growth — supported by a monthly trend combo chart, channel donut, and
> geo-filled map. The second page shows customer behaviour with a cohort retention heatmap
> built using a calculated months_since_cohort column, an RFM treemap, and a churn risk
> funnel. The third page is profitability analysis with margin by channel, a cashback scatter
> plot, and two What-If parameter slicers that let any stakeholder simulate MDR increases or
> cashback reductions and instantly see the projected revenue impact. All measures are written
> in DAX and the model uses a proper star schema with five dimension tables."

---
*End of Power BI Guide*
