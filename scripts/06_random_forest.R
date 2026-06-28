# Fit random forest models for feature importance on the cleaned cohort.
#
# Models are fit for two outcomes on the overall cleaned cohort.
# The goal is to identify important baseline predictors of each outcome,
# not to estimate a treatment effect. This uses the unmatched cleaned data.
#
# Two-phase fitting strategy:
#   Phase 1 — caret CV on a stratified tuning subset (TUNING_MAX_N rows) to
#              select hyperparameters cheaply.
#   Phase 2 — final ranger model (500 trees, permutation importance) fit on
#              the full SMOTE'd training data using the best params from Phase 1.
#
# Run from the repository root:
#   Rscript scripts/06_random_forest.R

source("R/config.R")
source("R/data_cleaning.R")
source("R/validation.R")
source("R/random_forest.R")

# ---------------------------------------------------------------------------
# Runtime configuration
# ---------------------------------------------------------------------------

# Set RF_DEV_MODE = TRUE to run only the first outcome for quick testing.
RF_DEV_MODE <- FALSE

# Set USE_TUNING_SUBSET = TRUE to run caret CV on a small stratified subset,
# then refit the final model on the full training data. Recommended for large
# cohorts to reduce runtime without sacrificing final model quality.
USE_TUNING_SUBSET   <- TRUE
TUNING_MAX_N        <- 10000L

RF_SEED             <- 123L
RF_SMOTE_OVER_RATIO <- 0.5
TUNE_NUM_TREES      <- 100L   # trees used during caret CV tuning phase only
FINAL_NUM_TREES     <- 500L   # trees used for the final ranger model

# ---------------------------------------------------------------------------
# Package checks
# ---------------------------------------------------------------------------

required_pkgs <- c("caret", "ranger", "recipes", "themis", "pROC",
                   "ggplot2", "tidyselect")

for (pkg in required_pkgs) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(
      sprintf("Package '%s' is required but is not installed.\n", pkg),
      sprintf("Install it with: install.packages(\"%s\")", pkg)
    )
  }
}

# ---------------------------------------------------------------------------
# Parallel backend (optional — speeds up caret CV folds)
# ---------------------------------------------------------------------------

if (requireNamespace("doParallel", quietly = TRUE)) {
  n_cores <- max(1L, parallel::detectCores() - 1L)
  doParallel::registerDoParallel(cores = n_cores)
  cat(sprintf("Parallel backend registered: %d cores\n\n", n_cores))
} else {
  cat("doParallel not installed — running single-threaded.\n")
  cat("Install with: install.packages(\"doParallel\")\n\n")
}

if (RF_DEV_MODE) {
  cat("*** DEV MODE: running first outcome only ***\n\n")
}

# ---------------------------------------------------------------------------
# Input check
# ---------------------------------------------------------------------------

cleaned_path <- file.path("data", "synthetic", "synthetic_cohort_clean.rds")

if (!file.exists(cleaned_path)) {
  stop(
    "Cleaned data file not found: ", cleaned_path, "\n",
    "Run scripts/02_clean_data.R first."
  )
}

# ---------------------------------------------------------------------------
# Load cleaned data
# ---------------------------------------------------------------------------

df_clean <- readRDS(cleaned_path)

cat("Cleaned data loaded.\n")
cat("  Rows:    ", nrow(df_clean), "\n")
cat("  Columns: ", ncol(df_clean), "\n\n")

# ---------------------------------------------------------------------------
# Build predictor set
# ---------------------------------------------------------------------------

predictors <- build_rf_predictor_set(
  data                = df_clean,
  group_var           = GROUP_VAR,
  baseline_predictors = BASELINE_PREDICTORS,
  leakage_vars        = LEAKAGE_VARS
)

cat("RF predictor set (", length(predictors), " features):\n", sep = "")
cat("  ", paste(predictors, collapse = ", "), "\n\n")

# ---------------------------------------------------------------------------
# Cohort definitions
# ---------------------------------------------------------------------------

df_age65 <- create_age_subcohort(df_clean, age_cutoff = 65)

cat(sprintf("Age 65+ subcohort: %d rows (%.1f%% of full cohort)\n\n",
            nrow(df_age65), nrow(df_age65) / nrow(df_clean) * 100))

cohort_list <- list(
  list(slug = "overall", label = "Overall cleaned cohort",  data = df_clean),
  list(slug = "age65",   label = "Age 65+ cleaned cohort", data = df_age65)
)

# ---------------------------------------------------------------------------
# Outcome specifications
# ---------------------------------------------------------------------------

outcome_specs <- list(
  list(slug = "outcome_1", event_var = "outcome_1", label = "Outcome 1"),
  list(slug = "outcome_2", event_var = "outcome_2", label = "Outcome 2")
)

# ---------------------------------------------------------------------------
# RF configuration
# ---------------------------------------------------------------------------

