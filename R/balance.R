# balance.R
#
# Covariate balance assessment and the caliper search.
#
# The rule used throughout: balance is judged by the absolute standardized mean
# difference, not by a hypothesis test. At n = 20,000 a t-test will flag
# differences far too small to bias anything, so a "significant" imbalance and
# a "meaningful" imbalance are different claims.

#' Standardized mean difference for a single covariate.
#'
#' Continuous covariates use the pooled standard deviation of the two arms;
#' binary and categorical covariates use the binomial form on each indicator.
#' Both use the *unweighted, unmatched* pooled denominator when supplied, so
#' that before and after values are comparable on one scale -- comparing an
#' SMD computed with a post-match denominator against one computed with a
#' pre-match denominator is a common way to manufacture apparent balance.
smd_single <- function(x, treat, weights = NULL, denom = NULL) {
  if (is.null(weights)) weights <- rep(1, length(x))

  wmean <- function(v, w) sum(v * w) / sum(w)
  wvar  <- function(v, w) {
    m <- wmean(v, w)
    sum(w * (v - m)^2) / (sum(w) - sum(w^2) / sum(w))
  }

  i1 <- treat == 1
  i0 <- treat == 0

  m1 <- wmean(x[i1], weights[i1])
  m0 <- wmean(x[i0], weights[i0])

  if (is.null(denom)) {
    v1 <- wvar(x[i1], weights[i1])
    v0 <- wvar(x[i0], weights[i0])
    denom <- sqrt((v1 + v0) / 2)
  }
  if (!is.finite(denom) || denom == 0) return(0)
  (m1 - m0) / denom
}

#' Expand a data frame of covariates into a numeric design matrix.
#'
#' Factors become one indicator column per level (all levels, not level minus
#' one) so that every category gets its own balance row, which is how balance
#' tables are conventionally read.
expand_covariates <- function(data, vars) {
  out <- list()
  for (v in vars) {
    col <- data[[v]]
    if (is.factor(col) || is.character(col)) {
      col <- factor(col)
      for (lv in levels(col)) {
        out[[paste0(v, "_", lv)]] <- as.numeric(col == lv)
      }
    } else {
      out[[v]] <- as.numeric(col)
    }
  }
  as.data.frame(out, check.names = FALSE)
}

