# propensity_matching.R
#
# PSM functions for the clinical modeling pipeline.
# No file I/O or hard-coded paths. All functions are independently callable.

# ---------------------------------------------------------------------------
# run_propensity_matching
# ---------------------------------------------------------------------------
# Attempts nearest-neighbor PSM across a descending sequence of calipers
# (in propensity score SD units). Returns on the first (largest) caliper
# where every baseline covariate has absolute SMD < smd_threshold.
# Fails fast with a descriptive error if no caliper passes.
#
# Returns a list with:
#   matched_data — data.frame from MatchIt::match.data()
#   matchit_obj  — fitted matchit object
#   selected     — attempt record for the selected caliper
#   attempt_log  — list of attempt records for every caliper tried

run_propensity_matching <- function(
  data,
  treatment_var,
  formula_vars,
  calipers      = seq(0.20, 0.01, by = -0.01),
  smd_threshold = 0.10
) {

  if (!treatment_var %in% names(data)) {
    stop(sprintf(
      "run_propensity_matching: treatment variable '%s' not found in data.",
      treatment_var
    ))
  }

  missing_vars <- setdiff(formula_vars, names(data))
  if (length(missing_vars) > 0) {
    stop(sprintf(
      "run_propensity_matching: formula variable(s) not found in data: %s.",
      paste(missing_vars, collapse = ", ")
    ))
  }

  psm_formula <- stats::as.formula(paste(
    treatment_var, "~", paste(formula_vars, collapse = " + ")
  ))

  attempt_log <- list()

  for (cal in calipers) {

    m_out <- tryCatch(
      MatchIt::matchit(
        formula     = psm_formula,
        data        = data,
        method      = "nearest",
        ratio       = 1,
        caliper     = cal,
        std.caliper = TRUE
      ),
      error = function(e) NULL
    )

    if (is.null(m_out)) {
      attempt_log[[length(attempt_log) + 1]] <- list(
        caliper         = cal,
        max_smd         = NA_real_,
        matched_n       = 0L,
        retention_rate  = NA_real_,
        imbalanced_vars = character(0),
        pass            = FALSE
      )
      next
    }

    matched_data <- MatchIt::match.data(m_out)
    matched_n    <- nrow(matched_data)
    retention    <- matched_n / nrow(data)

    # Extract post-matching SMDs; exclude 'distance' row (propensity score itself)
    sum_matched <- summary(m_out, standardize = TRUE)$sum.matched
    cov_rows    <- rownames(sum_matched)[rownames(sum_matched) != "distance"]
    smd_col     <- grep("Std\\..*Mean.*Diff|Std.*Mean.*Diff", colnames(sum_matched), value = TRUE)[1]
    smd_vals    <- abs(sum_matched[cov_rows, smd_col])
    max_smd     <- max(smd_vals, na.rm = TRUE)
    imbal_vars  <- names(smd_vals[smd_vals >= smd_threshold])

    attempt <- list(
      caliper         = cal,
      max_smd         = max_smd,
      matched_n       = matched_n,
      retention_rate  = retention,
      imbalanced_vars = imbal_vars,
      pass            = (max_smd < smd_threshold)
    )
    attempt_log[[length(attempt_log) + 1]] <- attempt

    cat(sprintf(
      "  caliper = %.2f | max SMD = %.4f | n = %d | retention = %.1f%% | imbalanced: %s\n",
      cal, max_smd, matched_n, retention * 100,
      if (length(imbal_vars) == 0L) "none" else paste(imbal_vars, collapse = ", ")
    ))

    if (attempt$pass) {
      return(list(
        matched_data = matched_data,
        matchit_obj  = m_out,
        selected     = attempt,
        attempt_log  = attempt_log
      ))
    }
  }

  # No caliper passed — report best result and fail
  valid_attempts <- Filter(function(a) !is.na(a$max_smd), attempt_log)

  if (length(valid_attempts) == 0L) {
    stop("PSM fail-fast: all caliper attempts failed to produce matched data.")
  }

  best <- valid_attempts[[which.min(sapply(valid_attempts, `[[`, "max_smd"))]]

  stop(sprintf(
    paste(
      "PSM fail-fast: no caliper in [%.2f, %.2f] achieved max covariate SMD < %.2f.",
      "Best result: caliper = %.2f, max SMD = %.4f.",
      "Remaining imbalanced variables: %s."
    ),
    max(calipers), min(calipers), smd_threshold,
    best$caliper, best$max_smd,
    paste(best$imbalanced_vars, collapse = ", ")
  ))
}

# ---------------------------------------------------------------------------
# extract_psm_balance
# ---------------------------------------------------------------------------
# Extracts per-variable pre- and post-matching SMD from a fitted matchit
# object. Returns a data.frame with columns: variable, smd_before, smd_after.

extract_psm_balance <- function(matchit_obj) {
  s       <- summary(matchit_obj, standardize = TRUE)
  smd_col <- grep("Std\\..*Mean.*Diff|Std.*Mean.*Diff", colnames(s$sum.all), value = TRUE)[1]

  all_rows   <- rownames(s$sum.all)[rownames(s$sum.all) != "distance"]
  smd_before <- abs(s$sum.all[all_rows, smd_col])
  smd_after  <- abs(s$sum.matched[all_rows, smd_col])

  data.frame(
    variable   = all_rows,
    smd_before = round(smd_before, 4),
    smd_after  = round(smd_after,  4),
    row.names  = NULL,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# build_attempt_log_df
# ---------------------------------------------------------------------------
# Converts the attempt log list into a data.frame suitable for CSV export.

build_attempt_log_df <- function(attempt_log) {
  rows <- lapply(attempt_log, function(a) {
    data.frame(
      caliper         = a$caliper,
      max_smd         = round(a$max_smd, 4),
      matched_n       = a$matched_n,
      retention_rate  = round(a$retention_rate, 4),
      imbalanced_vars = paste(a$imbalanced_vars, collapse = "; "),
      pass            = a$pass,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}
