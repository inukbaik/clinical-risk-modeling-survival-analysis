# clean.R
#
# Cleaning for the Study A cohort.
#
# Two decisions are made here rather than left implicit, and both are reported
# rather than absorbed: what happens to the "null" race code, and what happens
# to negative follow-up times.

#' Clean the Study A cohort.
#'
#' @param race_strategy How to handle the literal string "null" in demo_race:
#'   "explicit_level" keeps it as a category named "Missing", so that every
#'     subject stays in the analysis and missingness itself can be a predictor;
#'   "complete_case" drops those subjects.
#'   Neither is obviously right, which is why the choice is an argument rather
#'   than a hard-coded line. Running the analysis both ways is a sensitivity
#'   analysis, not a rewrite.
#'
#' Returns the cleaned data with an "attrition" attribute recording what was
#' removed and why.
clean_study_a <- function(data,
                          race_strategy = c("explicit_level", "complete_case")) {
  race_strategy <- match.arg(race_strategy)
  n_start <- nrow(data)

  # Negative follow-up cannot be correct under any reading. Remove and report.
  bad_time <- data$followup_time_1 < 0 | data$followup_time_2 < 0
  n_bad_time <- sum(bad_time)
  data <- data[!bad_time, , drop = FALSE]

  n_null_race <- sum(data$demo_race == "null")
  if (race_strategy == "complete_case") {
    data <- data[data$demo_race != "null", , drop = FALSE]
    data$demo_race <- factor(data$demo_race, levels = c("Group_A", "Group_B"))
  } else {
    data$demo_race[data$demo_race == "null"] <- "Missing"
    data$demo_race <- factor(data$demo_race,
                             levels = c("Group_A", "Group_B", "Missing"))
  }

  data$exposure_group <- factor(data$exposure_group, levels = STUDY_A_GROUP_LEVELS)
  data$demo_sex <- factor(data$demo_sex, levels = c(0, 1))
  for (v in CLINICAL_BINARY_VARS) {
    data[[v]] <- factor(data[[v]], levels = c(0, 1))
  }

  attr(data, "attrition") <- data.frame(
    step = c("Starting cohort",
             "Removed: negative follow-up time",
             sprintf("Race \"null\" (%s)", race_strategy),
             "Analysis cohort"),
    n = c(n_start, -n_bad_time,
          if (race_strategy == "complete_case") -n_null_race else 0L,
          nrow(data)),
    stringsAsFactors = FALSE
  )
  data
}

#' Restrict to the age subgroup.
#'
#' Subgroup analyses re-run the design inside the subgroup rather than
#' subsetting an analysis built on the full cohort. A propensity score fitted
#' in the whole cohort does not balance the subgroup.
age_subgroup <- function(data, cutoff = STUDY_A_AGE_CUTOFF) {
  out <- data[data$demo_age >= cutoff, , drop = FALSE]
  droplevels(out)
}