#' Balance table for a set of covariates.
#'
#' Returns one row per expanded covariate with its SMD, plus a logical flag
#' against the threshold. `denoms` lets a post-adjustment table reuse the
#' pre-adjustment standard deviations.
balance_table <- function(data, treat_var, vars, weights = NULL,
                          treat_level = NULL, denoms = NULL,
                          threshold = SMD_THRESHOLD) {
  tv <- data[[treat_var]]
  if (is.null(treat_level)) treat_level <- levels(factor(tv))[2]
  treat <- as.integer(as.character(tv) == treat_level)

  X <- expand_covariates(data, vars)
  if (is.null(weights)) weights <- rep(1, nrow(X))

  smds <- vapply(
    names(X),
    function(nm) smd_single(X[[nm]], treat, weights, denom = denoms[[nm]]),
    numeric(1)
  )

  data.frame(
    covariate = names(X),
    smd       = unname(smds),
    abs_smd   = abs(unname(smds)),
    balanced  = abs(unname(smds)) <= threshold,
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}

#' Pooled standard deviations from an unadjusted cohort, for reuse as denominators.
balance_denominators <- function(data, treat_var, vars, treat_level = NULL) {
  tv <- data[[treat_var]]
  if (is.null(treat_level)) treat_level <- levels(factor(tv))[2]
  treat <- as.integer(as.character(tv) == treat_level)

  X <- expand_covariates(data, vars)
  vapply(X, function(x) {
    v1 <- stats::var(x[treat == 1])
    v0 <- stats::var(x[treat == 0])
    sqrt((v1 + v0) / 2)
  }, numeric(1))
}

#' Search descending calipers for the loosest one achieving balance.
#'
#' Two things matter about the search direction. Tighter calipers buy balance
#' but discard subjects, so the loosest caliper meeting the threshold is the
#' one that keeps the most data. And every attempt is logged, including the
#' failures -- an attempt log is the evidence that balance was verified rather
#' than assumed.
#'
#' Returns the log and the selected fit, or raises an error if no caliper in
#' the grid achieves balance. It does not quietly return the best failure.
search_caliper <- function(data, treat_var, ps_vars, balance_vars,
                           calipers = CALIPER_GRID,
                           threshold = SMD_THRESHOLD,
                           seed = PROJECT_SEED) {
  fml <- stats::as.formula(
    paste(treat_var, "~", paste(ps_vars, collapse = " + "))
  )
  denoms <- balance_denominators(data, treat_var, balance_vars)

  log_rows <- list()
  selected <- NULL

  for (cal in calipers) {
    set.seed(seed)
    fit <- MatchIt::matchit(fml, data = data, method = "nearest",
                            distance = "glm", ratio = 1,
                            caliper = cal, std.caliper = TRUE)
    md  <- MatchIt::match.data(fit)
    tab <- balance_table(md, treat_var, balance_vars,
                         denoms = denoms, threshold = threshold)

    worst <- tab[which.max(tab$abs_smd), ]
    log_rows[[length(log_rows) + 1L]] <- data.frame(
      caliper          = cal,
      n_matched        = nrow(md),
      pct_retained     = round(100 * nrow(md) / nrow(data), 1),
      max_abs_smd      = round(worst$abs_smd, 4),
      worst_covariate  = worst$covariate,
      n_imbalanced     = sum(!tab$balanced),
      balanced         = all(tab$balanced),
      stringsAsFactors = FALSE
    )

    if (all(tab$balanced) && is.null(selected)) {
      selected <- list(caliper = cal, fit = fit, matched = md, balance = tab)
      break
    }
  }

  attempts <- do.call(rbind, log_rows)

  if (is.null(selected)) {
    stop(sprintf(
      paste0("No caliper in the grid achieved |SMD| <= %.2f on all covariates. ",
             "Best attempt: caliper %.2f, max |SMD| %.4f on %s. ",
             "Matching produced output, but it did not produce balance."),
      threshold,
      attempts$caliper[which.min(attempts$max_abs_smd)],
      min(attempts$max_abs_smd),
      attempts$worst_covariate[which.min(attempts$max_abs_smd)]
    ), call. = FALSE)
  }

  list(selected = selected, attempts = attempts, denominators = denoms)
}

# ---------------------------------------------------------------------------
# Weighting
# ---------------------------------------------------------------------------

#' Compute the three weighting schemes from a fitted propensity score.
#'
#' Overlap weights are 1 - ps for the treated and ps for the controls. They are
#' bounded in (0, 1) by construction, which is why they cannot produce the
#' extreme values that untruncated inverse-probability weights can.
create_weights <- function(ps, treat) {
  stopifnot(all(is.finite(ps)), all(ps > 0), all(ps < 1))

  p_treated <- mean(treat == 1)

  iptw    <- ifelse(treat == 1, 1 / ps, 1 / (1 - ps))
  sw_iptw <- ifelse(treat == 1, p_treated / ps, (1 - p_treated) / (1 - ps))
  overlap <- ifelse(treat == 1, 1 - ps, ps)

  stopifnot(all(overlap > 0), all(overlap < 1))
  data.frame(iptw = iptw, sw_iptw = sw_iptw, overlap_w = overlap)
}

#' Kish effective sample size.
#'
#' The quantity that says what a weighted analysis actually cost in precision.
#' A weighting scheme that balances covariates perfectly but drops the ESS to a
#' fraction of the cohort has not come for free.
effective_sample_size <- function(w) sum(w)^2 / sum(w^2)

#' Weight diagnostics, one row per method.
#'
#' Extreme-weight thresholds differ by method because the weights sit on
#' different scales. Overlap weights are bounded in (0, 1), so for those the
#' diagnostic reported instead is the share of subjects with a propensity score
#' outside the central range.
weight_diagnostics <- function(weights_df, ps, treat,
                               thresholds = WEIGHT_THRESHOLDS) {
  rows <- list()
  for (nm in c("iptw", "sw_iptw", "overlap_w")) {
    w <- weights_df[[nm]]
    extreme <- switch(
      nm,
      iptw      = sum(w > thresholds$iptw),
      sw_iptw   = sum(w > thresholds$sw_iptw),
      overlap_w = sum(ps < thresholds$overlap_ps[1] | ps > thresholds$overlap_ps[2])
    )
    criterion <- switch(
      nm,
      iptw      = sprintf("weight > %g", thresholds$iptw),
      sw_iptw   = sprintf("weight > %g", thresholds$sw_iptw),
      overlap_w = sprintf("PS outside [%g, %g]", thresholds$overlap_ps[1],
                          thresholds$overlap_ps[2])
    )
    rows[[nm]] <- data.frame(
      method       = nm,
      min          = round(min(w), 4),
      median       = round(stats::median(w), 4),
      mean         = round(mean(w), 4),
      max          = round(max(w), 4),
      criterion    = criterion,
      n_flagged    = extreme,
      ess_treated  = round(effective_sample_size(w[treat == 1]), 1),
      ess_control  = round(effective_sample_size(w[treat == 0]), 1),
      ess_total    = round(effective_sample_size(w), 1),
      stringsAsFactors = FALSE
    )
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}
