# Apply propensity score matching to the cleaned synthetic cohort.
# Uses nearest-neighbor 1:1 matching via MatchIt::matchit() with caliper
# search from 0.20 down to 0.01 (SD units). Selects the first caliper
# where every baseline covariate has absolute SMD < 0.10.
#
# Run from the repository root:
#   Rscript scripts/04_propensity_matching.R

source("R/config.R")
source("R/validation.R")
source("R/propensity_matching.R")

if (!requireNamespace("MatchIt", quietly = TRUE)) {
  stop(
    "Package 'MatchIt' is required but is not installed.\n",
    "Install it with: install.packages(\"MatchIt\")"
  )
}

# ---------------------------------------------------------------------------
# Input check
# ---------------------------------------------------------------------------

cleaned_path <- PATHS$data_clean

if (!file.exists(cleaned_path)) {
  stop(
    "Cleaned data file not found: ", cleaned_path, "\n",
    "Run scripts/02_clean_data.R first."
  )
}

# ---------------------------------------------------------------------------
# Load cleaned data
# ---------------------------------------------------------------------------

df_clean <- readRDS(cleaned_path)

cat("Cleaned data loaded.\n")
cat("  Rows:    ", nrow(df_clean), "\n")
cat("  Columns: ", ncol(df_clean), "\n\n")

# ---------------------------------------------------------------------------
# Pre-matching validation
# ---------------------------------------------------------------------------

validate_two_group_exposure(df_clean, GROUP_VAR)
validate_predictor_columns(df_clean, PSM_FORMULA_VARS)
validate_no_leakage_predictors(PSM_FORMULA_VARS, LEAKAGE_VARS)

cat("Pre-matching validation passed.\n\n")

# ---------------------------------------------------------------------------
# Propensity score matching
# ---------------------------------------------------------------------------

calipers <- seq(0.20, 0.01, by = -0.01)

cat(sprintf(
  "Running caliper search (nearest-neighbor, ratio = 1, calipers %.2f to %.2f):\n",
  max(calipers), min(calipers)
))

set.seed(PROJECT_SEED)

psm_result <- run_propensity_matching(
  data          = df_clean,
  treatment_var = GROUP_VAR,
  formula_vars  = PSM_FORMULA_VARS,
  calipers      = calipers,
  smd_threshold = 0.10
)

# ---------------------------------------------------------------------------
# Ensure output directories exist
# ---------------------------------------------------------------------------

if (!dir.exists(PATHS$output_tables)) dir.create(PATHS$output_tables, recursive = TRUE)
if (!dir.exists(PATHS$output_models)) dir.create(PATHS$output_models, recursive = TRUE)

# ---------------------------------------------------------------------------
# Save outputs
# ---------------------------------------------------------------------------

matched_data_path  <- PATHS$data_matched
matchit_obj_path   <- file.path(PATHS$output_models, "matchit_object.rds")
balance_table_path <- file.path(PATHS$output_tables, "psm_balance_summary.csv")
matching_log_path  <- file.path(PATHS$output_tables, "psm_matching_summary.csv")

saveRDS(psm_result$matched_data, matched_data_path)
saveRDS(psm_result$matchit_obj,  matchit_obj_path)

balance_df <- extract_psm_balance(psm_result$matchit_obj)
write.csv(balance_df, balance_table_path, row.names = FALSE)

attempt_df <- build_attempt_log_df(psm_result$attempt_log)
write.csv(attempt_df, matching_log_path, row.names = FALSE)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

sel <- psm_result$selected

cat("\n")
cat("====================================================\n")
cat("Propensity score matching summary\n")
cat("====================================================\n")
cat(sprintf("  Selected caliper:   %.2f SD\n",  sel$caliper))
cat(sprintf("  Max matched SMD:    %.4f\n",      sel$max_smd))
cat(sprintf("  Matched sample n:   %d\n",        sel$matched_n))
cat(sprintf("  Retention rate:     %.1f%%\n",    sel$retention_rate * 100))
cat(sprintf("  Calipers tried:     %d\n",        length(psm_result$attempt_log)))
cat("\n")
cat("Output files:\n")
cat("  Matched data:       ", matched_data_path,  "\n")
cat("  MatchIt object:     ", matchit_obj_path,   "\n")
cat("  Balance summary:    ", balance_table_path, "\n")
cat("  Matching log:       ", matching_log_path,  "\n")
