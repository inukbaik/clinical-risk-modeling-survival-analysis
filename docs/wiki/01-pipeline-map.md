# Pipeline Map

See also: [[00-index]], [[03-modeling-workflow]]

## Directory roles

- `R/` — reusable functions, no file I/O, no hard-coded paths. Each file is
  a pure module imported by one or more scripts.
- `scripts/` — pipeline drivers. Each script does file I/O, calls into
  `R/`, validates inputs, and writes outputs. Each script is runnable
  independently from the repo root (given its required input files exist).
- `data/synthetic/` — generated and cleaned synthetic data (git-ignored
  `.rds` files; the raw `.csv` is tracked).
- `outputs/tables/`, `outputs/figures/`, `outputs/models/` — pipeline
  outputs (models `.rds` are git-ignored; tables/figures are tracked).
- `reports/` — currently empty; reserved for a future RMarkdown summary
  report (see README "Planned Next Steps").

## R/ modules

| File | Purpose |
|---|---|
| `R/config.R` | Central source of truth: paths, column-role lists (`ID_VAR`, `GROUP_VAR`, `DEMOGRAPHIC_VARS`, `CLINICAL_VARS`, `BASELINE_PREDICTORS`), `OUTCOME_SPECS`, `COX_MODEL_SPECS`, `PSM_FORMULA_VARS`, `LEAKAGE_VARS`, `SEED` |
| `R/data_cleaning.R` | `clean_clinical_data()`, `create_age_subcohort()` |
| `R/descriptive_tables.R` | `create_tableone_summary()`, `create_outcome_followup_summary()` |
| `R/propensity_matching.R` | `run_propensity_matching()`, `extract_psm_balance()`, `build_attempt_log_df()` |
| `R/cox_modeling.R` | `fit_cox_model()`, `extract_cox_results()` |
| `R/random_forest.R` | `build_rf_predictor_set()`, `prepare_rf_outcome()`, `split_rf_data()`, `create_tuning_subset()`, `fit_rf_model()`, `evaluate_rf_model()`, `extract_rf_importance()`, `plot_rf_importance()` |
| `R/validation.R` | Fail-fast pre-modeling checks shared by Cox, PSM, and RF steps |

## scripts/ execution order

```
01_generate_synthetic_data.R   → data/synthetic/synthetic_cohort.csv
02_clean_data.R                → data/synthetic/synthetic_cohort_clean.rds
03_descriptive_tables.R        → outputs/tables/table1_baseline_characteristics.csv
                                  outputs/tables/outcome_followup_summary.csv
04_propensity_matching.R       → data/synthetic/matched_clinical_data.rds
                                  outputs/models/matchit_object.rds
                                  outputs/tables/psm_balance_summary.csv
                                  outputs/tables/psm_matching_summary.csv
05_cox_models.R                → outputs/tables/cox_results.csv
                                  outputs/models/cox_models.rds
06_random_forest.R             → outputs/tables/rf_*.csv
                                  outputs/figures/rf_*.png
                                  outputs/models/rf_models.rds
```

Each script downstream of `02_clean_data.R` fails fast with a clear message
if its required input file is missing (e.g. `05_cox_models.R` requires
`matched_clinical_data.rds` from `04_propensity_matching.R`).

Note: Cox modeling (`05`) runs on the **matched** cohort; random forest
(`06`) runs on the **unmatched cleaned** cohort, since RF's goal is
baseline predictor importance, not treatment-effect estimation.
