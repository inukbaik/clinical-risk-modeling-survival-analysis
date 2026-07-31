# config.R
#
# Single source of truth for the synthetic schema and for the true parameter
# values used by the data-generating process.
#
# Every notebook sources this file. Nothing here is re-declared anywhere else:
# if a column name or a true coefficient needs to change, it changes here and
# only here.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# Figures are not written to disk: they are embedded in the rendered notebooks,
# which is where they are meant to be read. Only the result tables are exported,
# so that a number can be checked without re-rendering.
PATHS <- list(
  study_a       = file.path("data", "synthetic", "study_a.rds"),
  study_b       = file.path("data", "synthetic", "study_b.rds"),
  output_tables = file.path("outputs", "tables")
)

# ---------------------------------------------------------------------------
# Column roles (shared by both studies)
# ---------------------------------------------------------------------------

ID_VAR    <- "record_id"
GROUP_VAR <- "exposure_group"

DEMOGRAPHIC_VARS <- c("demo_age", "demo_sex", "demo_race")

CLINICAL_BINARY_VARS <- paste0("clinical_binary_", 1:6)

# The single continuous clinical measure. It stands in for the lab value that,
# in the source analysis, was deliberately entered last in the Cox ladder and
# deliberately excluded from the matching formula -- it sits on the causal
# pathway rather than being a pure confounder.
CLINICAL_CONTINUOUS_VAR <- "clinical_continuous_1"

CLINICAL_VARS <- c(CLINICAL_BINARY_VARS, CLINICAL_CONTINUOUS_VAR)

# Everything measured at or before index date. This whitelist IS the leakage
# control: models are built by selecting from it, never by subtracting a
# blacklist from the full column set.
BASELINE_PREDICTORS <- c(DEMOGRAPHIC_VARS, CLINICAL_VARS)

# Covariates entering the propensity model. The continuous clinical measure is
# excluded on purpose (see above); this is what makes it the covariate that
# fails balance first, which is the point of the caliper notebook.
PS_FORMULA_VARS <- c(DEMOGRAPHIC_VARS, CLINICAL_BINARY_VARS)

# Columns produced by MatchIt that must never reach a predictor set.
MATCHIT_ARTIFACT_VARS <- c("distance", "weights", "subclass")

# ---------------------------------------------------------------------------
# Study A -- propensity score matching, two endpoints
# ---------------------------------------------------------------------------

STUDY_A_GROUP_LEVELS <- c("TreatA", "TreatB")   # TreatA is the reference arm

STUDY_A_OUTCOMES <- list(
  outcome_1 = list(event_var = "outcome_1", time_var = "followup_time_1",
                   label = "Outcome 1"),
  outcome_2 = list(event_var = "outcome_2", time_var = "followup_time_2",
                   label = "Outcome 2")
)

STUDY_A_N            <- 20000L
STUDY_A_ADMIN_YEARS  <- 8
STUDY_A_AGE_CUTOFF   <- 65      # subgroup threshold, applied as >= 65

# ---------------------------------------------------------------------------
# Study B -- overlap weighting, competing risks
# ---------------------------------------------------------------------------

STUDY_B_GROUP_LEVELS <- c("TreatA", "TreatC")   # TreatA is the reference arm

STUDY_B_N             <- 20000L
STUDY_B_HORIZON_YEARS <- 3
STUDY_B_ALT_HORIZONS  <- c(1, 2)
STUDY_B_LANDMARK_DAYS <- 180L
DAYS_PER_YEAR         <- 365.25

STUDY_B_ENROLMENT_START <- as.Date("2015-01-01")
STUDY_B_ENROLMENT_END   <- as.Date("2019-12-31")
STUDY_B_ADMIN_CENSOR    <- as.Date("2022-12-31")

# ---------------------------------------------------------------------------
# True parameter values
# ---------------------------------------------------------------------------
# These are the ground truth of the simulation. Every notebook checks its
# estimates against them, which is what separates this repo from one that
# merely runs models and reports whatever comes out.
#
# demo_race is absent from every outcome linear predictor below. Its true
# effect is exactly zero, and it is the reference point for reading the random
# forest importance rankings.

