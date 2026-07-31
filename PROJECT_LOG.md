# PROJECT_LOG.md

## 2026-07-30 — Rebuild as a problem-driven Quarto project

**Task:** Replace the script-based pipeline with six Quarto notebooks organised around
three problems from the source analysis, and fix the data-generating process so estimates
can be checked against known truth. Entries below this one describe the previous
script pipeline and are retained as history; they no longer describe the codebase.

**Motivation:** The previous pipeline produced null results by construction.
`scripts/01_generate_synthetic_data.R` drew follow-up time first from a marginal
exponential, then drew the event indicator from a logistic model that used that time as a
predictor. No hazard ratio existed in the data-generating process, so the Cox step was
estimating a parameter that was not there — the shipped headline was HR 0.943
(0.873–1.018), p = 0.133, two of four random forest models had test AUC near 0.50, and
`demo_race`, whose true effect was exactly zero, ranked second in permutation importance.
Separately, `R/validation.R` (133 lines) had no reachable failure path at any call site,
and the schema was declared in three unlinked places.

**Files removed:** `scripts/01`–`06`; `R/validation.R`, `R/data_cleaning.R`,
`R/descriptive_tables.R`, `R/propensity_matching.R`, `R/cox_modeling.R`,
`R/random_forest.R`; `docs/wiki/` (stale on two counts, superseded by the rendered site);
the tracked 9.9 MB `data/synthetic/synthetic_cohort.csv`; all of `outputs/`; the empty
`reports/`; stale `.RData` / `.RDataTmp`.

**Files created:**
- `R/config.R` — rewritten as the single schema definition plus true parameter values
  (`TRUE_A_OUTCOME_1`, `TRUE_A_OUTCOME_2`, `TRUE_B_EVENT`, `TRUE_B_DEATH`, `TRUE_PS_COEFS`,
  `TRUE_PS_COEFS_B`) and analysis constants
- `R/simulate.R` — Weibull proportional hazards generator for Study A; competing-risks
  generator for Study B with a shared gamma frailty, real date columns, and
  month-precision death dates
- `R/clean.R` — `clean_study_a()` with an attrition attribute, `age_subgroup()`
- `R/balance.R` — SMD helpers, `search_caliper()`, `create_weights()`,
  `effective_sample_size()`, `weight_diagnostics()`
- `R/inference.R` — `model_result_row()` (variance source as an explicit argument),
  `ph_interval_test()`, `robust_wald_test()`, `ph_status_label()`
- `R/setup.R`, `_quarto.yml`, `index.qmd`, `notebooks/00`–`05`

**Validation results:**
- Full cold render: 6/6 notebooks, ~2 minutes
- Study A adjusted Cox recovers HR 0.717 against a true 0.75 (outcome 1); the unadjusted
  unmatched estimate is 0.988, i.e. confounding hides the effect entirely
- Naive matching without a caliper raised the largest |SMD| from 0.248 to 0.381 while
  retaining 95.7% of subjects — asserted in the notebook, since the narrative depends on it
- Caliper search: 8 attempts, 7 failures, selected 0.16 at max |SMD| 0.086, 90.8% retained
- Overlap weighting balances to |SMD| = 0 exactly; IPTW effective sample size 13,964 of
  20,000 versus 15,417 for overlap weights, with 61 inverse-probability weights above 10
- Fine-Gray sHR 0.810 (0.707–0.927) and cause-specific HR 0.815 (0.712–0.933) against a
  true cause-specific HR of 0.80; all six sensitivity analyses fall in 0.79–0.82
- Random forest test AUC 0.633 (unmatched) and 0.649 (matched), replacing the previous
  near-chance values

**Deviations from the plan, and why:**
- The plan specified a scale-invariance demonstration (refit with weights × 4) to justify
  the robust variance. Dropped at the user's direction — the robust-versus-model-based
  choice is now explained in prose in notebook 05 §3, with no demonstration code, and no
  p-value backtracking narrative appears anywhere.
- Study A outcome 2's confidence interval does not cover its true hazard ratio in this
  realization (2.6 SE away, ~1,900 events). Reported and explained in the notebook rather
  than resolved by reseeding. Per-estimate CI coverage is deliberately not asserted; the
  assertion checks that matching moves the estimate closer to truth than doing nothing.
- Exact same-day event/death ties number zero in this cohort, so the tie rule moves no
  subjects. Reported honestly. The material finding is that month-precision rounding
  inverts the true event ordering for a small number of subjects under *both* rules, which
  no tie rule can fix.

