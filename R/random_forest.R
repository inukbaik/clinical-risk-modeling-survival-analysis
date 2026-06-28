# random_forest.R
#
# Reusable functions for the random forest feature importance step.
# No file I/O or hard-coded paths. All functions are independently callable.
# Assumes outcome has been validated as binary integer before prepare_rf_outcome().
#
# Two-phase fitting strategy:
#   Phase 1 — caret CV on a small stratified tuning subset to select hyperparameters.
#   Phase 2 — final ranger model on the full SMOTE'd training data using best params.
# This separates the expensive CV grid search from the full-data final fit.

MATCHIT_ARTIFACT_VARS <- c("subclass", "weights", "distance")

# ---------------------------------------------------------------------------
# build_rf_predictor_set
# ---------------------------------------------------------------------------
# Returns the predictor column names for RF: group_var + baseline_predictors,
# minus leakage variables and MatchIt artifact columns, keeping only names
# that are actually present in data.

build_rf_predictor_set <- function(data, group_var, baseline_predictors, leakage_vars) {
  candidates <- unique(c(group_var, baseline_predictors))
  candidates <- setdiff(candidates, leakage_vars)
  candidates <- setdiff(candidates, MATCHIT_ARTIFACT_VARS)
  candidates[candidates %in% names(data)]
}

# ---------------------------------------------------------------------------
# prepare_rf_outcome
# ---------------------------------------------------------------------------
# Converts a binary integer outcome column (0/1) to a factor with labels
# "NoEvent" (0) and "Event" (1). Call after validate_binary_outcome().

prepare_rf_outcome <- function(data, outcome_var) {
  data[[outcome_var]] <- factor(
    data[[outcome_var]],
    levels = c(0L, 1L),
    labels = c("NoEvent", "Event")
  )
  data
}

# ---------------------------------------------------------------------------
# split_rf_data
# ---------------------------------------------------------------------------
# Stratified 80/20 train/test split on the factor outcome produced by
# prepare_rf_outcome(). Returns list(train, test).

split_rf_data <- function(data, outcome_var, train_frac = 0.80, seed = 123L) {
  if (!outcome_var %in% names(data)) {
    stop(sprintf("split_rf_data: outcome column '%s' not found.", outcome_var))
  }

  col <- data[[outcome_var]]
  if (!is.factor(col)) {
    stop(sprintf(
      "split_rf_data: '%s' must be a factor. Call prepare_rf_outcome() first.",
      outcome_var
    ))
  }

  set.seed(seed)

  event_idx    <- which(col == "Event")
  nonevent_idx <- which(col == "NoEvent")

  n_train_event    <- floor(length(event_idx)    * train_frac)
  n_train_nonevent <- floor(length(nonevent_idx) * train_frac)

  train_idx <- c(
    sample(event_idx,    n_train_event),
    sample(nonevent_idx, n_train_nonevent)
  )

  list(
    train = data[ train_idx, , drop = FALSE],
    test  = data[-train_idx, , drop = FALSE]
  )
}

# ---------------------------------------------------------------------------
# create_tuning_subset
# ---------------------------------------------------------------------------
# Returns a stratified random sample of at most max_n rows from data,
# preserving the event/non-event ratio observed in data[[outcome_var]].
# If nrow(data) <= max_n, returns data unchanged.

create_tuning_subset <- function(data, outcome_var, max_n, seed = 123L) {
  if (nrow(data) <= max_n) return(data)

  col          <- data[[outcome_var]]
  event_idx    <- which(col == "Event")
  nonevent_idx <- which(col == "NoEvent")

  event_rate <- length(event_idx) / nrow(data)
  n_event    <- max(1L, floor(max_n * event_rate))
  n_nonevent <- max_n - n_event

  n_event    <- min(n_event,    length(event_idx))
  n_nonevent <- min(n_nonevent, length(nonevent_idx))

  set.seed(seed)
  idx <- c(
    sample(event_idx,    n_event),
    sample(nonevent_idx, n_nonevent)
  )

  data[idx, , drop = FALSE]
}

# ---------------------------------------------------------------------------
# fit_rf_model
# ---------------------------------------------------------------------------
# Two-phase fitting:
#   Phase 1: caret CV on tune_data (defaults to train_data if not supplied)
#            using tune_num_trees to select best mtry / min.node.size.
#   Phase 2: final ranger model on the full SMOTE'd train_data using
#            best params and final_num_trees.
#
# Returns list(model, rec_prepped, best_params, tune_model):
#   model       — fitted ranger object (used for prediction and importance)
#   rec_prepped — recipe prepped on full train_data (used to bake test data)
#   best_params — data.frame row from caret bestTune
#   tune_model  — caret train object from the tuning phase

