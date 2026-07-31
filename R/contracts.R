# contracts.R
#
# Fail-fast contracts for the analysis pipeline.
#
# The organising idea is that a check belongs at the seam between stages, not
# scattered through the code that does the work. A stage declares what it needs
# from its input and what question it is answering; both are validated once, on
# entry, before any model is fitted. A violation then surfaces where it was
# introduced rather than as a confusing failure three stages later.
#
# Four categories of check exist in this project, and they are not
# interchangeable:
#
#   Contract      Does the data and design support this analysis at all?
#                 -> stop before fitting
#   Postcondition Did the computation do what it claims?
#                 -> stop
#   Calibration   Did the simulation produce what it promised?
#                 -> stop
#   Finding       What did the data say?
#                 -> report, never stop
#
# Only the first three are errors. A finding that comes out the "wrong" way is
# a result, and a pipeline that halts on it destroys the most valuable thing it
# could have produced. This file provides the first category and the last;
# postconditions and calibration checks live next to the code they guard.

# ---------------------------------------------------------------------------
# Layer 1 -- schema at the seam
# ---------------------------------------------------------------------------

#' Assert that a data frame matches a column specification.
#'
#' @param data  the data frame arriving at this stage
#' @param spec  named list of column name -> expected type, one of
#'   "numeric", "integer", "character", "factor", "Date", or "any"
#' @param stage human-readable name of the stage, used in the error message
#'
#' Reports every problem at once rather than stopping at the first, so a
#' malformed handoff is diagnosed in one pass instead of one re-run per column.
require_schema <- function(data, spec, stage) {
  problems <- character(0)

  missing <- setdiff(names(spec), names(data))
  if (length(missing)) {
    problems <- c(problems, sprintf(
      "missing column(s): %s", paste(missing, collapse = ", ")
    ))
  }

  for (nm in intersect(names(spec), names(data))) {
    want <- spec[[nm]]
    if (identical(want, "any")) next

    got <- class(data[[nm]])[1]
    ok <- switch(
      want,
      numeric   = is.numeric(data[[nm]]),
      integer   = is.numeric(data[[nm]]),
      character = is.character(data[[nm]]),
      factor    = is.factor(data[[nm]]),
      Date      = inherits(data[[nm]], "Date"),
      stop(sprintf("Unknown type '%s' in schema for '%s'.", want, nm))
    )
    if (!ok) {
      problems <- c(problems, sprintf(
        "column '%s' should be %s but is %s", nm, want, got
      ))
    }
  }

  if (length(problems)) {
    stop(sprintf(
      "Schema contract failed entering stage '%s':\n  - %s",
      stage, paste(problems, collapse = "\n  - ")
    ), call. = FALSE)
  }
  invisible(data)
}

#' Build a schema specification from the column vectors in config.R.
#'
#' Schemas are derived rather than typed out, so R/config.R remains the single
#' place a column name is written down.
schema_for <- function(stage = c("study_a_clean", "study_a_matched",
                                 "study_b_weighted", "study_b_outcome")) {
  stage <- match.arg(stage)

  baseline <- c(
    stats::setNames(as.list(rep("numeric", 1)), "demo_age"),
    stats::setNames(as.list(rep("factor", 2)), c("demo_sex", "demo_race")),
    stats::setNames(as.list(rep("factor", length(CLINICAL_BINARY_VARS))),
                    CLINICAL_BINARY_VARS),
    stats::setNames(list("numeric"), CLINICAL_CONTINUOUS_VAR)
  )
  core <- c(
    stats::setNames(list("character"), ID_VAR),
    stats::setNames(list("factor"), GROUP_VAR),
    baseline
  )

  # Outcome and time column names come from STUDY_A_OUTCOMES rather than being
  # written out again here.
  outcome_cols <- unlist(lapply(STUDY_A_OUTCOMES,
                                function(s) c(s$event_var, s$time_var)),
                         use.names = FALSE)
  outcomes <- stats::setNames(
    as.list(rep("numeric", length(outcome_cols))), outcome_cols
  )

  switch(
    stage,
    study_a_clean   = c(core, outcomes),
    study_a_matched = c(core, outcomes, list(
      subclass = "any", weights = "numeric", distance = "numeric"
    )),
    study_b_weighted = c(core, list(
      ps = "numeric", overlap_w = "numeric", iptw = "numeric",
      sw_iptw = "numeric", baseline_date = "Date", last_fu_date = "Date"
    )),
    study_b_outcome = c(core, list(
      fu_years = "numeric", cr_status = "factor", cs_event = "numeric",
      overlap_w = "numeric"
    ))
  )
}

#' Load a file produced by an earlier notebook, or explain how to make it.
#'
#' A bare readRDS() on a missing handoff file fails inside gzfile() with
#' "cannot open the connection", which says nothing about what to run. This
#' says it.
require_stage_input <- function(path, produced_by) {
  if (!file.exists(path)) {
    stop(sprintf(
      paste0("Required input '%s' is missing.\n",
             "  It is produced by: %s\n",
             "  Render that notebook first, or run `quarto render` to build ",
             "the whole site in order."),
      path, produced_by
    ), call. = FALSE)
  }
  readRDS(path)
}

