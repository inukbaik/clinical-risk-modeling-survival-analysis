# Clean and validate the synthetic clinical cohort.
#
# Reads the raw CSV produced by scripts/01_generate_synthetic_data.R,
# applies clean_clinical_data(), saves the result as an RDS file, and
# prints a validation summary.
#
# Run from the repository root:
#   Rscript scripts/02_clean_data.R

source("R/config.R")
source("R/data_cleaning.R")

# ---------------------------------------------------------------------------
# Check input
# ---------------------------------------------------------------------------

if (!file.exists(PATHS$data_raw)) {
  stop(
    "Raw data file not found: ", PATHS$data_raw, "\n",
    "Run scripts/01_generate_synthetic_data.R first."
  )
}

# ---------------------------------------------------------------------------
# Load raw data
# ---------------------------------------------------------------------------

raw <- read.csv(PATHS$data_raw, stringsAsFactors = FALSE)

cat("Raw data loaded.\n")
cat("  Rows:    ", nrow(raw), "\n")
cat("  Columns: ", ncol(raw), "\n\n")

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

cleaned <- clean_clinical_data(raw)

cat("\nCleaned data ready.\n")
cat("  Rows:    ", nrow(cleaned), "\n")
cat("  Columns: ", ncol(cleaned), "\n")

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

output_path <- file.path("data", "synthetic", "synthetic_cohort_clean.rds")

saveRDS(cleaned, output_path)
cat("\nCleaned dataset saved to:", output_path, "\n")

# ---------------------------------------------------------------------------
# Validation summary
# ---------------------------------------------------------------------------

cat("\n--- Validation summary ---\n")

cat("\nexposure_group counts:\n")
print(table(cleaned$exposure_group, useNA = "ifany"))

cat("\noutcome_1 counts:\n")
print(table(cleaned$outcome_1, useNA = "ifany"))

cat("\noutcome_2 counts:\n")
print(table(cleaned$outcome_2, useNA = "ifany"))

cat("\nfollowup_time_1 summary:\n")
print(summary(cleaned$followup_time_1))

cat("\nfollowup_time_2 summary:\n")
print(summary(cleaned$followup_time_2))
