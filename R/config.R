# config.R
#
# Central configuration for the clinical modeling pipeline.
# All variable names, file paths, model specs, and constants are
# defined here. Downstream modules reference these objects rather
# than hard-coding names, making the pipeline easy to adapt.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

PATHS <- list(
  data_raw        = file.path("data", "synthetic", "synthetic_cohort.csv"),
  output_tables   = file.path("outputs", "tables"),
  output_figures  = file.path("outputs", "figures"),
  output_models   = file.path("outputs", "models")
)

# ---------------------------------------------------------------------------
# Column roles
# ---------------------------------------------------------------------------

ID_VAR    <- "record_id"
GROUP_VAR <- "exposure_group"

DEMOGRAPHIC_VARS <- c("demo_age", "demo_sex", "demo_race")

CLINICAL_VARS <- c(
  "clinical_binary_1",
  "clinical_binary_2",
  "clinical_binary_3",
  "clinical_binary_4",
  "clinical_binary_5",
  "clinical_binary_6",
  "clinical_continuous_1"
)

# All baseline predictors available for modeling (demographics + clinical)
BASELINE_PREDICTORS <- c(DEMOGRAPHIC_VARS, CLINICAL_VARS)

# ---------------------------------------------------------------------------
# Outcome specifications
# ---------------------------------------------------------------------------
# Each entry defines one time-to-event endpoint:
#   event_var   : binary event indicator (0/1 integer)
#   time_var    : follow-up time in years
#   label       : human-readable label for tables and figures

OUTCOME_SPECS <- list(
  outcome_1 = list(
    event_var = "outcome_1",
    time_var  = "followup_time_1",
    label     = "Outcome 1"
  ),
  outcome_2 = list(
    event_var = "outcome_2",
    time_var  = "followup_time_2",
    label     = "Outcome 2"
  )
)

# ---------------------------------------------------------------------------
# Cox proportional hazards model specifications
# ---------------------------------------------------------------------------
# covariates: right-hand side terms added to every Cox model.
# Outcome-specific time/event vars are pulled from OUTCOME_SPECS at runtime.

COX_MODEL_SPECS <- list(
  covariates = c(
    GROUP_VAR,
    "demo_age",
    "demo_sex",
    "demo_race",
    "clinical_binary_1",
    "clinical_binary_2",
    "clinical_binary_3",
    "clinical_binary_4",
    "clinical_binary_5",
    "clinical_binary_6",
    "clinical_continuous_1"
  )
)

# ---------------------------------------------------------------------------
# Propensity score matching
# ---------------------------------------------------------------------------
# Variables used on the right-hand side of the PSM logistic model.
# The treatment variable (GROUP_VAR) is always the left-hand side.

PSM_FORMULA_VARS <- c(
  "demo_age",
  "demo_sex",
  "demo_race",
  "clinical_binary_1",
  "clinical_binary_2",
  "clinical_binary_3",
  "clinical_binary_4",
  "clinical_binary_5",
  "clinical_binary_6",
  "clinical_continuous_1"
)

# ---------------------------------------------------------------------------
# Data-leakage exclusion list
# ---------------------------------------------------------------------------
# Variables that must NOT appear as random forest predictors.
# Includes: identifiers, outcome variables, follow-up time variables,
# and any post-baseline variable that would leak information about outcomes.

LEAKAGE_VARS <- c(
  "record_id",
  "outcome_1",
  "outcome_2",
  "followup_time_1",
  "followup_time_2",
  "post_baseline_indicator"
)

# ---------------------------------------------------------------------------
# Reproducibility
# ---------------------------------------------------------------------------

SEED <- 42
