# cox_modeling.R
#
# Reusable functions for fitting Cox proportional hazards models and
# extracting tidy result tables. No file paths are hard-coded here.
# Package functions are called with explicit namespaces (pkg::fun).

# ---------------------------------------------------------------------------
# fit_cox_model
# ---------------------------------------------------------------------------

#' Fit a Cox proportional hazards model.
#'
#' @param data        Data frame (cleaned, type-cast).
#' @param time_var    Character: name of the follow-up time column (numeric > 0).
#' @param outcome_var Character: name of the binary event indicator column (0/1).
#' @param predictors  Character vector of right-hand side predictor names.
#' @return            A fitted coxph object.
fit_cox_model <- function(data, time_var, outcome_var, predictors) {

  if (!requireNamespace("survival", quietly = TRUE)) {
    stop(
      "Package 'survival' is required but is not installed.\n",
      "Install it with: install.packages(\"survival\")"
    )
  }

  rhs <- paste(predictors, collapse = " + ")
  formula_str <- sprintf("survival::Surv(%s, %s) ~ %s", time_var, outcome_var, rhs)
  cox_formula <- stats::as.formula(formula_str)

  survival::coxph(cox_formula, data = data)
}

# ---------------------------------------------------------------------------
# extract_cox_results
# ---------------------------------------------------------------------------

#' Extract per-term results from a fitted coxph object.
#'
#' @param model         Fitted coxph object from fit_cox_model().
#' @param cohort_label  Character: label for the cohort (e.g. "Overall cohort").
#' @param outcome_label Character: label for the outcome (e.g. "Outcome 1").
#' @param model_label   Character: label for the model (e.g. "Model 1: exposure only").
#' @return              A data frame with columns: cohort_label, outcome_label,
#'                      model_label, term, hazard_ratio, conf_low, conf_high,
#'                      p_value.
extract_cox_results <- function(model, cohort_label, outcome_label, model_label) {

  if (!requireNamespace("survival", quietly = TRUE)) {
    stop(
      "Package 'survival' is required but is not installed.\n",
      "Install it with: install.packages(\"survival\")"
    )
  }

  coef_mat <- summary(model)$coefficients
  conf_mat <- stats::confint(model)

  term_names <- rownames(coef_mat)
  n_terms    <- length(term_names)

  hr       <- exp(coef_mat[, "coef"])
  conf_low <- exp(conf_mat[, 1L])
  conf_hi  <- exp(conf_mat[, 2L])
  pval     <- coef_mat[, "Pr(>|z|)"]

  data.frame(
    cohort_label  = rep(cohort_label,  n_terms),
    outcome_label = rep(outcome_label, n_terms),
    model_label   = rep(model_label,   n_terms),
    term          = term_names,
    hazard_ratio  = hr,
    conf_low      = conf_low,
    conf_high     = conf_hi,
    p_value       = pval,
    row.names     = NULL,
    stringsAsFactors = FALSE
  )
}
