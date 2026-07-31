# simulate.R
#
# Synthetic cohort generation for both studies.
#
# The masking rule: every column carries a generic name and a generic set of
# levels, but the *role* each column plays and the *structure* between columns
# are preserved -- a confounded exposure, correlated comorbidities, a lab value
# on the causal pathway, competing events, and two real data defects.
#
# Survival times come from a Weibull proportional hazards model, so the true
# hazard ratio is a known quantity that every downstream notebook can be
# checked against. Follow-up time is derived from the event and censoring
# times, never drawn first and then used to predict the event.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

#' Draw event times from a Weibull proportional hazards model.
#'
#' With survivor function S(t) = exp(-(t / scale0)^shape * exp(lp)), inverting
#' at U ~ Uniform(0, 1) gives the closed form below. exp(coefficient) is then a
#' hazard ratio in the usual Cox sense.
weibull_ph_time <- function(lp, shape, scale0) {
  u <- stats::runif(length(lp))
  scale0 * (-log(u) * exp(-lp))^(1 / shape)
}

#' Linear predictor from a named coefficient vector.
#'
#' Coefficients are matched to columns by name so that a typo produces an
#' error rather than a silently mis-specified model.
linear_predictor <- function(data, coefs) {
  lp <- numeric(nrow(data))
  for (nm in names(coefs)) {
    term <- switch(
      nm,
      treat               = as.integer(data$.treat),
      demo_age_per_decade = (data$demo_age - 65) / 10,
      demo_sex            = as.integer(as.character(data$demo_sex)),
      clinical_cont_per10 = (data$clinical_continuous_1 - 80) / 10,
      # everything else is a plain binary column
      {
        stopifnot(nm %in% names(data))
        as.integer(as.character(data[[nm]]))
      }
    )
    lp <- lp + coefs[[nm]] * term
  }
  lp
}

# ---------------------------------------------------------------------------
# Shared baseline covariates
# ---------------------------------------------------------------------------

#' Generate the baseline covariate block used by both studies.
#'
#' The six binary clinical variables form a correlated chain rather than being
#' independent draws, and the continuous measure depends on age and on two of
#' the binaries. Independent covariates would make propensity score adjustment
#' trivial and the balance tables uninformative.
simulate_baseline <- function(n) {
  demo_age <- round(pmin(pmax(stats::rnorm(n, mean = 68, sd = 11), 18), 90))
  demo_sex <- stats::rbinom(n, 1, 0.48)

  age_c <- (demo_age - 65) / 10

  cb1 <- stats::rbinom(n, 1, stats::plogis(-1.10 + 0.45 * age_c))
  cb2 <- stats::rbinom(n, 1, stats::plogis(-1.60 + 0.30 * age_c + 0.80 * cb1))
  cb3 <- stats::rbinom(n, 1, stats::plogis(-2.10 + 0.25 * age_c + 0.60 * cb2))
  cb4 <- stats::rbinom(n, 1, stats::plogis(-1.90 + 0.20 * age_c + 0.50 * cb2))
  cb5 <- stats::rbinom(n, 1, stats::plogis(-2.40 + 0.35 * age_c))
  cb6 <- stats::rbinom(n, 1, stats::plogis(-1.70 + 0.15 * age_c + 0.70 * cb5))

  clinical_continuous_1 <- stats::rnorm(
    n,
    mean = 82 - 3.5 * age_c - 9 * cb1 - 4 * cb2,
    sd   = 14
  )
  clinical_continuous_1 <- round(pmin(pmax(clinical_continuous_1, 10), 130), 1)

  # Race is generated independently of everything else and enters no outcome
  # model. Its true effect is exactly zero, which makes it the yardstick for
  # reading random forest importance.
  demo_race <- sample(c("Group_A", "Group_B"), n, replace = TRUE,
                      prob = c(0.55, 0.45))

  data.frame(
    demo_age              = demo_age,
    demo_sex              = demo_sex,
    demo_race             = demo_race,
    clinical_binary_1     = cb1,
    clinical_binary_2     = cb2,
    clinical_binary_3     = cb3,
    clinical_binary_4     = cb4,
    clinical_binary_5     = cb5,
    clinical_binary_6     = cb6,
    clinical_continuous_1 = clinical_continuous_1,
    stringsAsFactors      = FALSE
  )
}

#' Assign exposure from a logistic model on the confounders.
#'
#' The covariates here overlap with those in the outcome models on purpose:
#' that overlap is the confounding, and it is what a propensity score has to
#' undo.
assign_exposure <- function(df, group_levels, coefs = TRUE_PS_COEFS) {
  lp <- coefs[["intercept"]] +
    coefs[["demo_age_per_decade"]]   * (df$demo_age - 65) / 10 +
    coefs[["demo_sex"]]              * df$demo_sex +
    coefs[["clinical_binary_1"]]     * df$clinical_binary_1 +
    coefs[["clinical_binary_2"]]     * df$clinical_binary_2 +
    coefs[["clinical_continuous_1"]] * (df$clinical_continuous_1 - 80)

  treat <- stats::rbinom(nrow(df), 1, stats::plogis(lp))
  df$.treat        <- treat
  df$exposure_group <- factor(group_levels[treat + 1L], levels = group_levels)
  df
}

