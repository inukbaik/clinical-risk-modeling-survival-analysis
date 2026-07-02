# Output Inventory

See also: [[03-modeling-workflow]], [[05-reproducibility]]

## Tracking status

- `outputs/tables/*.csv` and `outputs/figures/*.png` are **tracked** in git.
- `outputs/models/*.rds` and `data/synthetic/*.rds` are **git-ignored**
  (see `.gitignore`: `data/synthetic/*.rds`, `outputs/models/*.rds`).
  They must be regenerated locally by running the pipeline.

## outputs/tables/

| File | Produced by | Contents |
|---|---|---|
| `table1_baseline_characteristics.csv` | `03_descriptive_tables.R` | Baseline characteristics by exposure group, overall + age 65+ |
| `outcome_followup_summary.csv` | `03_descriptive_tables.R` | Event counts/%, follow-up time distribution by exposure group |
| `psm_balance_summary.csv` | `04_propensity_matching.R` | Per-variable SMD before/after matching |
| `psm_matching_summary.csv` | `04_propensity_matching.R` | Per-caliper attempt log from the caliper search |
| `cox_results.csv` | `05_cox_models.R` | Per-term hazard ratios, 95% CIs, p-values across all model/outcome/cohort combinations |
| `rf_auc_summary.csv` | `06_random_forest.R` | Test-set AUC per cohort and outcome |
| `rf_importance_overall_outcome_1.csv` | `06_random_forest.R` | Permutation importance, overall cohort, outcome 1 |
| `rf_importance_overall_outcome_2.csv` | `06_random_forest.R` | Permutation importance, overall cohort, outcome 2 |
| `rf_importance_age65_outcome_1.csv` | `06_random_forest.R` | Permutation importance, age 65+ cohort, outcome 1 |
| `rf_importance_age65_outcome_2.csv` | `06_random_forest.R` | Permutation importance, age 65+ cohort, outcome 2 |

## outputs/figures/

| File | Produced by | Contents |
|---|---|---|
| `rf_importance_overall_outcome_1.png` | `06_random_forest.R` | Top-15 importance bar chart, overall cohort, outcome 1 |
| `rf_importance_overall_outcome_2.png` | `06_random_forest.R` | Top-15 importance bar chart, overall cohort, outcome 2 |
| `rf_importance_age65_outcome_1.png` | `06_random_forest.R` | Top-15 importance bar chart, age 65+ cohort, outcome 1 |
| `rf_importance_age65_outcome_2.png` | `06_random_forest.R` | Top-15 importance bar chart, age 65+ cohort, outcome 2 |

## outputs/models/ (git-ignored)

| File | Produced by | Contents |
|---|---|---|
| `matchit_object.rds` | `04_propensity_matching.R` | Fitted `matchit` object |
| `cox_models.rds` | `05_cox_models.R` | Named list of fitted `coxph` objects |
| `rf_models.rds` | `06_random_forest.R` | Named list of fitted `ranger` objects |

## data/synthetic/

| File | Tracked? | Produced by |
|---|---|---|
| `synthetic_cohort.csv` | Yes | `01_generate_synthetic_data.R` |
| `synthetic_cohort_clean.rds` | No (git-ignored) | `02_clean_data.R` |
| `matched_clinical_data.rds` | No (git-ignored) | `04_propensity_matching.R` |

## Regenerating everything

See [[05-reproducibility]] for the full run order. Because `.rds` files are
git-ignored, a fresh clone must run scripts `01`–`06` in order before any
downstream script will find its inputs.
