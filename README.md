# Clinical Modeling Pipeline Demo

This repository demonstrates a reusable clinical modeling pipeline using fully synthetic data and generalized variable names.

The project is designed as a public-safe portfolio example. It does not include real patient data, protected health information, institutional data, unpublished results, or study-specific variable names.

## Current Implementation

The current version includes:

-   Synthetic cohort data generation
-   Centralized variable configuration in `R/config.R`
-   Basic data cleaning and validation in `R/data_cleaning.R`
-   Removal of invalid follow-up times before survival modeling
-   Generalized variable names for public-safe demonstration

Future steps will add descriptive tables, Cox proportional hazards models, propensity score matching, random forest feature importance, and a final report.

## Project Structure

-   `README.md`
-   `.gitignore`
-   `R/`
    -   `config.R`
    -   `data_cleaning.R`
-   `scripts/`
    -   `01_generate_synthetic_data.R`
-   `data/`
    -   `synthetic/`
-   `outputs/`
    -   `tables/`
    -   `figures/`
-   `reports/`

## Synthetic Data

Generate the synthetic cohort with:

`Rscript scripts/01_generate_synthetic_data.R`

This creates:

`data/synthetic/synthetic_cohort.csv`

The dataset uses generalized variable names to preserve the structure of an observational clinical modeling workflow while avoiding study-specific details.

| Variable group | Example columns | Description |
|----|----|----|
| Record identifier | `record_id` | Synthetic row-level ID |
| Demographics | `demo_age`, `demo_sex`, `demo_race` | Synthetic demographic predictors |
| Baseline clinical predictors | `clinical_binary_1` to `clinical_binary_6`, `clinical_continuous_1` | Masked baseline clinical variables |
| Exposure | `exposure_group` | Synthetic binary exposure group |
| Outcomes | `outcome_1`, `outcome_2` | Synthetic event indicators |
| Follow-up time | `followup_time_1`, `followup_time_2` | Outcome-specific follow-up times |
| Post-baseline indicator | `post_baseline_indicator` | Excluded from future ML models to avoid leakage |

## Design Notes

The project uses `R/config.R` as the central source of truth for variable names, outcome specifications, and leakage-prone variables. This avoids repeated hard-coded column names and supports a modular pipeline design.

The cleaning step validates required columns and excludes records with missing or non-positive follow-up time, since invalid follow-up time should not enter survival models.

## Planned Workflow

1.  Generate synthetic cohort data
2.  Clean and validate the dataset
3.  Create descriptive Table 1 summaries
4.  Fit Cox proportional hazards models
5.  Apply propensity score matching and check covariate balance
6.  Train random forest models for feature importance
7.  Export selected tables and figures
8.  Summarize the workflow in a final report

## Privacy Note

This repository is intended for public demonstration only. All data are synthetic, and variable names are generalized to avoid exposing study-specific information.
