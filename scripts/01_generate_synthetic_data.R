# Generate fully synthetic, public-safe cohort data
#
# This script intentionally uses generalized variable names.
# No real patient data, institutional data, protected health
# information, unpublished results, or study-specific variable
# names are included.
#
# Run from the repository root:
#   Rscript scripts/01_generate_synthetic_data.R

set.seed(123)

# -----------------------------
# Project paths
# -----------------------------

output_dir  <- "data/synthetic"
output_file <- file.path(output_dir, "synthetic_cohort.csv")

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# -----------------------------
# Cohort size
# -----------------------------

n <- 150000

# -----------------------------
# Synthetic baseline demographics
# -----------------------------

record_id <- seq_len(n)

demo_age <- round(
  pmin(pmax(rnorm(n, mean = 68, sd = 11), 18), 90)
)

demo_sex <- rbinom(n, size = 1, prob = 0.48)

demo_race <- sample(
  x       = c("Group_A", "Group_B", "Missing"),
  size    = n,
  replace = TRUE,
  prob    = c(0.50, 0.45, 0.05)
)

# -----------------------------
# Synthetic baseline clinical predictors
# -----------------------------
# clinical_binary_*      : synthetic binary baseline clinical predictors
# clinical_continuous_1  : synthetic continuous baseline clinical predictor

clinical_binary_1 <- rbinom(
  n,
  size = 1,
  prob = plogis(-2.4 + 0.025 * (demo_age - 65))
)

clinical_binary_2 <- rbinom(
  n,
  size = 1,
  prob = plogis(-1.2 + 0.020 * (demo_age - 65) + 0.30 * clinical_binary_1)
)

clinical_binary_3 <- rbinom(
  n,
  size = 1,
  prob = plogis(-1.5 + 0.018 * (demo_age - 65) + 0.25 * clinical_binary_2)
)

clinical_binary_4 <- rbinom(
  n,
  size = 1,
  prob = plogis(-1.7 + 0.022 * (demo_age - 65) + 0.35 * clinical_binary_2)
)

clinical_binary_5 <- rbinom(
  n,
  size = 1,
  prob = plogis(-1.0 + 0.010 * (demo_age - 65))
)

clinical_binary_6 <- rbinom(
  n,
  size = 1,
  prob = plogis(-2.0 + 0.012 * (demo_age - 65) + 0.15 * clinical_binary_5)
)

clinical_continuous_1 <- round(
  pmin(
    pmax(
      rnorm(
        n,
        mean = 82 -
          0.35 * (demo_age - 65) -
          9  * clinical_binary_1 -
          4  * clinical_binary_2,
        sd = 14
      ),
      10
    ),
    130
  ),
  1
)

# -----------------------------
# Synthetic exposure assignment
# -----------------------------
# exposure_group represents a binary treatment/exposure group.
# Exposure assignment is intentionally associated with baseline
# features to create confounding for PSM / adjusted modeling.

exposure_probability <- plogis(
  -0.25 +
    0.015 * (demo_age - 65) +
    0.25  * demo_sex +                      # fixed: was demo_binary_1
    0.40  * clinical_binary_1 +
    0.25  * clinical_binary_2 -
    0.015 * (clinical_continuous_1 - 80)
)

exposure_group <- ifelse(
  rbinom(n, size = 1, prob = exposure_probability) == 1,
  "Exposure_B",
  "Exposure_A"
)

exposure_group <- factor(exposure_group, levels = c("Exposure_A", "Exposure_B"))

# -----------------------------
# Synthetic follow-up times
# -----------------------------
# followup_time_1 and followup_time_2 are synthetic time-to-event
# follow-up variables used in Cox proportional hazards models.

followup_time_1 <- round(pmax(rexp(n, rate = 0.22), 0.05), 2)
followup_time_2 <- round(pmax(rexp(n, rate = 0.18), 0.05), 2)

followup_time_1 <- pmin(followup_time_1, 8)
followup_time_2 <- pmin(followup_time_2, 8)

# -----------------------------
# Synthetic outcomes
# -----------------------------
# outcome_1 and outcome_2 are binary event indicators.
# They are generated from baseline predictors, exposure group,
# and follow-up time to preserve realistic modeling structure.

linear_predictor_outcome_1 <- -5.1 +
  0.035 * (demo_age - 65) +
  0.20  * demo_sex +                        # fixed: was demo_binary_1
  0.30  * clinical_binary_1 +
  0.25  * clinical_binary_2 +
  0.20  * clinical_binary_4 +
  0.18  * clinical_binary_6 -
  0.10  * (exposure_group == "Exposure_B") +
  0.18  * followup_time_1

prob_outcome_1 <- plogis(linear_predictor_outcome_1)
outcome_1      <- rbinom(n, size = 1, prob = prob_outcome_1)

linear_predictor_outcome_2 <- -5.6 +
  0.025 * (demo_age - 65) +
  0.55  * clinical_binary_1 +
  0.20  * clinical_binary_2 +
  0.25  * clinical_binary_3 -
  0.035 * (clinical_continuous_1 - 80) -
  0.12  * (exposure_group == "Exposure_B") +
  0.22  * followup_time_2

prob_outcome_2 <- plogis(linear_predictor_outcome_2)
outcome_2      <- rbinom(n, size = 1, prob = prob_outcome_2)

# -----------------------------
# Synthetic post-baseline indicator
# -----------------------------
# This variable is intentionally generated after baseline and should
# be excluded from random forest predictors to demonstrate leakage
# prevention.

post_baseline_indicator <- rbinom(
  n,
  size = 1,
  prob = plogis(
    -3.0 +
      0.03 * (demo_age - 65) +
      0.50 * outcome_1 +
      0.60 * outcome_2 +
      0.30 * clinical_binary_1
  )
)

# -----------------------------
# Assemble synthetic cohort
# -----------------------------

synthetic_cohort <- data.frame(
  record_id   = record_id,

  demo_age    = demo_age,
  demo_sex    = demo_sex,             # fixed: was demo_binary_1 = demo_binary_1
  demo_race   = demo_race,            # fixed: was demo_group_1  = demo_group_1

  clinical_binary_1    = clinical_binary_1,
  clinical_binary_2    = clinical_binary_2,
  clinical_binary_3    = clinical_binary_3,
  clinical_binary_4    = clinical_binary_4,
  clinical_binary_5    = clinical_binary_5,
  clinical_binary_6    = clinical_binary_6,
  clinical_continuous_1 = clinical_continuous_1,

  exposure_group = exposure_group,

  outcome_1 = outcome_1,
  outcome_2 = outcome_2,

  followup_time_1 = followup_time_1,
  followup_time_2 = followup_time_2,

  post_baseline_indicator = post_baseline_indicator
)

# -----------------------------
# Save
# -----------------------------

write.csv(synthetic_cohort, output_file, row.names = FALSE)

cat("Synthetic cohort generated successfully.\n")
cat("Rows:    ", nrow(synthetic_cohort), "\n")
cat("Columns: ", ncol(synthetic_cohort), "\n")
cat("Saved to:", output_file, "\n")
cat("\nExposure group distribution:\n")
print(table(synthetic_cohort$exposure_group))
cat("\nOutcome counts:\n")
print(table(synthetic_cohort$outcome_1))
print(table(synthetic_cohort$outcome_2))
