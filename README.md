# Clinical Modeling Pipeline Demo

A reproducible R pipeline demonstrating cohort-based survival analysis methods, including descriptive Table 1 summaries, Cox proportional hazards modeling, propensity score matching, and random forest feature importance. The project is modeled on observational clinical research workflows and uses fully synthetic data.

This repository is intended as a public-safe portfolio example. It contains no real patient data, protected health information, institutional data, unpublished results, or study-specific variable names.

## Project Structure

```
clinical-risk-modeling-survival-analysis/
├── R/
│   ├── config.R                  # Central variable names, paths, model specs
│   ├── data_cleaning.R           # clean_clinical_data(), create_age_subcohort()
│   ├── descriptive_tables.R      # create_tableone_summary(), create_outcome_followup_summary()
│   └── validation.R              # Reusable modeling validation helpers
├── scripts/
│   ├── 01_generate_synthetic_data.R
│   ├── 02_clean_data.R
│   └── 03_descriptive_tables.R
├── data/
│   └── synthetic/
│       ├── synthetic_cohort.csv          # Raw generated cohort
│       └── synthetic_cohort_clean.rds    # Typed and factor-encoded
├── outputs/
│   ├── tables/
│   │   ├── table1_baseline_characteristics.csv
│   │   └── outcome_followup_summary.csv
│   └── figures/
├── reports/
└── README.md
```

## Running the Pipeline

Each script is independently runnable from the repository root. Run them in order:

```r
Rscript scripts/01_generate_synthetic_data.R
Rscript scripts/02_clean_data.R
Rscript scripts/03_descriptive_tables.R
```

Scripts 02 and 03 will stop with a clear error if their required input files are missing.

## Synthetic Data

`scripts/01_generate_synthetic_data.R`

Generates a fully synthetic cohort with realistic covariate structure, confounded exposure assignment, and two time-to-event outcomes. Saves to:

```
data/synthetic/synthetic_cohort.csv
```

The dataset uses generalized variable names to preserve the structure of an observational clinical modeling workflow while avoiding study-specific details.

| Variable group | Columns | Description |
|---|---|---|
| Record identifier | `record_id` | Synthetic row-level ID |
| Demographics | `demo_age`, `demo_sex`, `demo_race` | Synthetic demographic predictors |
| Baseline clinical | `clinical_binary_1`–`clinical_binary_6`, `clinical_continuous_1` | Masked binary and continuous baseline predictors |
| Exposure | `exposure_group` | Binary treatment/exposure group (`Exposure_A` / `Exposure_B`) |
| Outcomes | `outcome_1`, `outcome_2` | Binary event indicators |
| Follow-up time | `followup_time_1`, `followup_time_2` | Outcome-specific follow-up times (years) |
| Post-baseline | `post_baseline_indicator` | Excluded from predictive models to prevent data leakage |

## Data Cleaning

`scripts/02_clean_data.R`

Reads the raw CSV, applies `clean_clinical_data()` from `R/data_cleaning.R`, and saves the result as a typed RDS file:

```
data/synthetic/synthetic_cohort_clean.rds
```

Cleaning steps:

- Validates that all required columns are present; stops with a clear error if any are missing
- Removes records with missing or non-positive follow-up time
- Casts continuous variables to numeric; event indicators to integer
- Encodes `exposure_group` as a factor with `Exposure_A` as the reference level
- Encodes binary clinical predictors and demographic variables as factors

Downstream scripts load `synthetic_cohort_clean.rds` via `readRDS()` to preserve column types and factor levels exactly.

## Validation Helpers

`R/validation.R` provides reusable pre-modeling checks used across the Cox, PSM, and random forest steps:

- `validate_binary_outcome()` — confirms event indicator is 0/1 integer with no NAs
- `validate_min_events()` — confirms sufficient event count for modeling
- `validate_survival_time()` — confirms follow-up time is numeric, positive, and complete
- `validate_two_group_exposure()` — confirms exactly two exposure groups are present
- `validate_predictor_columns()` — confirms all required columns exist in the data
- `validate_no_leakage_predictors()` — confirms no leakage variables appear in the predictor list
- `validate_factor_levels()` — confirms all factor predictors have at least two observed levels

## Descriptive Tables

`scripts/03_descriptive_tables.R`

Generates baseline characteristic tables and outcome/follow-up summaries for:

- **Overall cohort** — all cleaned records
- **Age 65+ cohort** — restricted to `demo_age >= 65` via `create_age_subcohort()`

**Table 1 — Baseline Characteristics**

Generated via `create_tableone_summary()`, which wraps `tableone::CreateTableOne()`. Variables are summarised by exposure group, with continuous variables reported as mean (SD) and categorical variables as n (%). Requires the `tableone` package. `post_baseline_indicator` is excluded.

```
outputs/tables/table1_baseline_characteristics.csv
```

**Outcome and Follow-Up Summary**

Generated via `create_outcome_followup_summary()` using base R. Reports event counts, event percentages, and follow-up time distribution by exposure group for each outcome.

```
outputs/tables/outcome_followup_summary.csv
```

Both functions accept any cohort data frame and a `cohort_label` argument, making them reusable for matched cohorts in later steps.

## Planned Workflow

1. Generate synthetic cohort data — `scripts/01_generate_synthetic_data.R`
2. Clean and validate the dataset — `scripts/02_clean_data.R`
3. Create descriptive Table 1 summaries — `scripts/03_descriptive_tables.R`
4. Apply propensity score matching and check covariate balance
5. Fit Cox proportional hazards models
6. Train random forest models for feature importance
7. Summarize the workflow in a final reproducible report

## Design Notes

`R/config.R` is the central source of truth for all variable names, outcome specifications, file paths, and the leakage variable exclusion list (`LEAKAGE_VARS`). Downstream modules reference config objects rather than hard-coding column names, which makes the pipeline easy to adapt and audit.

Each script is designed to fail fast with a descriptive error if required input files or columns are missing, so pipeline errors surface early rather than propagating silently.

## Privacy Note

All data in this repository are fully synthetic. No real patients, real clinical measurements, or study-specific details are represented. Variable names are intentionally generalized.
