# data_cleaning.R
#
# Functions for loading, validating, and type-casting the synthetic cohort.
# All functions accept a data frame and return a data frame; no side effects.
# Package functions are called with explicit namespaces (pkg::fun) so that
# this file does not need to be loaded after a library() call.

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.REQUIRED_COLUMNS <- c(
  "record_id",
  "demo_age",
  "demo_sex",
  "demo_race",
  "clinical_binary_1",
  "clinical_binary_2",
  "clinical_binary_3",
  "clinical_binary_4",
  "clinical_binary_5",
  "clinical_binary_6",
  "clinical_continuous_1",
  "exposure_group",
  "outcome_1",
  "outcome_2",
  "followup_time_1",
  "followup_time_2",
  "post_baseline_indicator"
)

.validate_columns <- function(data) {
  missing <- setdiff(.REQUIRED_COLUMNS, names(data))
  if (length(missing) > 0) {
    stop(
      "clean_clinical_data: missing required column(s): ",
      paste(missing, collapse = ", ")
    )
  }
  invisible(TRUE)
}

.remove_invalid_followup <- function(data) {
  n_before <- nrow(data)

  valid <- !is.na(data[["followup_time_1"]]) &
           !is.na(data[["followup_time_2"]]) &
           data[["followup_time_1"]] > 0 &
           data[["followup_time_2"]] > 0

  n_removed <- n_before - sum(valid)

  if (n_removed > 0) {
    message(sprintf(
      "clean_clinical_data: removed %d record(s) with missing or non-positive follow-up time (%d remaining).",
      n_removed, sum(valid)
    ))
  }

  data[valid, , drop = FALSE]
}

# ---------------------------------------------------------------------------
# Primary cleaning function
# ---------------------------------------------------------------------------

#' Clean and type-cast the synthetic clinical cohort.
#'
#' @param data  Raw data frame as read from CSV (e.g. via read.csv or
#'              data.table::fread). Column names must match the expected
#'              schema defined in .REQUIRED_COLUMNS.
#' @return      A data frame with correctly typed columns, exposure_group
#'              factored with Exposure_A as reference, and binary clinical
#'              variables and demographic flags coerced to factor.
clean_clinical_data <- function(data) {

  .validate_columns(data)
  data <- .remove_invalid_followup(data)

  # --- Identifier (keep as-is) -------------------------------------------
  # record_id is left as integer; no factoring needed.

  # --- Continuous numerics ------------------------------------------------
  data[["demo_age"]]            <- as.numeric(data[["demo_age"]])
  data[["clinical_continuous_1"]] <- as.numeric(data[["clinical_continuous_1"]])

  # --- Follow-up times (numeric, in years) --------------------------------
  data[["followup_time_1"]] <- as.numeric(data[["followup_time_1"]])
  data[["followup_time_2"]] <- as.numeric(data[["followup_time_2"]])

  # --- Event indicators (integer 0/1) -------------------------------------
  data[["outcome_1"]] <- as.integer(data[["outcome_1"]])
  data[["outcome_2"]] <- as.integer(data[["outcome_2"]])

  # --- Exposure group (factor; Exposure_A is reference) -------------------
  data[["exposure_group"]] <- factor(
    data[["exposure_group"]],
    levels = c("Exposure_A", "Exposure_B")
  )

  # --- Demographic factors ------------------------------------------------
  data[["demo_sex"]]  <- factor(data[["demo_sex"]])
  data[["demo_race"]] <- factor(data[["demo_race"]])

  # --- Binary clinical predictors (factor) --------------------------------
  binary_vars <- c(
    "clinical_binary_1",
    "clinical_binary_2",
    "clinical_binary_3",
    "clinical_binary_4",
    "clinical_binary_5",
    "clinical_binary_6"
  )
  for (v in binary_vars) {
    data[[v]] <- factor(data[[v]], levels = c(0L, 1L))
  }

  # --- Post-baseline indicator (factor; excluded from RF by LEAKAGE_VARS) -
  data[["post_baseline_indicator"]] <- factor(
    data[["post_baseline_indicator"]],
    levels = c(0L, 1L)
  )

  data
}

# ---------------------------------------------------------------------------
# Subcohort constructor
# ---------------------------------------------------------------------------

#' Restrict cohort to records at or above an age threshold.
#'
#' @param data        Data frame previously processed by clean_clinical_data().
#' @param age_cutoff  Minimum age (inclusive). Defaults to 65.
#' @return            Filtered data frame; original row order is preserved.
create_age_subcohort <- function(data, age_cutoff = 65) {

  if (!"demo_age" %in% names(data)) {
    stop("create_age_subcohort: 'demo_age' column not found.")
  }
  if (!is.numeric(data[["demo_age"]])) {
    stop("create_age_subcohort: 'demo_age' must be numeric. Run clean_clinical_data() first.")
  }
  if (!is.numeric(age_cutoff) || length(age_cutoff) != 1L || is.na(age_cutoff)) {
    stop("create_age_subcohort: 'age_cutoff' must be a single non-missing numeric value.")
  }

  subset(data, demo_age >= age_cutoff)
}