fit_rf_model <- function(
  train_data,
  outcome_var,
  predictors,
  tune_grid,
  ctrl,
  seed            = 123L,
  over_ratio      = 0.5,
  tune_data       = NULL,
  tune_num_trees  = 100L,
  final_num_trees = 500L
) {
  rec_formula <- stats::as.formula(paste(outcome_var, "~ ."))

  # ---------------------------------------------------------------------------
  # Phase 1: caret CV on the tuning data
  # ---------------------------------------------------------------------------

  cv_data <- if (!is.null(tune_data)) tune_data else train_data
  cv_data  <- cv_data[, c(predictors, outcome_var), drop = FALSE]

  rec_tune  <- recipes::recipe(rec_formula, data = cv_data)
  rec_tune  <- recipes::step_dummy(rec_tune, recipes::all_nominal_predictors())
  rec_tune  <- themis::step_smote(rec_tune, tidyselect::all_of(outcome_var),
                                  over_ratio = over_ratio, seed = seed)

  rec_tune_prepped <- recipes::prep(rec_tune, training = cv_data)
  cv_baked         <- recipes::bake(rec_tune_prepped, new_data = NULL)

  x_cv <- cv_baked[, setdiff(names(cv_baked), outcome_var), drop = FALSE]
  y_cv <- cv_baked[[outcome_var]]

  set.seed(seed)
  tune_model <- caret::train(
    x          = x_cv,
    y          = y_cv,
    method     = "ranger",
    trControl  = ctrl,
    tuneGrid   = tune_grid,
    metric     = "ROC",
    num.trees  = tune_num_trees,
    seed       = seed
  )

  best_params <- tune_model$bestTune

  # ---------------------------------------------------------------------------
  # Phase 2: final ranger model on the full training data
  # ---------------------------------------------------------------------------

  train_subset <- train_data[, c(predictors, outcome_var), drop = FALSE]

  rec_train         <- recipes::recipe(rec_formula, data = train_subset)
  rec_train         <- recipes::step_dummy(rec_train, recipes::all_nominal_predictors())
  rec_train         <- themis::step_smote(rec_train, tidyselect::all_of(outcome_var),
                                          over_ratio = over_ratio, seed = seed)
  rec_train_prepped <- recipes::prep(rec_train, training = train_subset)
  train_baked       <- recipes::bake(rec_train_prepped, new_data = NULL)

  x_train <- train_baked[, setdiff(names(train_baked), outcome_var), drop = FALSE]
  y_train <- train_baked[[outcome_var]]

  set.seed(seed)
  final_model <- ranger::ranger(
    x             = x_train,
    y             = y_train,
    num.trees     = final_num_trees,
    mtry          = best_params$mtry,
    splitrule     = as.character(best_params$splitrule),
    min.node.size = best_params$min.node.size,
    importance    = "permutation",
    probability   = TRUE,
    seed          = seed
  )

  list(
    model       = final_model,
    rec_prepped = rec_train_prepped,
    best_params = best_params,
    tune_model  = tune_model
  )
}

# ---------------------------------------------------------------------------
# evaluate_rf_model
# ---------------------------------------------------------------------------
# Applies the prepped recipe to test_data (SMOTE skipped automatically),
# predicts class probabilities from the ranger object, and returns
# list(auc, roc_obj).

evaluate_rf_model <- function(fit_result, test_data, outcome_var, predictors) {
  model       <- fit_result$model
  rec_prepped <- fit_result$rec_prepped

  test_subset <- test_data[, c(predictors, outcome_var), drop = FALSE]
  test_baked  <- recipes::bake(rec_prepped, new_data = test_subset)

  x_test <- test_baked[, setdiff(names(test_baked), outcome_var), drop = FALSE]
  y_test <- test_baked[[outcome_var]]

  probs   <- predict(model, data = x_test)$predictions

  roc_obj <- pROC::roc(
    response  = y_test,
    predictor = probs[, "Event"],
    levels    = c("NoEvent", "Event"),
    direction = "<",
    quiet     = TRUE
  )

  list(
    auc     = as.numeric(pROC::auc(roc_obj)),
    roc_obj = roc_obj
  )
}

# ---------------------------------------------------------------------------
# extract_rf_importance
# ---------------------------------------------------------------------------
# Extracts permutation importance from the final ranger model.
# Returns a data.frame sorted descending by importance.

extract_rf_importance <- function(model) {
  if (is.null(model$variable.importance)) {
    stop("extract_rf_importance: no variable importance found. ",
         "Ensure importance = 'permutation' was set in ranger::ranger().")
  }

  imp <- model$variable.importance

  df <- data.frame(
    feature    = names(imp),
    importance = as.numeric(imp),
    row.names  = NULL,
    stringsAsFactors = FALSE
  )

  df[order(df$importance, decreasing = TRUE), ]
}

# ---------------------------------------------------------------------------
# plot_rf_importance
# ---------------------------------------------------------------------------
# Returns a ggplot2 horizontal bar chart of the top_n most important features.

plot_rf_importance <- function(importance_df, title, top_n = 15L) {
  plot_df         <- importance_df[seq_len(min(top_n, nrow(importance_df))), ]
  plot_df$feature <- factor(plot_df$feature, levels = rev(plot_df$feature))

  ggplot2::ggplot(plot_df, ggplot2::aes(x = importance, y = feature)) +
    ggplot2::geom_bar(stat = "identity", fill = "#3B82F6") +
    ggplot2::labs(
      title = title,
      x     = "Permutation Importance",
      y     = NULL
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      plot.title  = ggplot2::element_text(size = 13, face = "bold"),
      axis.text.y = ggplot2::element_text(size = 10)
    )
}
