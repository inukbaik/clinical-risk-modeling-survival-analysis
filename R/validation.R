# Each function stops with a clear message on failure and returns invisible(TRUE)
# on success. Functions are intentionally independent so they can be called
# in any order.

# ---------------------------------------------------------------------------
# validate_binary_outcome
# ---------------------------------------------------------------------------
# Confirms that outcome_var exists, is integer or numeric, contains only
# 0 and 1 (no other values, no NAs).

validate_binary_outcome <- function(data, outcome_var) {
  if (!outcome_var %in% names(data)) {
    stop(sprintf(
      "validate_binary_outcome: column '%s' not found in data.",
      outcome_var
    ))
  }

  col <- data[[outcome_var]]

  if (!is.numeric(col) && !is.integer(col)) {
    stop(sprintf(
      "validate_binary_outcome: '%s' must be numeric or integer (found %s).",
      outcome_var, class(col)
    ))
  }

  if (anyNA(col)) {
    stop(sprintf(
      "validate_binary_outcome: '%s' contains %d NA value(s).",
      outcome_var, sum(is.na(col))
    ))
  }

  bad <- setdiff(unique(col), c(0L, 1L))
  if (length(bad) > 0) {
    stop(sprintf(
      "validate_binary_outcome: '%s' contains values other than 0 and 1: %s.",
      outcome_var, paste(bad, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# validate_min_events
# ---------------------------------------------------------------------------
# Confirms that the number of observed events (outcome_var == 1) meets or
# exceeds min_events. Relies on validate_binary_outcome for preconditions.

validate_min_events <- function(data, outcome_var, min_events = 10) {
  validate_binary_outcome(data, outcome_var)

  n_events <- sum(data[[outcome_var]] == 1L)

  if (n_events < min_events) {
    stop(sprintf(
      "validate_min_events: '%s' has only %d event(s); minimum required is %d.",
      outcome_var, n_events, min_events
    ))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# validate_survival_time
# ---------------------------------------------------------------------------
# Confirms that time_var exists, is numeric, has no NAs, and is strictly
# positive in every row.

validate_survival_time <- function(data, time_var) {
  if (!time_var %in% names(data)) {
    stop(sprintf(
      "validate_survival_time: column '%s' not found in data.",
      time_var
    ))
  }

  col <- data[[time_var]]

  if (!is.numeric(col)) {
    stop(sprintf(
      "validate_survival_time: '%s' must be numeric (found %s).",
      time_var, class(col)
    ))
  }

  if (anyNA(col)) {
    stop(sprintf(
      "validate_survival_time: '%s' contains %d NA value(s).",
      time_var, sum(is.na(col))
    ))
  }

  n_nonpos <- sum(col <= 0)
  if (n_nonpos > 0) {
    stop(sprintf(
      "validate_survival_time: '%s' has %d non-positive value(s); all follow-up times must be > 0.",
      time_var, n_nonpos
    ))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# validate_two_group_exposure
# ---------------------------------------------------------------------------
# Confirms that exposure_var exists and has exactly two distinct non-NA
# groups. Works with character, factor, or integer columns.

validate_two_group_exposure <- function(data, exposure_var) {
  if (!exposure_var %in% names(data)) {
    stop(sprintf(
      "validate_two_group_exposure: column '%s' not found in data.",
      exposure_var
    ))
  }

  col <- data[[exposure_var]]

  if (anyNA(col)) {
    stop(sprintf(
      "validate_two_group_exposure: '%s' contains %d NA value(s).",
      exposure_var, sum(is.na(col))
    ))
  }

  n_groups <- length(unique(col))

  if (n_groups != 2L) {
    stop(sprintf(
      "validate_two_group_exposure: '%s' must have exactly 2 groups (found %d: %s).",
      exposure_var, n_groups,
      paste(sort(unique(as.character(col))), collapse = ", ")
    ))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# validate_predictor_columns
# ---------------------------------------------------------------------------
# Confirms that every name in predictors is present as a column in data.

validate_predictor_columns <- function(data, predictors) {
  missing <- setdiff(predictors, names(data))

  if (length(missing) > 0) {
    stop(sprintf(
      "validate_predictor_columns: %d predictor column(s) not found in data: %s.",
      length(missing), paste(missing, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# validate_no_leakage_predictors
# ---------------------------------------------------------------------------
# Confirms that none of the names in predictors appear in leakage_vars.
# Both arguments are character vectors of variable names.

validate_no_leakage_predictors <- function(predictors, leakage_vars) {
  leaked <- intersect(predictors, leakage_vars)

  if (length(leaked) > 0) {
    stop(sprintf(
      "validate_no_leakage_predictors: %d leakage variable(s) found in predictor list: %s.",
      length(leaked), paste(leaked, collapse = ", ")
    ))
  }

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# validate_factor_levels
# ---------------------------------------------------------------------------
# For every predictor in predictors that is a factor or character column,
# confirms that at least 2 distinct non-NA levels are observed in data.
# Single-level factors cause model fitting to fail or produce degenerate
# results and should be caught before modeling.

validate_factor_levels <- function(data, predictors) {
  validate_predictor_columns(data, predictors)

  bad <- character(0)

  for (v in predictors) {
    col <- data[[v]]

    if (is.factor(col) || is.character(col)) {
      n_levels <- length(unique(col[!is.na(col)]))

      if (n_levels < 2L) {
        bad <- c(bad, sprintf("'%s' (%d observed level)", v, n_levels))
      }
    }
  }

  if (length(bad) > 0) {
    stop(sprintf(
      "validate_factor_levels: the following factor/character predictor(s) have fewer than 2 observed levels: %s.",
      paste(bad, collapse = "; ")
    ))
  }

  invisible(TRUE)
}