**Assumptions and remaining risks:**
- `TRUE_PS_COEFS[["clinical_continuous_1"]]` was set to −0.003 so that the covariate
  excluded from the propensity model is imbalanced at loose calipers and balanced at tight
  ones. A stronger value makes it unbalanceable at any caliper — realistic, but it would
  mean the design fails rather than needing tuning. Documented at the definition.
- Study B uses its own, stronger exposure model (`TRUE_PS_COEFS_B`) so that propensity
  scores spread toward both extremes and the weighting diagnostics have something to find.
- Random forest tuning uses `importance = "none"` and refits once with permutation
  importance, cutting notebook 03 from 2m31s to ~55s. `RF_NUM_TREES = 250`; no conclusion
  depends on the exact value.
- The estimated competing-death hazard ratio (1.14) differs from its true value (0.98)
  because treatment reduces the event and therefore lengthens time at risk for death, in a
  frailty-selected subset. Explained in notebook 05 rather than treated as a defect.

## 2026-07-02 — Amendment: RF subcohort naming superseded

**Note:** The 2026-06-27 entry below ("Random forest feature importance workflow") describes a `clinical_binary_1 == 1` subcohort producing `rf_importance_subcohort_*` outputs. This is historical and no longer reflects the codebase. The RF subgroup workflow was changed to an age 65+ subcohort via `create_age_subcohort(age_cutoff = 65)` (slug `age65`) in `scripts/06_random_forest.R`, and current outputs are `rf_importance_age65_outcome_1/2.csv` and `rf_importance_age65_outcome_1/2.png`. No `rf_importance_subcohort_*` files exist. Documentation-only correction; no code or output changes.

## 2026-07-02 — Fix RF parallel backend fallback for unreliable core detection

**Task:** An independent audit found that `scripts/06_random_forest.R` crashed with `missing value where TRUE/FALSE needed` in sandboxed/CI environments where `parallel::detectCores()` returns `NA`. Made core detection robust with a safe single-threaded fallback so the RF step (and pipeline) always completes; parallelism is a speed optimization only and must never gate correctness.

**Files edited:**
- `scripts/06_random_forest.R` — replaced `max(1L, parallel::detectCores() - 1L)` with validated core detection (`parallel::detectCores(logical = TRUE)`, checked for numeric/finite/`>= 2`); only registers `doParallel` when available and usable cores `> 1`; prints `Unable to detect usable CPU cores; running random forest step single-threaded.` on fallback instead of `Parallel backend registered: NA cores`; wrapped the model-fitting loop in `tryCatch(..., finally = ...)` so `doParallel::stopImplicitCluster()` always runs, since top-level `on.exit()` never fires in an `Rscript` (verified empirically — no enclosing function frame to exit)
- `docs/wiki/05-reproducibility.md` — expanded the `doParallel` dependency note to describe the single-threaded fallback conditions (package missing, unusable core count, `< 2` cores), not just the missing-package case

**Outputs produced:**
- Regenerated `outputs/tables/rf_auc_summary.csv`, `outputs/tables/rf_importance_*.csv`, `outputs/figures/rf_importance_*.png`, `outputs/models/rf_models.rds` — byte-identical to the pre-fix versions (seeded RNG unaffected by the parallel-backend change)

**Validation results:**
- Normal environment (8 physical/logical cores detected): prints `Parallel backend registered: 7 cores`; full pipeline (`01`–`06`) ran end to end; 4 RF models fit, 0 skipped; AUCs unchanged (0.5430, 0.6399, 0.5023, 0.6101)
- Simulated audit failure (`parallel::detectCores()` monkey-patched to return `NA_integer_`, matching the reported CI behavior): prints `Unable to detect usable CPU cores; running random forest step single-threaded.`; RF step completed with identical AUCs and identical output files — confirms the crash is fixed and results are reproducible regardless of parallel backend availability

**Assumptions:**
- No explicit `parallel::makeCluster()` is used in this script — `doParallel::registerDoParallel(cores = n)` handles its own (fork-based on Unix, implicit cluster on Windows) backend internally, so cleanup uses `doParallel::stopImplicitCluster()` rather than `parallel::stopCluster()` on a captured cluster handle
- RF modeling logic, outcome/predictor definitions, seeds, and output filenames were not changed

## 2026-06-27 — Random forest feature importance workflow

**Task:** Add random forest feature importance as a reusable pipeline step using the unmatched cleaned cohort. Optimized runtime via a two-phase fitting strategy: caret CV on a stratified tuning subset for hyperparameter selection, followed by a final ranger model on the full training data.

