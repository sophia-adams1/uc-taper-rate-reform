# UC Taper Rate Reform: Did Lower-Pay Areas Work More After December 2021?

**A test of whether the substitution effect or income effect dominated after the UK Universal Credit taper rate was cut from 63% to 55%.**

## Question

In December 2021, the UK government cut the Universal Credit taper rate, the
rate at which benefit is withdrawn as claimants earn more, from 63% to 55%.
Using economic theory, we can predict two competing responses: a **substitution effect** (work now
pays relatively more, so claimants work more) and an **income effect**
(claimants keep more of their existing pay, so some may work less for the
same take-home income). This project tests which force actually dominated,
using local-authority-level administrative data.

## Finding

After correcting a data-processing bug that had initially produced a false
"significant" result (see *What I caught*, below): **claimant counts rose
significantly in lower-pay areas after the reform, for both in-employment and
not-in-employment claimants (p=0.03 and p=0.04). But, the overall employment
*share* did not move significantly (p=0.48).** The most defensible reading is
broader UC caseload growth in lower-pay areas, plausibly linked to 2022
cost-of-living pressures, rather than a genuine shift in the underlying
employment rate. The data does not support a clean "substitution effect won"
story, and says so explicitly, rather than overstating a marginal result.

## Key Components / Themes of the Project:

- **SQL**: multi-table joins, geography crosswalks, `CASE WHEN` recoding, window-style aggregation, staged temp-table pipelines (PostgreSQL)
- **R**: `tidyverse`, `fixest` (high-dimensional fixed effects, clustered SEs, event-study `i()` syntax), `modelsummary`, `lubridate`
- **Causal inference**: two-way fixed effects DiD, event-study specification, formal parallel pre-trends testing
- **HM Treasury Magenta Book**: evaluation design, addressing identification threats explicitly
- **Real government data infrastructure**: DWP Stat-Xplore, ONS NOMIS/APS, ASHE - sourcing, navigating, and troubleshooting live administrative data exports
- **Messy real-world data handling**: Windows-1252 encoding, ONS small-sample suppression markers, embedded multi-year exports, post-2023 local government boundary reorganisation

## Data sources

| Source | What it provides |
|---|---|
| DWP Stat-Xplore | Monthly UC claimant counts by local authority, by employment status |
| NOMIS (Annual Population Survey) | Local authority employment rate, 2021 & 2022 |
| ONS ASHE | Local authority median hourly pay and weekly hours, 2021 (pre-reform) |
| ONS Geography Lookup | Output Area → Local Authority → Travel-to-Work Area crosswalk |

## Method

Areas are split into "higher exposure" and "lower exposure" groups based on
their **2021 (pre-reform) median hourly pay**. This is a fixed, time-invariant
classification, deliberately never updated with 2022 data, so the treatment
group cannot be influenced by outcomes the policy itself may have shifted.
Standard errors are clustered at Travel-to-Work Area, not Local Authority,
since authorities within the same TTWA share a labour market and are unlikely
to be independent.

## Pipeline

Run in this order:

1. `01_clean_raw_datasets.R` - cleans the raw Stat-Xplore and NOMIS exports into tidy CSVs
2. `02_build_panel_data.sql` - joins geography, claimant, pay, and employment data into one panel
3. `03_build_analysis_variables.R` - builds the DiD design variables once, in one place
4. `04_descriptive_analysis.R`-  summary statistics, trend chart, formal pre-trends test
5. `05_did_regression.R`-  DiD and event-study models, results saved to `outputs/`

**Note:** running script 02 is not necessary to reproduce the results below; its
output, `master_labour_panel.csv`, is already included in `data-processed/`.
The script documents how the panel was actually built (joined in PostgreSQL via
DBeaver) and can be run independently if you want to verify the join yourself.
Scripts 01, 03, 04, and 05 run directly on the files already provided in this
repo, in that order.

## What I caught

Three issues surfaced during development that would have produced a
misleading result if left unfixed:

- **A silent join failure** was dropping four local authorities entirely,
  with no error, caused by a 2023 local government boundary reorganisation
  that predated the geography lookup file. This was fixed with an explicit crosswalk.
- **The treatment classification was initially allowed to vary over time**,
  meaning an area's treated/control status could technically change between
  2021 and 2022. This goes against the core logic of a difference-in-differences
  design. It was fixed by freezing the classification to pre-reform data only.
- **A duplicate-row bug in the geography join** (local authorities can span
  more than one Travel-to-Work Area, and an early version of the join kept
  every match rather than one per area) This was silently inflating the sample
  and artificially shrinking standard errors, turning a genuinely
  non-significant result into a false "significant" one. This was caught by checking
  row counts against expected totals, not by the code failing to run.

## Limitations

- Scoped to England & Wales only. The geography lookup used has no Scotland coverage, and Scotland's separate income tax bands would need distinct treatment regardless.
- Isles of Scilly is excluded across all three data sources due to small-sample statistical disclosure control.
- LFS/ASHE-based classification carries the usual survey noise at small area level, discussed in-line with each result rather than smoothed over.

## Tools

R 4.5.2 · PostgreSQL · DBeaver
