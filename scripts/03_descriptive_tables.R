# Generate descriptive summary tables (Table 1 style) for multiple cohorts.
#
# Reads the cleaned RDS produced by scripts/02_clean_data.R, generates
# baseline characteristic tables via tableone and outcome/follow-up summaries
# for:
#   - Overall cohort
#   - Age 65+ subcohort
# then saves combined CSVs to outputs/tables/.
#
# Run from the repository root:
#   Rscript scripts/03_descriptive_tables.R

source("R/config.R")
source("R/data_cleaning.R")
source("R/validation.R")
source("R/descriptive_tables.R")

# ---------------------------------------------------------------------------
# Input check
# ---------------------------------------------------------------------------

cleaned_path <- file.path("data", "synthetic", "synthetic_cohort_clean.rds")

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
# Variable definitions
# ---------------------------------------------------------------------------

baseline_vars <- c(
  "demo_age",
  "demo_sex",
  "demo_race",
  "clinical_binary_1",
  "clinical_binary_2",
  "clinical_binary_3",
  "clinical_binary_4",
  "clinical_binary_5",
  "clinical_binary_6",
  "clinical_continuous_1"
)

factor_vars <- c(
  "demo_sex",
  "demo_race",
  "clinical_binary_1",
  "clinical_binary_2",
  "clinical_binary_3",
  "clinical_binary_4",
  "clinical_binary_5",
  "clinical_binary_6"
)

outcome_vars  <- c("outcome_1",       "outcome_2")
followup_vars <- c("followup_time_1", "followup_time_2")

# ---------------------------------------------------------------------------
# Validate columns exist
# ---------------------------------------------------------------------------

validate_predictor_columns(df_clean, baseline_vars)
validate_predictor_columns(df_clean, outcome_vars)
validate_predictor_columns(df_clean, followup_vars)

for (ov in outcome_vars) validate_binary_outcome(df_clean, ov)
for (fv in followup_vars) validate_survival_time(df_clean, fv)

# ---------------------------------------------------------------------------
# Overall cohort
# ---------------------------------------------------------------------------

cat("Overall cohort exposure group counts:\n")
print(table(df_clean[[GROUP_VAR]], useNA = "ifany"))
cat("\n")

validate_two_group_exposure(df_clean, GROUP_VAR)

tbl_overall <- create_tableone_summary(
  data         = df_clean,
  vars         = baseline_vars,
  strata       = GROUP_VAR,
  factor_vars  = factor_vars,
  cohort_label = "Overall cohort"
)

out_overall <- create_outcome_followup_summary(
  data          = df_clean,
  exposure_var  = GROUP_VAR,
  outcome_vars  = outcome_vars,
  followup_vars = followup_vars,
  cohort_label  = "Overall cohort"
)

# ---------------------------------------------------------------------------
# Age 65+ subcohort
# ---------------------------------------------------------------------------

df_age65 <- create_age_subcohort(df_clean, age_cutoff = 65)

cat("Age 65+ subcohort row count: ", nrow(df_age65), "\n")
cat("Age 65+ subcohort exposure group counts:\n")
print(table(df_age65[[GROUP_VAR]], useNA = "ifany"))
cat("\n")

n_groups_age65 <- length(unique(as.character(
  df_age65[[GROUP_VAR]][!is.na(df_age65[[GROUP_VAR]])]
)))

if (n_groups_age65 < 2L) {
  warning(sprintf(
    "Age 65+ subcohort has only %d exposure group(s); between-group summaries may be uninformative.",
    n_groups_age65
  ))
}

tbl_age65 <- create_tableone_summary(
  data         = df_age65,
  vars         = baseline_vars,
  strata       = GROUP_VAR,
  factor_vars  = factor_vars,
  cohort_label = "Age 65+ cohort"
)

out_age65 <- create_outcome_followup_summary(
  data          = df_age65,
  exposure_var  = GROUP_VAR,
  outcome_vars  = outcome_vars,
  followup_vars = followup_vars,
  cohort_label  = "Age 65+ cohort"
)

# ---------------------------------------------------------------------------
# Combine and save
# ---------------------------------------------------------------------------

if (!dir.exists(PATHS$output_tables)) {
  dir.create(PATHS$output_tables, recursive = TRUE)
}

tbl_combined <- rbind(tbl_overall, tbl_age65)
out_combined <- rbind(out_overall, out_age65)

path_baseline <- file.path(PATHS$output_tables, "table1_baseline_characteristics.csv")
path_outcomes <- file.path(PATHS$output_tables, "outcome_followup_summary.csv")

write.csv(tbl_combined, path_baseline, row.names = FALSE)
write.csv(out_combined, path_outcomes, row.names = FALSE)

cat("Saved combined baseline table to:           ", path_baseline, "\n")
cat("Saved combined outcome/follow-up summary to:", path_outcomes, "\n")