**Files created:**
- `R/random_forest.R` — reusable functions: `build_rf_predictor_set`, `prepare_rf_outcome`, `split_rf_data`, `create_tuning_subset`, `fit_rf_model`, `evaluate_rf_model`, `extract_rf_importance`, `plot_rf_importance`; no file I/O or hard-coded paths
- `scripts/06_random_forest.R` — pipeline driver: loads cleaned data, runs two cohorts × two outcomes, saves importance tables/plots/models

**Design decisions:**
- Input is `data/synthetic/synthetic_cohort_clean.rds` (unmatched), not matched data; RF goal is predictor importance, not treatment effect estimation
- Two cohorts: overall cleaned cohort (150,000 rows) and `clinical_binary_1 == 1` subcohort (13,794 rows, 9.2%) as a configurable example baseline-flag-defined subgroup
- Subcohort-defining variable (`clinical_binary_1`) is automatically excluded from the subcohort predictor set since it is constant within the subcohort
- Two-phase fitting: caret CV on a stratified 10,000-row tuning subset (event rate preserved) selects hyperparameters; final ranger model (500 trees, permutation importance) is fit on the full SMOTE'd training data using best params
- SMOTE `over_ratio = 0.5` applied to training data only (skip = TRUE on test)
- `doParallel` registered if available (7 cores on dev machine); graceful fallback to single-threaded
- `RF_DEV_MODE = FALSE` flag for quick single-model testing

**Outputs produced:**
- `outputs/tables/rf_importance_overall_outcome_1.csv`
- `outputs/tables/rf_importance_overall_outcome_2.csv`
- `outputs/tables/rf_importance_subcohort_outcome_1.csv`
- `outputs/tables/rf_importance_subcohort_outcome_2.csv`
- `outputs/figures/rf_importance_overall_outcome_1.png`
- `outputs/figures/rf_importance_overall_outcome_2.png`
- `outputs/figures/rf_importance_subcohort_outcome_1.png`
- `outputs/figures/rf_importance_subcohort_outcome_2.png`
- `outputs/tables/rf_auc_summary.csv`
- `outputs/models/rf_models.rds`

**Validation results:**
- 4 models fit, 0 skipped, across 2 cohorts × 2 outcomes
- Tuning subset: 10,000 rows, stratified by outcome, event rate preserved in all 4 models
- Overall cohort, Outcome 1: best tune mtry=3/min.node.size=30, test AUC=0.5430; top feature: demo_sex_X1
- Overall cohort, Outcome 2: best tune mtry=2/min.node.size=5, test AUC=0.6399; top feature: exposure_group_Exposure_B
- Subcohort, Outcome 1: best tune mtry=3/min.node.size=20, test AUC=0.5371; top feature: demo_sex_X1
- Subcohort, Outcome 2: best tune mtry=3/min.node.size=5, test AUC=0.5797; top feature: demo_sex_X1
- Warnings: "Setting row names on a tibble is deprecated" (from caret internals, non-breaking)

**Assumptions:**
- `caret`, `ranger`, `recipes`, `themis`, `pROC`, `ggplot2`, `tidyselect` must be installed; script fails fast with install instructions if any are missing
- `doParallel` is optional; script degrades gracefully without it
- Tuning subset assumes all factor levels present in the 10k sample; safe given large cohort and simple 2–3 level factors in this schema

## 2026-06-24 — Propensity score matching inserted before Cox modeling

**Task:** Insert PSM as `scripts/04_propensity_matching.R` between descriptive tables and Cox modeling; update Cox script to run on matched data as `scripts/05_cox_models.R`.

**Files created:**
- `R/propensity_matching.R` — `run_propensity_matching()`, `extract_psm_balance()`, `build_attempt_log_df()`; no file I/O or hard-coded paths
- `scripts/04_propensity_matching.R` — caliper search (0.20 → 0.01, step −0.01), selects first caliper with max covariate SMD < 0.10, saves matched data and balance tables
- `scripts/05_cox_models.R` — renamed from `scripts/04_cox_models.R`; loads matched data instead of cleaned data; fail-fast if matched file is missing

**Files edited:**
- `README.md` — updated project structure tree, running order, added PSM section, updated Cox section to reference script 05 and matched data, fixed Planned Workflow order (PSM before Cox)

**Files deleted:**
- `scripts/04_cox_models.R` — replaced by `scripts/05_cox_models.R`

**Outputs produced:**
- `data/synthetic/matched_clinical_data.rds` — 136,800-row matched cohort
- `outputs/models/matchit_object.rds` — fitted matchit object
- `outputs/tables/psm_balance_summary.csv` — per-variable SMD before and after matching
- `outputs/tables/psm_matching_summary.csv` — per-caliper attempt log (4 attempts)
- `outputs/tables/cox_results.csv` — 16 Cox models on matched cohort (overall + age 65+)
- `outputs/models/cox_models.rds` — named list of 16 fitted coxph objects

