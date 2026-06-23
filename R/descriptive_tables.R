# Reusable functions for generating descriptive summary tables.
# Table 1 is generated via tableone::CreateTableOne().

# ---------------------------------------------------------------------------
# Package check
# ---------------------------------------------------------------------------

if (!requireNamespace("tableone", quietly = TRUE)) {
  stop(
    "The 'tableone' package is required but is not installed.\n",
    "Install it with: install.packages(\"tableone\")"
  )
}

# ---------------------------------------------------------------------------
# create_tableone_summary
# ---------------------------------------------------------------------------

#' Generate a Table 1 style summary via tableone::CreateTableOne().
#'
#' @param data          Data frame (clean, typed).
#' @param vars          Character vector of variable names to summarise.
#' @param strata        Character vector of strata column name(s), or NULL for
#'                      an unstratified overall table.
#' @param factor_vars   Character vector of variables to treat as categorical
#'                      even if stored as numeric.
#' @param cohort_label  Label attached to every row of the output (default
#'                      "Overall cohort"). Allows rbind-combining across cohorts.
#' @param include_na    Passed to tableone::CreateTableOne() includeNA argument.
#' @param smd           Logical. If TRUE, include standardised mean differences.
#' @return              A data frame with columns: variable, cohort_label, and
#'                      one column per stratum level (or "Overall" when unstratified),
#'                      plus an "p" column and optionally "SMD". Suitable for
#'                      write.csv() and rbind() across cohorts.
create_tableone_summary <- function(data,
                                    vars,
                                    strata       = NULL,
                                    factor_vars  = character(0),
                                    cohort_label = "Overall cohort",
                                    include_na   = FALSE,
                                    smd          = FALSE) {

  if (!is.data.frame(data)) {
    stop("create_tableone_summary: 'data' must be a data frame.")
  }

  missing_vars <- setdiff(vars, names(data))
  if (length(missing_vars) > 0) {
    stop(sprintf(
      "create_tableone_summary: variable(s) not found in data: %s.",
      paste(missing_vars, collapse = ", ")
    ))
  }

  if (!is.null(strata)) {
    missing_strata <- setdiff(strata, names(data))
    if (length(missing_strata) > 0) {
      stop(sprintf(
        "create_tableone_summary: strata column(s) not found in data: %s.",
        paste(missing_strata, collapse = ", ")
      ))
    }
  }

  tbl <- tableone::CreateTableOne(
    vars       = vars,
    strata     = strata,
    data       = data,
    factorVars = factor_vars,
    includeNA  = include_na,
    smd        = smd
  )

  # print() with printToggle = FALSE returns a character matrix whose rownames
  # are the variable/level labels and whose colnames are the group levels (or
  # "Overall" when unstratified). noSpaces = TRUE removes padding whitespace.
  mat <- print(tbl, printToggle = FALSE, smd = smd, noSpaces = TRUE)

  df <- as.data.frame(mat, stringsAsFactors = FALSE)
  df <- cbind(
    variable     = rownames(df),
    cohort_label = cohort_label,
    df,
    stringsAsFactors = FALSE
  )
  rownames(df) <- NULL

  df
}

# ---------------------------------------------------------------------------
# create_outcome_followup_summary
# ---------------------------------------------------------------------------

#' Summarize outcome event counts and follow-up times by exposure group.
#'
#' @param data          Data frame (clean, typed).
#' @param exposure_var  Name of the binary exposure/group column.
#' @param outcome_vars  Character vector of binary event indicator column names.
#' @param followup_vars Character vector of follow-up time column names,
#'                      matched positionally to outcome_vars.
#' @param cohort_label  Label attached to every output row (default "Overall cohort").
#' @return              A data frame with one row per outcome/group combination,
#'                      containing: cohort_label, group, outcome_var, followup_var,
#'                      n_total, n_events, pct_events, median_followup, q1_followup,
#'                      q3_followup, mean_followup, sd_followup.
create_outcome_followup_summary <- function(data,
                                             exposure_var,
                                             outcome_vars,
                                             followup_vars,
                                             cohort_label = "Overall cohort") {

  if (!exposure_var %in% names(data)) {
    stop(sprintf(
      "create_outcome_followup_summary: exposure column '%s' not found in data.",
      exposure_var
    ))
  }

  if (length(outcome_vars) != length(followup_vars)) {
    stop(
      "create_outcome_followup_summary: outcome_vars and followup_vars must have the same length."
    )
  }

  missing_out <- setdiff(outcome_vars,  names(data))
  missing_fu  <- setdiff(followup_vars, names(data))
  if (length(missing_out) > 0 || length(missing_fu) > 0) {
    stop(sprintf(
      "create_outcome_followup_summary: column(s) not found in data: %s.",
      paste(c(missing_out, missing_fu), collapse = ", ")
    ))
  }

  groups <- sort(unique(as.character(data[[exposure_var]][!is.na(data[[exposure_var]])])))

  rows <- vector("list", length(outcome_vars) * length(groups))
  idx  <- 0L

  for (i in seq_along(outcome_vars)) {
    ov  <- outcome_vars[[i]]
    fv  <- followup_vars[[i]]
    ev  <- data[[ov]]
    fut <- data[[fv]]

    for (grp in groups) {
      idx   <- idx + 1L
      mask  <- !is.na(data[[exposure_var]]) & as.character(data[[exposure_var]]) == grp
      ev_g  <- ev[mask]
      fut_g <- fut[mask]

      n_total  <- length(ev_g)
      n_events <- sum(ev_g == 1L, na.rm = TRUE)
      pct      <- if (n_total > 0) round(100 * n_events / n_total, 2) else NA_real_

      fu_vals  <- fut_g[!is.na(fut_g)]

      rows[[idx]] <- data.frame(
        cohort_label    = cohort_label,
        group           = grp,
        outcome_var     = ov,
        followup_var    = fv,
        n_total         = n_total,
        n_events        = n_events,
        pct_events      = pct,
        median_followup = if (length(fu_vals) > 0) median(fu_vals) else NA_real_,
        q1_followup     = if (length(fu_vals) > 0) quantile(fu_vals, 0.25, names = FALSE) else NA_real_,
        q3_followup     = if (length(fu_vals) > 0) quantile(fu_vals, 0.75, names = FALSE) else NA_real_,
        mean_followup   = if (length(fu_vals) > 0) mean(fu_vals)   else NA_real_,
        sd_followup     = if (length(fu_vals) > 0) sd(fu_vals)     else NA_real_,
        stringsAsFactors = FALSE
      )
    }
  }

  rows <- rows[seq_len(idx)]
  do.call(rbind, rows)
}
