# Modeling Workflow

See also: [[01-pipeline-map]], [[04-output-inventory]]

## Cohorts used throughout

- **Overall** — all records in the relevant data file
- **Age 65+** — `create_age_subcohort(data, age_cutoff = 65)` from
  `R/data_cleaning.R`

## 1. Descriptive tables — `scripts/03_descriptive_tables.R`

- `create_tableone_summary()` wraps `tableone::CreateTableOne()`; reports
  baseline characteristics by `exposure_group` (continuous as mean (SD),
  categorical as n (%)). `post_baseline_indicator` excluded.
- `create_outcome_followup_summary()` (base R) reports event counts,
  event %, and follow-up time distribution by exposure group, per outcome.
- Both functions take any cohort data frame plus a `cohort_label`, so the
  same code runs for overall and age 65+ cohorts, and later for matched
  cohorts.

## 2. Propensity score matching — `scripts/04_propensity_matching.R`

- `run_propensity_matching()` (`R/propensity_matching.R`) runs 1:1
  nearest-neighbor matching via `MatchIt::matchit()` on
  `PSM_FORMULA_VARS` (demographics + clinical predictors from
  `R/config.R`). Outcomes, follow-up times, and `post_baseline_indicator`
  are excluded from the propensity model.
- Caliper search: 0.20 → 0.01 in propensity-score SD units, step −0.01.
  Selects the first (largest) caliper where every covariate's absolute SMD
  < 0.10. If none pass, the script stops and reports the best attempted
  caliper, lowest max SMD, and which variables remain imbalanced.
- Runs on the **unmatched cleaned** cohort as input; output is the matched
  cohort used by the Cox step.

## 3. Cox proportional hazards — `scripts/05_cox_models.R`

- Runs on `data/synthetic/matched_clinical_data.rds`; fails fast with a
  message to run `04_propensity_matching.R` first if that file is missing.
- `fit_cox_model()` / `extract_cox_results()` (`R/cox_modeling.R`) — no
  file I/O, no hard-coded paths.
- 4 covariate models × 2 outcomes × 2 cohorts (overall, age 65+):
  1. Exposure only (unadjusted)
  2. + demographics
  3. + all binary clinical predictors
  4. + continuous clinical predictor
- Each outcome uses its matched event/time pair from `OUTCOME_SPECS` in
  `R/config.R` (`outcome_1`/`followup_time_1`, `outcome_2`/`followup_time_2`).
- Pre-fit validation (`R/validation.R`) checks: two-group exposure, binary
  outcome format, minimum event count, valid follow-up time, predictor
  columns present, factor levels present, no leakage variables in the
  predictor list. Models that fail validation are skipped with a
  descriptive message; other model/cohort/outcome combinations still run.

## 4. Random forest feature importance — `scripts/06_random_forest.R`

- Runs on the **unmatched cleaned** cohort
  (`synthetic_cohort_clean.rds`), not the matched data — the goal here is
  baseline predictor importance, not treatment-effect estimation.
- Predictor set built by `build_rf_predictor_set()` from `R/config.R`
  columns, with `LEAKAGE_VARS` (follow-up times, outcomes,
  `post_baseline_indicator`, `record_id`) excluded before any data is
  touched. See the leakage rule in [[06-agent-rules]].
- Stratified 80/20 train/test split preserving event rate
  (`split_rf_data()`).
- SMOTE oversampling (`over_ratio = 0.5`) applied to training data only.
- Two-phase fitting: `caret` 5-fold CV on a stratified tuning subset
  selects hyperparameters (mtry, min.node.size), then a final `ranger`
  model (500 trees, permutation importance) is fit on the full SMOTE'd
  training set using the selected parameters.
- Same fail-fast validation checks as the Cox step apply; failed
  combinations are skipped with a message, others continue.
- Runs across 2 outcomes × 2 cohorts (overall, age 65+).

## What this pipeline does not claim

Random forest importance describes association/predictiveness of baseline
variables, not causal effects. Cox models here are demonstration models on
synthetic, confounded-by-design data — no clinical or causal conclusions
should be drawn from any output in this repository.