#' Inject the two data defects carried over from the source data.
#'
#' Neither is decoration. The literal string "null" in a character column is
#' what forces an explicit missingness decision instead of a silent
#' as.numeric() coercion, and negative follow-up times are what the cleaning
#' step actually has to catch.
inject_defects <- function(df, time_vars, null_race_frac = 0.05,
                           negative_time_frac = 0.002) {
  n <- nrow(df)

  idx_null <- sample.int(n, size = round(null_race_frac * n))
  df$demo_race[idx_null] <- "null"

  for (tv in time_vars) {
    idx_neg <- sample.int(n, size = round(negative_time_frac * n))
    df[[tv]][idx_neg] <- -abs(df[[tv]][idx_neg])
  }
  df
}

# ---------------------------------------------------------------------------
# Study A -- propensity score matching, two endpoints
# ---------------------------------------------------------------------------

#' Simulate the Study A cohort.
#'
#' Two endpoints, each with its own Weibull hazard, its own censoring draw, and
#' therefore its own follow-up time -- exactly as in the source analysis, where
#' the two outcomes had separate time variables.
simulate_study_a <- function(n = STUDY_A_N, seed = PROJECT_SEED) {
  set.seed(seed)

  df <- simulate_baseline(n)
  df <- assign_exposure(df, STUDY_A_GROUP_LEVELS)

  for (spec in list(
    list(coefs = TRUE_A_OUTCOME_1, scale0 = 34, cens_rate = 0.055,
         event = "outcome_1", time = "followup_time_1"),
    list(coefs = TRUE_A_OUTCOME_2, scale0 = 42, cens_rate = 0.055,
         event = "outcome_2", time = "followup_time_2")
  )) {
    lp     <- linear_predictor(df, spec$coefs)
    t_evt  <- weibull_ph_time(lp, WEIBULL_SHAPE, spec$scale0)
    t_cens <- stats::rexp(n, rate = spec$cens_rate)
    t_obs  <- pmin(t_evt, t_cens, STUDY_A_ADMIN_YEARS)

    df[[spec$event]] <- as.integer(t_evt <= pmin(t_cens, STUDY_A_ADMIN_YEARS))
    df[[spec$time]]  <- round(t_obs, 4)
  }

  # A post-baseline flag derived from the outcomes. Nothing in the analysis
  # uses it; it exists so that the predictor whitelist has something real to
  # exclude, and so that a reader can see what leakage would look like.
  df$post_baseline_indicator <- as.integer(
    (df$outcome_1 == 1 | df$outcome_2 == 1) &
      stats::rbinom(n, 1, 0.7) == 1
  )

  df <- inject_defects(df, time_vars = c("followup_time_1", "followup_time_2"))

  df$record_id <- sprintf("A%06d", seq_len(n))
  df$.treat    <- NULL

  df[, c("record_id", "exposure_group", BASELINE_PREDICTORS,
         "outcome_1", "followup_time_1", "outcome_2", "followup_time_2",
         "post_baseline_indicator")]
}

# ---------------------------------------------------------------------------
# Study B -- overlap weighting, competing risks
# ---------------------------------------------------------------------------

#' Floor a date to the first of its month.
#'
#' This reproduces a real property of the source extract: death was delivered
#' at month precision, with every day component set to 01, while the event of
#' interest carried true day precision. That asymmetry is what creates
#' same-day ties and makes the tie rule a decision rather than a footnote.
floor_to_month <- function(x) {
  as.Date(format(x, "%Y-%m-01"))
}