**Validation results:**
- Selected caliper: 0.17 SD
- Max matched SMD: 0.0956 (all covariates < 0.10)
- Matched sample n: 136,800 (retention: 91.2% of 150,000)
- Calipers tried: 4 (0.20, 0.19, 0.18 failed on `clinical_continuous_1`; 0.17 passed)
- Cox: 16 models fit, 0 skipped, across 2 cohorts × 2 outcomes × 4 model specs
- Age 65+ matched cohort: 86,010 rows

**Assumptions:**
- `MatchIt` package must be installed; fails fast with install instructions if missing
- Caliper is applied in propensity score SD units (`std.caliper = TRUE`)
- `distance` row excluded from SMD balance checks (covariate balance only)
- Matched data retains all original columns plus MatchIt columns (`weights`, `subclass`, `distance`); Cox validation and fitting are unaffected

## 2026-06-24 — Cox proportional hazards modeling workflow

**Task:** Add Cox survival modeling functions and a runnable pipeline script for two outcomes, four covariate models, and two cohorts.

**Files created:**
- `R/cox_modeling.R` — `fit_cox_model()` and `extract_cox_results()` functions; no file I/O, no hard-coded paths; explicit namespace syntax throughout
- `scripts/04_cox_models.R` — pipeline driver: loads cleaned data, defines outcome/model/cohort specs, validates inputs before every fit, skips gracefully on failure, saves outputs

**Outputs produced:**
- `outputs/tables/cox_results.csv` — combined per-term results (cohort_label, outcome_label, model_label, term, hazard_ratio, conf_low, conf_high, p_value)
- `outputs/models/cox_models.rds` — named list of 16 fitted coxph objects

**Validation results:**
- 16 models fit, 0 skipped
- 4 model specs × 2 outcomes × 2 cohorts (overall + age 65+)
- All 7 pre-fit validation checks passed for every combination
- `post_baseline_indicator` excluded via `validate_no_leakage_predictors()` / `LEAKAGE_VARS`
- Age 65+ cohort: 93,630 rows

**Assumptions:**
- `survival` package must be installed; fails fast with install instructions if missing
- `stats::confint()` used for CI extraction (S3 dispatch routes to `survival:::confint.coxph`; `survival::confint.coxph` is not exported)
- Cleaned data file (`data/synthetic/synthetic_cohort_clean.rds`) must exist; script stops with a clear message if missing

**Validation review (fail-fast theme):**
- All 10 validation concerns reviewed and confirmed PASS
- `scripts/04_cox_models.R` acts as the gatekeeper; `R/cox_modeling.R` is a pure modeling engine with no validation logic

## 2026-06-23 — Refactor descriptive tables to use tableone

**Task:** Replace custom summary logic with `tableone::CreateTableOne()` wrapper.

**Files edited:**
- `R/descriptive_tables.R` — replaced `create_baseline_table()` with `create_tableone_summary()`; kept `create_outcome_followup_summary()` unchanged
- `scripts/03_descriptive_tables.R` — added `factor_vars` definition; switched to `create_tableone_summary()`

**Outputs produced:**
- `outputs/tables/table1_baseline_characteristics.csv` — combined tableone output (overall + age 65+), columns: variable, cohort_label, Exposure_A, Exposure_B, p, test
- `outputs/tables/outcome_followup_summary.csv` — unchanged base-R summary

**Validation results:**
- No warnings; both CSVs written cleanly
- Overall cohort: Exposure_A n=74,138 / Exposure_B n=75,862
- Age 65+ cohort: Exposure_A n=42,839 / Exposure_B n=50,791
- `post_baseline_indicator` excluded (not in `baseline_vars`)
- All variable names use the synthetic schema from `R/config.R`

**Assumptions:**
- `tableone` package must be installed; fails fast with install instructions if missing
- `factor_vars` is passed explicitly to `CreateTableOne()` so numeric-coded binary vars are treated as categorical regardless of their storage type after cleaning

## 2026-06-22 — Descriptive tables workflow (initial)

**Task:** Add reusable Table 1 / descriptive summary functions for multiple cohorts.

**Files created:**
- `R/descriptive_tables.R` — `create_baseline_table()` and `create_outcome_followup_summary()` functions
- `scripts/03_descriptive_tables.R` — pipeline script for overall and age 65+ cohorts
