# inference.R
#
# Extraction of estimates from fitted models into tidy rows.
#
# Every hazard ratio in this project is assembled here rather than read out of
# summary() piecemeal at each call site, so that one definition of "the
# estimate, its interval and its p-value" applies everywhere and the tables
# cannot silently disagree with each other.

#' Build one result row from a fitted Cox or Fine-Gray model.
#'
#' `se_source` selects which stored variance is used:
#'   "robust" -- the sandwich variance in fit$var, used whenever the model
#'               carries analytic weights or repeated rows per subject
#'   "naive"  -- the model-based variance in fit$naive.var
#'
#' The Wald statistic, interval and p-value are all computed from the chosen
#' standard error rather than read from summary(), so the reported p-value and
#' the reported interval are guaranteed to come from the same variance.
model_result_row <- function(fit, term = 1L, label, model = "",
                             se_source = c("robust", "naive"),
                             extra = list()) {
  se_source <- match.arg(se_source)

  coefs <- stats::coef(fit)
  idx   <- if (is.character(term)) match(term, names(coefs)) else term
  if (is.na(idx)) {
    stop(sprintf("Term '%s' not found in model '%s'.", term, label), call. = FALSE)
  }

  vmat <- if (se_source == "robust") fit$var else fit$naive.var
  if (is.null(vmat)) {
    stop(sprintf(
      "Model '%s' has no %s variance stored. A %s standard error requires %s.",
      label, se_source, se_source,
      if (se_source == "robust") "robust = TRUE" else "an unweighted fit"
    ), call. = FALSE)
  }

  beta <- unname(coefs[idx])
  se   <- unname(sqrt(diag(vmat))[idx])
  z    <- beta / se
  crit <- stats::qnorm(0.975)

  out <- data.frame(
    analysis  = label,
    model     = model,
    estimate  = exp(beta),
    ci_lower  = exp(beta - crit * se),
    ci_upper  = exp(beta + crit * se),
    se_log    = se,
    z         = z,
    p_value   = 2 * stats::pnorm(-abs(z)),
    se_source = se_source,
    stringsAsFactors = FALSE
  )
  for (nm in names(extra)) out[[nm]] <- extra[[nm]]
  out
}

#' Format an estimate and its interval for display.
fmt_est_ci <- function(est, lo, hi, digits = 2) {
  sprintf(paste0("%.", digits, "f (%.", digits, "f–%.", digits, "f)"),
          est, lo, hi)
}

#' Format a p-value, without pretending to precision that is not there.
fmt_p <- function(p) {
  ifelse(p < 0.001, "<0.001", sprintf("%.3f", p))
}

#' Add a display column to a table of result rows.
add_display <- function(df, digits = 2) {
  df$hr_ci <- fmt_est_ci(df$estimate, df$ci_lower, df$ci_upper, digits)
  df$p     <- fmt_p(df$p_value)
  df
}

# ---------------------------------------------------------------------------
# Proportional hazards checking
# ---------------------------------------------------------------------------

#' Joint Wald test on a subset of coefficients using the robust covariance.
#'
#' Used for the interval-interaction check below, where the null is that every
#' treatment-by-period interaction is zero simultaneously.
robust_wald_test <- function(fit, idx) {
  b <- stats::coef(fit)[idx]
  V <- fit$var[idx, idx, drop = FALSE]
  stat <- as.numeric(t(b) %*% solve(V) %*% b)
  df   <- length(idx)
  list(statistic = stat, df = df,
       p_value = stats::pchisq(stat, df = df, lower.tail = FALSE))
}

#' Test proportional hazards by splitting follow-up into intervals.
#'
#' The model gains a treatment-by-period interaction; if the hazard ratio is
#' constant over time those interaction terms should be jointly null. This is
#' used instead of cox.zph() wherever the model is weighted or has repeated
#' rows per subject -- cox.zph() has no valid interpretation for a Fine-Gray
#' fit, since the risk set there is artificial by construction.
ph_interval_test <- function(data, time_var, event_var, group_var,
                             weight_var = NULL, id_var, cuts, label) {
  # survSplit parses the response off the formula, so the working columns get
  # plain names -- a leading dot is not recognised there.
  d <- data.frame(
    ph_time  = data[[time_var]],
    ph_event = as.integer(data[[event_var]]),
    ph_group = data[[group_var]],
    ph_id    = data[[id_var]],
    ph_w     = if (is.null(weight_var)) 1 else data[[weight_var]]
  )

  # survSplit inspects the formula and requires the response to be a literal
  # Surv(...) call -- a survival::Surv(...) prefix is a different call object
  # and is rejected with "left hand side not recognized".
  Surv <- survival::Surv

  split <- survival::survSplit(
    Surv(ph_time, ph_event) ~ ., data = d, cut = cuts,
    episode = "period", zero = -1
  )

  fit <- survival::coxph(
    Surv(tstart, ph_time, ph_event) ~ ph_group * factor(period),
    data = split, weights = ph_w, id = ph_id, robust = TRUE
  )

  idx <- grep(":", names(stats::coef(fit)))
  if (length(idx) == 0) {
    return(data.frame(analysis = label, statistic = NA_real_, df = NA_integer_,
                      p_value = NA_real_,
                      conclusion = "Not assessed", stringsAsFactors = FALSE))
  }

  w <- robust_wald_test(fit, idx)
  data.frame(
    analysis   = label,
    statistic  = round(w$statistic, 3),
    df         = w$df,
    p_value    = w$p_value,
    conclusion = ph_status_label(w$p_value),
    stringsAsFactors = FALSE
  )
}

#' Describe the result of a PH check without overclaiming.
#'
#' A non-significant test is not evidence that hazards are proportional; it is
#' an absence of evidence that they are not. The wording here says only that.
ph_status_label <- function(p) {
  ifelse(
    is.na(p), "Not assessed",
    ifelse(p < 0.05,
           "Evidence against a constant hazard ratio over follow-up.",
           "No evidence against a constant hazard ratio over follow-up.")
  )
}