tune_grid <- expand.grid(
  mtry          = c(2, 3, 4, 5, 6),
  splitrule     = "gini",
  min.node.size = c(5, 10, 20, 30)
)

ctrl <- caret::trainControl(
  method          = "cv",
  number          = 5,
  classProbs      = TRUE,
  summaryFunction = caret::twoClassSummary,
  savePredictions = "final"
)

# ---------------------------------------------------------------------------
# Ensure output directories exist
# ---------------------------------------------------------------------------

for (d in c(PATHS$output_tables, PATHS$output_figures, PATHS$output_models)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# ---------------------------------------------------------------------------
# Fit models
# ---------------------------------------------------------------------------

all_models   <- list()
auc_rows     <- list()
skipped_msgs <- character(0)
fit_count    <- 0L

for (cohort in cohort_list) {

  cat(sprintf("\n=== Cohort: %s ===\n", cohort$label))
  cat(sprintf("    Rows: %d\n", nrow(cohort$data)))

  for (oc in outcome_specs) {

    run_label <- sprintf("[%s | %s]", cohort$label, oc$label)

    cat(sprintf("\n  Outcome: %s\n", oc$label))

    # --- Validation (on raw integer outcome) --------------------------------

    skip_msg <- tryCatch({
      validate_binary_outcome(cohort$data, oc$event_var)
      validate_min_events(cohort$data, oc$event_var, min_events = 10L)
      validate_predictor_columns(cohort$data, predictors)
      validate_no_leakage_predictors(predictors, LEAKAGE_VARS)
      validate_factor_levels(cohort$data, predictors)
      NULL
    }, error = function(e) conditionMessage(e))

    if (!is.null(skip_msg)) {
      msg <- sprintf("  SKIP %s\n    Reason: %s", run_label, skip_msg)
      cat(msg, "\n")
      skipped_msgs <- c(skipped_msgs, msg)
      next
    }

    n_events <- sum(cohort$data[[oc$event_var]] == 1L)
    n_total  <- nrow(cohort$data)
    cat(sprintf("    Events: %d / %d (%.1f%%)\n",
                n_events, n_total, n_events / n_total * 100))

    # --- Prepare outcome and split ------------------------------------------

    cohort_factored <- prepare_rf_outcome(cohort$data, oc$event_var)
    split           <- split_rf_data(cohort_factored, oc$event_var,
                                     train_frac = 0.80, seed = RF_SEED)

    n_train        <- nrow(split$train)
    n_train_events <- sum(split$train[[oc$event_var]] == "Event")

    cat(sprintf("    Full train n: %d  |  events: %d (%.1f%%)\n",
                n_train, n_train_events, n_train_events / n_train * 100))
    cat(sprintf("    Test n:       %d\n", nrow(split$test)))

    # --- Tuning subset ------------------------------------------------------

    tune_data <- NULL
    if (USE_TUNING_SUBSET && n_train > TUNING_MAX_N) {
      tune_data     <- create_tuning_subset(split$train, oc$event_var,
                                            max_n = TUNING_MAX_N,
                                            seed  = RF_SEED)
      n_tune        <- nrow(tune_data)
      n_tune_events <- sum(tune_data[[oc$event_var]] == "Event")
      cat(sprintf("    Tuning subset n: %d  |  events: %d (%.1f%%)  [CV tuning only]\n",
                  n_tune, n_tune_events, n_tune_events / n_tune * 100))
    } else {
      cat(sprintf("    Tuning subset: using full training data\n"))
    }

    # --- Fit model ----------------------------------------------------------

    fit_result <- tryCatch(
      fit_rf_model(
        train_data      = split$train,
        outcome_var     = oc$event_var,
        predictors      = predictors,
        tune_grid       = tune_grid,
        ctrl            = ctrl,
        seed            = RF_SEED,
        over_ratio      = RF_SMOTE_OVER_RATIO,
        tune_data       = tune_data,
        tune_num_trees  = TUNE_NUM_TREES,
        final_num_trees = FINAL_NUM_TREES
      ),
      error = function(e) list(.error = conditionMessage(e))
    )

    if (!is.null(fit_result$.error)) {
      msg <- sprintf("  SKIP %s\n    Reason: fit_rf_model() failed: %s",
                     run_label, fit_result$.error)
      cat(msg, "\n")
      skipped_msgs <- c(skipped_msgs, msg)
      next
    }

    best_params <- fit_result$best_params
    cat(sprintf("    Best tune: mtry=%d, splitrule=%s, min.node.size=%d\n",
                best_params$mtry, best_params$splitrule, best_params$min.node.size))

    # --- Evaluate on held-out test set -------------------------------------

    eval_result <- tryCatch(
      evaluate_rf_model(fit_result, split$test, oc$event_var, predictors),
      error = function(e) list(.error = conditionMessage(e))
    )

    if (!is.null(eval_result$.error)) {
      msg <- sprintf("  SKIP %s\n    Reason: evaluate_rf_model() failed: %s",
                     run_label, eval_result$.error)
      cat(msg, "\n")
      skipped_msgs <- c(skipped_msgs, msg)
      next
    }

    cat(sprintf("    Test AUC: %.4f\n", eval_result$auc))

    # --- Feature importance -------------------------------------------------

    importance_df <- extract_rf_importance(fit_result$model)

    top10 <- head(importance_df, 10)
    cat("    Top 10 features:\n")
    for (i in seq_len(nrow(top10))) {
      cat(sprintf("      %2d. %-35s %.6f\n",
                  i, top10$feature[i], top10$importance[i]))
    }

    # --- Save importance CSV ------------------------------------------------

    imp_slug <- sprintf("rf_importance_%s_%s", cohort$slug, oc$slug)
    imp_path <- file.path(PATHS$output_tables, paste0(imp_slug, ".csv"))
    write.csv(importance_df, imp_path, row.names = FALSE)

    # --- Save importance plot -----------------------------------------------

    plot_title <- sprintf("%s\n%s — Permutation Importance (Top 15)",
                          cohort$label, oc$label)
    p <- plot_rf_importance(importance_df, title = plot_title, top_n = 15L)

    fig_path <- file.path(PATHS$output_figures, paste0(imp_slug, ".png"))
    ggplot2::ggsave(fig_path, plot = p, width = 7, height = 5, dpi = 150)

    # --- Store model and AUC row -------------------------------------------

    model_key               <- sprintf("%s_%s", cohort$slug, oc$slug)
    all_models[[model_key]] <- fit_result$model

    auc_rows[[length(auc_rows) + 1]] <- data.frame(
      cohort_label       = cohort$label,
      outcome_label      = oc$label,
      n_total            = n_total,
      n_events           = n_events,
      n_train            = n_train,
      n_train_events     = n_train_events,
      n_tune             = if (!is.null(tune_data)) nrow(tune_data) else n_train,
      best_mtry          = best_params$mtry,
      best_min_node_size = best_params$min.node.size,
      test_auc           = round(eval_result$auc, 4),
      stringsAsFactors   = FALSE
    )

    fit_count <- fit_count + 1L

    if (RF_DEV_MODE) {
      cat("\n  *** DEV MODE: stopping after first outcome ***\n")
      break
    }
  }
}

# ---------------------------------------------------------------------------
# Save outputs
# ---------------------------------------------------------------------------

if (length(all_models) == 0L) {
  stop(
    "No RF models were successfully fit. ",
    "Check validation errors above and re-run scripts/02_clean_data.R if needed."
  )
}

models_path <- file.path(PATHS$output_models, "rf_models.rds")
saveRDS(all_models, models_path)

auc_df   <- do.call(rbind, auc_rows)
auc_path <- file.path(PATHS$output_tables, "rf_auc_summary.csv")
write.csv(auc_df, auc_path, row.names = FALSE)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

cat("\n")
cat("====================================================\n")
cat("Random forest modeling summary\n")
cat("====================================================\n")
cat(sprintf("  Tuning subset:       %s (max_n = %d)\n",
    if (USE_TUNING_SUBSET) "enabled" else "disabled", TUNING_MAX_N))
cat(sprintf("  Tune trees:          %d | Final trees: %d\n",
    TUNE_NUM_TREES, FINAL_NUM_TREES))
cat(sprintf("  Cohorts modeled:     %s\n",
    paste(sapply(cohort_list, `[[`, "label"), collapse = ", ")))
cat(sprintf("  Outcomes modeled:    %s\n",
    paste(sapply(outcome_specs, `[[`, "label"), collapse = ", ")))
cat(sprintf("  Models fit:          %d\n", fit_count))

if (length(skipped_msgs) > 0L) {
  cat(sprintf("  Models skipped:      %d\n", length(skipped_msgs)))
  cat("\nSkipped model details:\n")
  for (m in skipped_msgs) cat(m, "\n")
} else {
  cat("  Models skipped:      0\n")
}

cat("\nAUC summary:\n")
for (i in seq_len(nrow(auc_df))) {
  cat(sprintf("  %-35s | %-12s | AUC = %.4f\n",
              auc_df$cohort_label[i], auc_df$outcome_label[i],
              auc_df$test_auc[i]))
}

cat("\nOutput files:\n")
for (cohort in cohort_list) {
  for (oc in outcome_specs) {
    slug <- sprintf("rf_importance_%s_%s", cohort$slug, oc$slug)
    cat("  ", file.path(PATHS$output_tables,  paste0(slug, ".csv")), "\n")
    cat("  ", file.path(PATHS$output_figures, paste0(slug, ".png")), "\n")
  }
}
cat("  ", auc_path,    "\n")
cat("  ", models_path, "\n")