# ---------------------------------------------------------------------------
# Layer 2 -- the estimand contract
# ---------------------------------------------------------------------------

#' Declare what question an analysis answers and what it needs to answer it.
#'
#' The point of writing this down in code rather than prose is that the
#' `requires` field is executable. An analysis that names "balance" as a
#' precondition cannot proceed to fit a model in a cohort that never achieved
#' it -- which is otherwise an easy thing to publish by accident, because an
#' unbalanced cohort still produces a clean-looking hazard ratio.
#'
#' @param question   the question as the physician posed it
#' @param estimand   the quantity that answers it
#' @param population who the answer applies to
#' @param estimator  how it is computed
#' @param causal     may the output be read as a treatment effect?
#' @param requires   names of gates to run: "balance", "positivity", "events",
#'                   "no_leakage", "competing_risk"
analysis_contract <- function(question, estimand, population, estimator,
                              causal = TRUE, requires = character(0)) {
  known <- c("balance", "positivity", "events", "no_leakage", "competing_risk")
  unknown <- setdiff(requires, known)
  if (length(unknown)) {
    stop(sprintf("Unknown requirement(s): %s. Known gates: %s.",
                 paste(unknown, collapse = ", "),
                 paste(known, collapse = ", ")), call. = FALSE)
  }

  structure(
    list(question = question, estimand = estimand, population = population,
         estimator = estimator, causal = causal, requires = requires),
    class = "analysis_contract"
  )
}

# --- gates -----------------------------------------------------------------
# Each returns list(ok, detail). They are deliberately small and reuse what
# already exists rather than reimplementing it.

gate_balance <- function(balance, threshold = SMD_THRESHOLD) {
  worst <- balance[which.max(balance$abs_smd), ]
  list(
    ok = worst$abs_smd <= threshold,
    detail = sprintf("largest |SMD| %.4f on %s (threshold %.2f)",
                     worst$abs_smd, worst$covariate, threshold)
  )
}

gate_positivity <- function(ps, treat, bounds = c(0.05, 0.95)) {
  inside <- ps > bounds[1] & ps < bounds[2]
  both_arms <- length(unique(treat[inside])) == 2
  pct <- 100 * mean(inside)
  list(
    ok = both_arms && pct >= 90,
    detail = sprintf("%.1f%% of subjects with PS in [%.2f, %.2f]; both arms present: %s",
                     pct, bounds[1], bounds[2], both_arms)
  )
}

#' Events per covariate.
#'
#' The classic way to get a confidently wrong hazard ratio is to fit more
#' parameters than the events can support. Ten events per covariate is the
#' conventional floor.
gate_events <- function(n_events, n_covariates, min_epv = 10) {
  epv <- n_events / max(n_covariates, 1)
  list(
    ok = epv >= min_epv,
    detail = sprintf("%d events / %d covariates = %.1f per covariate (floor %d)",
                     n_events, n_covariates, epv, min_epv)
  )
}

gate_no_leakage <- function(predictors, forbidden) {
  hits <- intersect(predictors, forbidden)
  list(
    ok = length(hits) == 0,
    detail = if (length(hits)) {
      sprintf("post-baseline or identifier column(s) in predictor set: %s",
              paste(hits, collapse = ", "))
    } else {
      sprintf("%d predictors, none post-baseline", length(predictors))
    }
  )
}

gate_competing_risk <- function(status) {
  lv <- levels(status)
  n_competing <- sum(status == "death_before_event")
  list(
    ok = "death_before_event" %in% lv && n_competing > 0,
    detail = sprintf("competing events observed: %d (%.1f%% of cohort)",
                     n_competing, 100 * n_competing / length(status))
  )
}

#' The set of columns that may never be used as a baseline predictor.
forbidden_predictors <- function() {
  c(ID_VAR, "outcome_1", "outcome_2", "followup_time_1", "followup_time_2",
    "post_baseline_indicator", "death", "fu_years", "cr_status", "cs_event",
    "event_date", "death_month_date", "last_fu_date",
    MATCHIT_ARTIFACT_VARS)
}

