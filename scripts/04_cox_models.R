# Fit Cox proportional hazards models for the synthetic clinical cohort.
#
# Models are fit for two outcomes, four covariate sets, and two cohorts
# (overall and age 65+). Validation runs before each model; failed
# validations are recorded and skipped rather than halting the pipeline.
#
# Run from the repository root:
#   Rscript scripts/04_cox_models.R

source("R/config.R")
source("R/data_cleaning.R")
source("R/validation.R")
source("R/cox_modeling.R")

if (!requireNamespace("survival", quietly = TRUE)) {
  stop(
    "Package 'survival' is required but is not installed.\n",
    "Install it with: install.packages(\"survival\")"
  )
}

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
# Outcome specifications
# ---------------------------------------------------------------------------

outcome_specs <- list(
  outcome_1 = list(
    event_var = "outcome_1",
    time_var  = "followup_time_1",
    label     = "Outcome 1"
  ),
  outcome_2 = list(
    event_var = "outcome_2",
    time_var  = "followup_time_2",
    label     = "Outcome 2"
  )
)

# ---------------------------------------------------------------------------
# Model specifications
# ---------------------------------------------------------------------------

binary_clinical <- c(
  "clinical_binary_1",
  "clinical_binary_2",
  "clinical_binary_3",
  "clinical_binary_4",
  "clinical_binary_5",
  "clinical_binary_6"
)

model_specs <- list(
  list(
    label      = "Model 1: exposure only",
    predictors = c("exposure_group")
  ),
  list(
    label      = "Model 2: exposure + demographics",
    predictors = c("exposure_group", "demo_age", "demo_sex", "demo_race")
  ),
  list(
    label      = "Model 3: model 2 + binary clinical",
    predictors = c("exposure_group", "demo_age", "demo_sex", "demo_race",
                   binary_clinical)
  ),
  list(
    label      = "Model 4: model 3 + continuous clinical",
    predictors = c("exposure_group", "demo_age", "demo_sex", "demo_race",
                   binary_clinical, "clinical_continuous_1")
  )
)

# ---------------------------------------------------------------------------
# Cohort definitions
# ---------------------------------------------------------------------------

df_age65 <- create_age_subcohort(df_clean, age_cutoff = 65)

cohort_list <- list(
  list(label = "Overall cohort", data = df_clean),
  list(label = "Age 65+ cohort", data = df_age65)
)

# ---------------------------------------------------------------------------
# Ensure output directories exist
# ---------------------------------------------------------------------------

if (!dir.exists(PATHS$output_tables)) {
  dir.create(PATHS$output_tables, recursive = TRUE)
}
if (!dir.exists(PATHS$output_models)) {
  dir.create(PATHS$output_models, recursive = TRUE)
}

# ---------------------------------------------------------------------------
# Fit models
# ---------------------------------------------------------------------------

all_results  <- list()
all_models   <- list()
skipped_msgs <- character(0)
fit_count    <- 0L

for (cohort in cohort_list) {

  cat(sprintf("\n=== Cohort: %s ===\n", cohort$label))
  cat(sprintf("    Rows: %d\n", nrow(cohort$data)))

  for (oc in outcome_specs) {

    cat(sprintf("\n  Outcome: %s\n", oc$label))

    for (ms in model_specs) {

      run_label <- sprintf(
        "[%s | %s | %s]",
        cohort$label, oc$label, ms$label
      )

      skip_msg <- tryCatch({

        validate_two_group_exposure(cohort$data, "exposure_group")
        validate_binary_outcome(cohort$data, oc$event_var)
        validate_min_events(cohort$data, oc$event_var, min_events = 10L)
        validate_survival_time(cohort$data, oc$time_var)
        validate_predictor_columns(cohort$data, ms$predictors)
        validate_factor_levels(cohort$data, ms$predictors)
        validate_no_leakage_predictors(ms$predictors, LEAKAGE_VARS)

        NULL
      }, error = function(e) {
        conditionMessage(e)
      })

      if (!is.null(skip_msg)) {
        msg <- sprintf("  SKIP %s\n    Reason: %s", run_label, skip_msg)
        cat(msg, "\n")
        skipped_msgs <- c(skipped_msgs, msg)
        next
      }

      fit <- tryCatch(
        fit_cox_model(
          data        = cohort$data,
          time_var    = oc$time_var,
          outcome_var = oc$event_var,
          predictors  = ms$predictors
        ),
        error = function(e) {
          list(.error = conditionMessage(e))
        }
      )

      if (!is.null(fit$.error)) {
        msg <- sprintf(
          "  SKIP %s\n    Reason: coxph() failed: %s",
          run_label, fit$.error
        )
        cat(msg, "\n")
        skipped_msgs <- c(skipped_msgs, msg)
        next
      }

      result_df <- extract_cox_results(
        model         = fit,
        cohort_label  = cohort$label,
        outcome_label = oc$label,
        model_label   = ms$label
      )

      model_key           <- gsub("[ |]+", "_", run_label)
      all_results[[model_key]] <- result_df
      all_models[[model_key]]  <- fit
      fit_count <- fit_count + 1L

      cat(sprintf("    fit: %s\n", ms$label))
    }
  }
}

# ---------------------------------------------------------------------------
# Save outputs
# ---------------------------------------------------------------------------

path_results <- file.path(PATHS$output_tables, "cox_results.csv")
path_models  <- file.path(PATHS$output_models, "cox_models.rds")

if (length(all_results) > 0L) {
  combined_results <- do.call(rbind, all_results)
  row.names(combined_results) <- NULL
  write.csv(combined_results, path_results, row.names = FALSE)
  saveRDS(all_models, path_models)
} else {
  stop(
    "No Cox models were successfully fit. ",
    "Check validation errors above and re-run scripts/02_clean_data.R if needed."
  )
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

cat("\n")
cat("====================================================\n")
cat("Cox modeling summary\n")
cat("====================================================\n")
cat(sprintf("  Cohorts modeled:     %s\n",
    paste(sapply(cohort_list, `[[`, "label"), collapse = ", ")))
cat(sprintf("  Outcomes modeled:    %s\n",
    paste(sapply(outcome_specs, `[[`, "label"), collapse = ", ")))
cat(sprintf("  Models fit:          %d\n", fit_count))

if (length(skipped_msgs) > 0L) {
  cat(sprintf("  Models skipped:      %d\n", length(skipped_msgs)))
  cat("\nSkipped model details:\n")
  for (m in skipped_msgs) cat(m, "\n")
} else {
  cat("  Models skipped:      0\n")
}

cat("\n")
cat("Output files:\n")
cat("  Cox results table:  ", path_results, "\n")
cat("  Fitted models RDS:  ", path_models,  "\n")
