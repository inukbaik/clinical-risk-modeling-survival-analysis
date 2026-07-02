# Reproducibility

See also: [[01-pipeline-map]], [[04-output-inventory]]

## Running the full pipeline

From the repository root, in order:

```r
Rscript scripts/01_generate_synthetic_data.R
Rscript scripts/02_clean_data.R
Rscript scripts/03_descriptive_tables.R
Rscript scripts/04_propensity_matching.R
Rscript scripts/05_cox_models.R
Rscript scripts/06_random_forest.R
```

Each script is independently runnable given its required inputs exist, and
stops with a clear error message if a required input file or column is
missing (see [[06-agent-rules]] for the fail-fast philosophy).

## Seed

`SEED <- 42` is defined in `R/config.R` as the single source of truth for
reproducibility-sensitive steps (data generation, train/test splits,
SMOTE, matching, CV folds).

## Package dependencies

Scripts check for required packages and fail fast with install
instructions if any are missing, rather than silently attempting to
proceed. Packages used across the pipeline include: `tableone`,
`MatchIt`, `survival`, `caret`, `ranger`, `recipes`, `themis`, `pROC`,
`ggplot2`, `tidyselect`. `doParallel` is optional — the random forest step
degrades gracefully to single-threaded execution if it isn't installed.

## Regenerating outputs after a code change

Because `data/synthetic/*.rds` and `outputs/models/*.rds` are git-ignored,
a fresh clone (or a clone with generated files removed) requires rerunning
scripts `01`–`06` in order. Tracked outputs (`outputs/tables/*.csv`,
`outputs/figures/*.png`) reflect whatever the last local run produced —
they are not guaranteed to be current with the latest code unless someone
reran the pipeline after the change.

## Verifying a change

After modifying an `R/` module or a `scripts/*.R` driver:
1. Run the specific script(s) affected (not necessarily the whole
   pipeline, unless the change touches an early step like cleaning).
2. Confirm the script's own console output/validation messages, not just
   "it exited 0".
3. Check whether downstream scripts depend on a changed output shape
   (e.g. a column added/removed in cleaning affects every script after
   `02_clean_data.R`).