#' Run a contract's gates and stop if any fail.
#'
#' @param contract an analysis_contract
#' @param evidence named list supplying what the gates need, e.g.
#'   list(balance = <balance table>, ps = , treat = , n_events = ,
#'        n_covariates = , predictors = , status = )
#'
#' Returns the status table invisibly so a notebook can render it.
validate_contract <- function(contract, evidence) {
  stopifnot(inherits(contract, "analysis_contract"))

  run <- function(req) {
    need <- function(...) {
      missing <- setdiff(c(...), names(evidence))
      if (length(missing)) {
        stop(sprintf("Gate '%s' needs evidence: %s.",
                     req, paste(missing, collapse = ", ")), call. = FALSE)
      }
    }
    switch(
      req,
      balance        = { need("balance"); gate_balance(evidence$balance) },
      positivity     = { need("ps", "treat"); gate_positivity(evidence$ps, evidence$treat) },
      events         = { need("n_events", "n_covariates")
                         gate_events(evidence$n_events, evidence$n_covariates) },
      no_leakage     = { need("predictors")
                         gate_no_leakage(evidence$predictors, forbidden_predictors()) },
      competing_risk = { need("status"); gate_competing_risk(evidence$status) }
    )
  }

  results <- lapply(contract$requires, run)
  status <- data.frame(
    requirement = contract$requires,
    status = vapply(results, function(r) if (r$ok) "pass" else "FAIL", character(1)),
    detail = vapply(results, function(r) r$detail, character(1)),
    stringsAsFactors = FALSE
  )

  failed <- status[status$status == "FAIL", ]
  if (nrow(failed)) {
    stop(sprintf(
      paste0("This analysis cannot answer the question it declares.\n",
             "  Question: %s\n",
             "  Estimand: %s\n",
             "  Unmet requirement(s):\n    - %s\n",
             "Fix the design before fitting. An unmet precondition does not ",
             "stop a model from producing a number; it stops that number ",
             "from meaning what the question asks."),
      contract$question, contract$estimand,
      paste(sprintf("%s: %s", failed$requirement, failed$detail),
            collapse = "\n    - ")
    ), call. = FALSE)
  }

  invisible(status)
}

#' Render a contract and its gate results as markdown.
#'
#' Called for its side effect inside a chunk with `results: asis`.
contract_block <- function(contract, status = NULL) {
  cat("::: {.callout-note appearance=\"minimal\"}\n")
  cat("## Analysis contract\n\n")
  cat(sprintf("**Question (as posed).** %s\n\n", contract$question))
  cat(sprintf("**Estimand.** %s\n\n", contract$estimand))
  cat(sprintf("**Population.** %s\n\n", contract$population))
  cat(sprintf("**Estimator.** %s\n\n", contract$estimator))
  cat(":::\n\n")

  if (!is.null(status) && nrow(status)) {
    cat("Preconditions, checked once before anything is fitted:\n\n")
    print(knitr::kable(status, row.names = FALSE,
                       col.names = c("Requirement", "Status", "Detail")))
    cat("\n\n")
  }

  if (!isTRUE(contract$causal)) {
    cat("::: {.callout-warning}\n")
    cat("## This analysis does not estimate a treatment effect\n\n")
    cat("The output below is a **predictive** ranking. It carries no sign, no ",
        "confidence interval, and no causal interpretation, and it is not ",
        "invariant to the other variables in the model. A variable ranking ",
        "highly has not been shown to cause anything.\n\n", sep = "")
    cat("The treatment effect for these data is estimated in ",
        "[the Cox models](02-cox-models.qmd).\n", sep = "")
    cat(":::\n\n")
  }
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Layer 3 -- findings are reported, never asserted
# ---------------------------------------------------------------------------

#' Compare a set of estimates against a reference and report agreement.
#'
#' Deliberately has no failure mode. Whether sensitivity analyses agree with
#' the primary estimate is a property of the data, not of the code, and a
#' disagreement is the most informative thing this pipeline can surface. Making
#' it fatal would mean the one result worth investigating is the one that
#' prevents the report from being produced.
#'
#' @return a data frame with an agreement column, invisibly; renders a callout
report_agreement <- function(estimates, labels, reference, null_value = 1) {
  same_side <- (estimates < null_value) == (reference < null_value)

  out <- data.frame(
    analysis = labels,
    estimate = round(estimates, 3),
    side = ifelse(estimates < null_value, "below null", "at or above null"),
    agrees_with_primary = same_side,
    stringsAsFactors = FALSE
  )

  n_diverge <- sum(!same_side)
  if (n_diverge == 0) {
    cat("::: {.callout-tip}\n")
    cat("## All sensitivity analyses agree in direction\n\n")
    cat(sprintf(
      paste0("Every one of the %d analyses falls on the same side of the null ",
             "as the primary estimate. Consistency across horizons, weighting ",
             "schemes and confounding-control strategies is what makes the ",
             "primary estimate worth reporting.\n"),
      length(estimates)))
    cat(":::\n\n")
  } else {
    cat("::: {.callout-important}\n")
    cat("## A sensitivity analysis diverges from the primary estimate\n\n")
    cat(sprintf(
      paste0("%d of %d analyses fall on the opposite side of the null. This is ",
             "reported rather than treated as an error: it is a finding about ",
             "the data, and it is the part of this analysis most worth ",
             "investigating. The primary estimate should not be reported ",
             "without addressing it.\n"),
      n_diverge, length(estimates)))
    cat(":::\n\n")
  }

  invisible(out)
}