#' Simulate the Study B cohort with a genuine competing-risks structure.
#'
#' Two cause-specific hazards are drawn independently; whichever fires first is
#' what is observed. Treatment lowers the event hazard and is near-null on the
#' death hazard, so the cause-specific and subdistribution hazard ratios differ
#' in a direction that is known in advance.
simulate_study_b <- function(n = STUDY_B_N, seed = PROJECT_SEED + 1L) {
  set.seed(seed)

  df <- simulate_baseline(n)
  df <- assign_exposure(df, STUDY_B_GROUP_LEVELS, coefs = TRUE_PS_COEFS_B)

  # A shared gamma frailty multiplies both cause-specific hazards, so that
  # frail subjects are at raised risk of the event AND of death. Drawing the
  # two causes independently would be simpler but wrong: it would scatter
  # events and deaths across different people and different months, and the
  # same-month collisions that the tie rule exists to resolve would never
  # occur. Mean 1 by construction, so marginal hazards are unchanged.
  frailty    <- stats::rgamma(n, shape = 1 / FRAILTY_VARIANCE,
                              rate = 1 / FRAILTY_VARIANCE)
  log_frailty <- log(frailty)

  t_event <- weibull_ph_time(linear_predictor(df, TRUE_B_EVENT) + log_frailty,
                             WEIBULL_SHAPE, scale0 = 27)
  t_death <- weibull_ph_time(linear_predictor(df, TRUE_B_DEATH) + log_frailty,
                             WEIBULL_SHAPE, scale0 = 20)

  # Loss to follow-up, independent of both causes.
  t_ltfu <- stats::rexp(n, rate = 0.04)

  df$baseline_date <- STUDY_B_ENROLMENT_START +
    sample.int(as.integer(STUDY_B_ENROLMENT_END - STUDY_B_ENROLMENT_START),
               n, replace = TRUE)

  as_offset_date <- function(years) df$baseline_date + round(years * DAYS_PER_YEAR)

  event_occurs <- t_event < t_ltfu
  death_occurs <- t_death < t_ltfu

  df$event_date <- as.Date(ifelse(event_occurs, as_offset_date(t_event), NA),
                           origin = "1970-01-01")
  # Death is recorded at month precision only.
  df$death_month_date <- as.Date(
    ifelse(death_occurs, floor_to_month(as_offset_date(t_death)), NA),
    origin = "1970-01-01"
  )
  df$death <- as.integer(death_occurs)

  df$last_fu_date <- as_offset_date(t_ltfu)

  # Retain the true latent ordering so the notebook can quantify how often
  # month-precision rounding disturbs it. This is a simulation-only column and
  # never enters a model.
  df$.true_event_first <- as.integer(event_occurs &
                                       (!death_occurs | t_event <= t_death))

  df$.treat <- NULL
  df$record_id <- sprintf("B%06d", seq_len(n))

  df[, c("record_id", "exposure_group", BASELINE_PREDICTORS,
         "baseline_date", "last_fu_date", "event_date", "death_month_date",
         "death", ".true_event_first")]
}

# ---------------------------------------------------------------------------
# Study B outcome derivation
# ---------------------------------------------------------------------------

#' Classify competing-risk status from dates.
#'
#' Single point of control for the event definition. `tie_rule` selects how an
#' event recorded on the same date as death is handled:
#'   "event_wins"  -- event_date <= death_date, the specification used here
#'   "death_wins"  -- event_date <  death_date, the stricter alternative
#'
#' Returns a factor whose levels are ordered so that finegray() reads level 2
#' as the event of interest and level 3 as the competing event.
derive_cr_status <- function(event_date, death_month_date,
                             tie_rule = c("event_wins", "death_wins")) {
  tie_rule <- match.arg(tie_rule)

  has_event <- !is.na(event_date)
  has_death <- !is.na(death_month_date)

  before <- if (tie_rule == "event_wins") {
    event_date <= death_month_date
  } else {
    event_date < death_month_date
  }

  event_first <- has_event & (!has_death | (!is.na(before) & before))

  factor(
    ifelse(event_first, 1L, ifelse(has_death, 2L, 0L)),
    levels = 0:2,
    labels = c("censored", "event", "death_before_event")
  )
}

#' Derive follow-up time and competing-risk status for Study B.
#'
#' Follow-up is bounded by loss to follow-up, the analysis horizon, and the
#' administrative censoring date, then truncated at whichever event came first.
#' Because the censoring date takes the minimum over both event dates
#' symmetrically, the tie rule cannot change follow-up time -- only the label
#' attached to it.
prepare_outcome_data <- function(df, horizon_years = STUDY_B_HORIZON_YEARS,
                                 tie_rule = "event_wins") {
  horizon_date <- df$baseline_date + round(horizon_years * DAYS_PER_YEAR)

  min_fu <- pmin(df$last_fu_date, horizon_date, STUDY_B_ADMIN_CENSOR)

  # Month-precision rounding can place a death date before the index date when
  # death falls in the index month. A death cannot precede enrolment, so the
  # date is clamped forward. The count is retained as an attribute so the
  # notebook can report how often the rounding bit rather than silently
  # absorbing it.
  death_date <- df$death_month_date
  n_clamped  <- sum(!is.na(death_date) & death_date < df$baseline_date)
  death_date <- pmax(death_date, df$baseline_date)

  # Only events occurring within the follow-up window are observed.
  event_date <- df$event_date
  event_date[!is.na(event_date) & event_date > min_fu] <- NA
  death_date[!is.na(death_date) & death_date > min_fu] <- NA

  cens_date <- pmin(min_fu, event_date, death_date, na.rm = TRUE)

  df$fu_years  <- as.numeric(cens_date - df$baseline_date) / DAYS_PER_YEAR
  df$cr_status <- derive_cr_status(event_date, death_date, tie_rule)
  df$cs_event  <- as.integer(df$cr_status == "event")

  # Fail loudly rather than modelling nonsense.
  stopifnot(
    all(is.finite(df$fu_years)),
    all(df$fu_years >= 0),
    !anyNA(df$cr_status)
  )
  attr(df, "n_death_dates_clamped") <- n_clamped
  df
}
