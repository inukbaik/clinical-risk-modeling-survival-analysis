# Clinical Modeling Pipeline Demo

A reproducible R pipeline demonstrating cohort-based survival analysis methods, including descriptive Table 1 summaries, Cox proportional hazards modeling, propensity score matching, and random forest feature importance. The project is modeled on observational clinical research workflows and uses fully synthetic data.

This repository is intended as a public-safe portfolio example. It contains no real patient data, protected health information, institutional data, unpublished results, or study-specific variable names.

## Project Structure

```         
clinical-risk-modeling-survival-analysis/
├── R/
│   ├── config.R                  # Central variable names, paths, model specs
│   ├── cox_modeling.R            # fit_cox_model(), extract_cox_results()
│   ├── data_cleaning.R           # clean_clinical_data(), create_age_subcohort()
│   ├── descriptive_tables.R      # create_tableone_summary(), create_outcome_followup_summary()
│   ├── propensity_matching.R     # run_propensity_matching(), extract_psm_balance(), build_attempt_log_df()
│   ├── random_forest.R           # build_rf_predictor_set(), fit_rf_model(), evaluate_rf_model(), extract_rf_importance(), plot_rf_importance()
│   └── validation.R              # Reusable modeling validation helpers
├── scripts/
│   ├── 01_generate_synthetic_data.R
│   ├── 02_clean_data.R
│   ├── 03_descriptive_tables.R
│   ├── 04_propensity_matching.R
│   ├── 05_cox_models.R
│   └── 06_random_forest.R
├── data/
│   └── synthetic/
│       ├── synthetic_cohort.csv          # Raw generated cohort
│       ├── synthetic_cohort_clean.rds    # Typed and factor-encoded
│       └── matched_clinical_data.rds     # Propensity-score-matched cohort
├── outputs/
│   ├── tables/
│   │   ├── table1_baseline_characteristics.csv
│   │   ├── outcome_followup_summary.csv
│   │   ├── psm_balance_summary.csv
│   │   ├── psm_matching_summary.csv
│   │   ├── cox_results.csv
│   │   ├── rf_auc_summary.csv
│   │   ├── rf_importance_overall_outcome_1.csv
│   │   ├── rf_importance_overall_outcome_2.csv
│   │   ├── rf_importance_age65_outcome_1.csv
│   │   └── rf_importance_age65_outcome_2.csv
│   ├── models/
│   │   ├── matchit_object.rds
│   │   ├── cox_models.rds
│   │   └── rf_models.rds
│   └── figures/
│       ├── rf_importance_overall_outcome_1.png
│       ├── rf_importance_overall_outcome_2.png
│       ├── rf_importance_age65_outcome_1.png
│       └── rf_importance_age65_outcome_2.png
├── reports/
└── README.md
```

## Running the Pipeline

Each script is independently runnable from the repository root. Run them in order:

``` r
Rscript scripts/01_generate_synthetic_data.R
Rscript scripts/02_clean_data.R
Rscript scripts/03_descriptive_tables.R
Rscript scripts/04_propensity_matching.R
Rscript scripts/05_cox_models.R
Rscript scripts/06_random_forest.R
```

Each script stops with a clear error if its required input files are missing.

## Synthetic Data

`scripts/01_generate_synthetic_data.R`

Generates a fully synthetic cohort with realistic covariate structure, confounded exposure assignment, and two time-to-event outcomes. Saves to:

```         
data/synthetic/synthetic_cohort.csv
```

The dataset uses generalized variable names to preserve the structure of an observational clinical modeling workflow while avoiding study-specific details.

| Variable group | Columns | Description |
|----|----|----|
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

## Propensity Score Matching

`scripts/04_propensity_matching.R`

Applies 1:1 nearest-neighbor propensity score matching using `MatchIt::matchit()`. The propensity model uses all baseline covariates (demographics and clinical predictors); outcome variables, follow-up time variables, and `post_baseline_indicator` are excluded.

A caliper search runs from 0.20 to 0.01 (in propensity score SD units, step −0.01). The first (largest) caliper where every baseline covariate has absolute standardized mean difference (SMD) \< 0.10 is selected. If no caliper passes, the script stops with the best attempted caliper, lowest max SMD, and the names of remaining imbalanced variables.

**Outputs:**

```         
data/synthetic/matched_clinical_data.rds      # Matched cohort for downstream modeling
outputs/models/matchit_object.rds             # Fitted matchit object
outputs/tables/psm_balance_summary.csv        # Per-variable SMD before and after matching
outputs/tables/psm_matching_summary.csv       # Per-caliper attempt log
```

## Cox Survival Modeling

`scripts/05_cox_models.R`

Fits Cox proportional hazards models for both outcomes across the matched cohort and an age 65+ matched subcohort. Four adjustment models are fit per outcome per cohort. Requires `matched_clinical_data.rds`; fails fast with a message to run `scripts/04_propensity_matching.R` if the file is missing.