# Exposure assignment (shared shape across both studies): the same covariates
# drive treatment and outcome, which is what makes confounding real and makes
# balance adjustment necessary rather than decorative.
TRUE_PS_COEFS <- c(
  intercept             = -0.25,
  demo_age_per_decade   =  0.15,
  demo_sex              =  0.25,
  clinical_binary_1     =  0.40,
  clinical_binary_2     =  0.25,
  # Deliberately modest. This covariate is left out of the propensity model, so
  # matching can only balance it through its correlation with the covariates
  # that ARE in the model. A strong direct association would make it
  # unbalanceable at any caliper -- realistic, but it would mean the design
  # simply does not work rather than needing to be tuned.
  clinical_continuous_1 = -0.003   # per unit, centred at 80
)

# Study B uses a stronger exposure model. Channelling is more pronounced in
# that comparison, so propensity scores spread toward both extremes. That
# spread is the reason the choice of weighting scheme matters at all: where the
# scores are all near 0.5, every scheme behaves well and the diagnostics have
# nothing to find.
TRUE_PS_COEFS_B <- c(
  intercept             = -1.40,
  demo_age_per_decade   =  0.55,
  demo_sex              =  0.45,
  clinical_binary_1     =  1.00,
  clinical_binary_2     =  0.70,
  clinical_continuous_1 = -0.015
)

# Study A outcome hazards (Weibull proportional hazards).
TRUE_A_OUTCOME_1 <- c(
  treat               = log(0.75),   # true hazard ratio 0.75
  demo_age_per_decade = 0.35,
  demo_sex            = 0.20,
  clinical_binary_1   = 0.30,
  clinical_binary_2   = 0.25,
  clinical_binary_4   = 0.20,
  clinical_binary_6   = 0.18,
  clinical_cont_per10 = -0.12
)

TRUE_A_OUTCOME_2 <- c(
  treat               = log(0.85),   # true hazard ratio 0.85
  demo_age_per_decade = 0.30,
  demo_sex            = -0.10,
  clinical_binary_1   = 0.15,
  clinical_binary_3   = 0.35,
  clinical_binary_5   = 0.22,
  clinical_cont_per10 = -0.20
)

# Study B cause-specific hazards.
#
# Treatment lowers the hazard of the event of interest and is essentially null
# on the competing death hazard. That asymmetry is deliberate: it is what makes
# the cause-specific and subdistribution hazard ratios differ in a known
# direction, and therefore what makes fitting both worthwhile.
TRUE_B_EVENT <- c(
  treat               = log(0.80),   # true cause-specific hazard ratio 0.80
  demo_age_per_decade = 0.30,
  demo_sex            = 0.15,
  clinical_binary_1   = 0.30,
  clinical_binary_3   = 0.25,
  clinical_cont_per10 = -0.15
)

TRUE_B_DEATH <- c(
  treat               = log(0.98),   # deliberately near-null
  demo_age_per_decade = 0.55,
  demo_sex            = 0.20,
  clinical_binary_5   = 0.35,
  clinical_cont_per10 = -0.25
)

# Weibull shape parameters. shape > 1 gives an increasing baseline hazard.
WEIBULL_SHAPE <- 1.3

# Variance of the gamma frailty shared between the Study B cause-specific
# hazards. Larger values make the event of interest and death cluster more
# tightly in the same subjects and the same calendar months.
FRAILTY_VARIANCE <- 1.5

# ---------------------------------------------------------------------------
# Analysis constants
# ---------------------------------------------------------------------------

SMD_THRESHOLD  <- 0.10          # |SMD| at or below this counts as balanced

# Forest size. 250 is enough for stable permutation importance at this sample
# size and keeps a cold render inside its time budget; nothing in the
# conclusions turns on the exact value.
RF_NUM_TREES   <- 250L
CALIPER_GRID   <- seq(0.30, 0.02, by = -0.02)

# Extreme-weight thresholds, one per weighting method. They differ because the
# weights are on different scales; a single cutoff would be meaningless.
WEIGHT_THRESHOLDS <- list(
  iptw       = 10,              # untruncated inverse-probability weights
  sw_iptw    = 3,               # stabilized weights centre near 1
  overlap_ps = c(0.1, 0.9)      # overlap: flag PS outside this range instead
)

PROJECT_SEED <- 20240730L