- **Model 1** — exposure group only (unadjusted)
- **Model 2** — exposure group + demographics (`demo_age`, `demo_sex`, `demo_race`)
- **Model 3** — Model 2 + all binary clinical predictors (`clinical_binary_1` through `clinical_binary_6`)
- **Model 4** — Model 3 + continuous clinical predictor (`clinical_continuous_1`)

Each outcome is modeled using its matched follow-up time (`outcome_1` / `followup_time_1`, `outcome_2` / `followup_time_2`).

**Fail-fast validation** runs before each model fit:

- Exposure variable has exactly two groups
- Outcome variable is binary (0/1 integer, no NAs)
- Minimum event count met (≥ 10 events)
- Follow-up time is numeric, positive, and complete
- All predictor columns exist in the data
- Factor predictors have at least two observed levels
- No leakage variables (outcomes, follow-up times, `post_baseline_indicator`, record ID) appear in the predictor list

Models that fail validation are skipped with a descriptive console message identifying the cohort, outcome, and model; the remaining models continue. Modeling functions are implemented in `R/cox_modeling.R`, which contains no file I/O or hard-coded paths.

**Outputs:**

```         
outputs/tables/cox_results.csv    # Per-term hazard ratios, 95% CIs, p-values
outputs/models/cox_models.rds     # Named list of fitted coxph objects
```

The matched data retains all original columns, so the same four-model covariate structure and all fail-fast validation checks apply unchanged.

## Random Forest Feature Importance

`scripts/06_random_forest.R`

Trains random forest classifiers to identify baseline predictors of each outcome using the unmatched cleaned cohort. This step is separate from the Cox models: the goal is to characterize which baseline variables are most informative, not to estimate a treatment effect.

**Modeling approach:**

- Predictor set is drawn from `R/config.R`; all leakage variables (follow-up times, outcome indicators, post-baseline indicators, record ID) are excluded before any data is touched
- The cohort is split into 80% training and 20% held-out test using a stratified split to preserve the event rate in each partition
- SMOTE oversampling is applied to the training data only, after the split, to address class imbalance
- Hyperparameter tuning uses 5-fold cross-validation with ROC-AUC as the metric, run via `caret` on a stratified tuning subset to keep runtime manageable
- The final model is fit with `ranger` (500 trees, permutation importance) on the full SMOTE'd training data using the best parameters from the tuning phase
- Feature importance is extracted as permutation importance from the final `ranger` model

Models are fit for both outcomes across two cohorts:

- **Overall cleaned cohort** — all records from `synthetic_cohort_clean.rds`
- **Age 65+ cohort** — restricted to `demo_age >= 65` via `create_age_subcohort()`

The same fail-fast validation checks used in the Cox step apply here: binary outcome format, minimum event count, predictor column presence, leakage exclusion, and factor level checks. A run that fails validation is skipped with a descriptive message; remaining runs continue.

**Outputs:**

```         
outputs/tables/rf_auc_summary.csv                    # Test-set AUC per cohort and outcome
outputs/tables/rf_importance_overall_outcome_1.csv   # Permutation importance, overall cohort, outcome 1
outputs/tables/rf_importance_overall_outcome_2.csv   # Permutation importance, overall cohort, outcome 2
outputs/tables/rf_importance_age65_outcome_1.csv     # Permutation importance, age 65+ cohort, outcome 1
outputs/tables/rf_importance_age65_outcome_2.csv     # Permutation importance, age 65+ cohort, outcome 2
outputs/figures/rf_importance_overall_outcome_1.png  # Top-15 importance bar chart, overall cohort, outcome 1
outputs/figures/rf_importance_overall_outcome_2.png  # Top-15 importance bar chart, overall cohort, outcome 2
outputs/figures/rf_importance_age65_outcome_1.png    # Top-15 importance bar chart, age 65+ cohort, outcome 1
outputs/figures/rf_importance_age65_outcome_2.png    # Top-15 importance bar chart, age 65+ cohort, outcome 2
outputs/models/rf_models.rds                         # Named list of fitted ranger objects
```

## Planned Next Steps

1.  Reproducible report — `reports/` RMarkdown summary integrating all pipeline outputs
2.  Final project polish and documentation review

## Design Notes

`R/config.R` is the central source of truth for all variable names, outcome specifications, file paths, and the leakage variable exclusion list (`LEAKAGE_VARS`). Downstream modules reference config objects rather than hard-coding column names, which makes the pipeline easy to adapt and audit.

Each script is designed to fail fast with a descriptive error if required input files or columns are missing, so pipeline errors surface early rather than propagating silently.

## Project Wiki

Additional pipeline detail, output inventory, and maintenance notes are
kept in `docs/wiki/`, a manually maintained project wiki. Start at
`docs/wiki/00-index.md`.

## Privacy Note

All data in this repository are fully synthetic. No real patients, real clinical measurements, or study-specific details are represented. Variable names are intentionally generalized.
