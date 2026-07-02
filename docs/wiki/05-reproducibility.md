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

`PROJECT_SEED <- 123L` is defined in `R/config.R` as the single
project-level seed used across all stochastic pipeline steps: synthetic
data generation, propensity score matching, and the random forest
train/test split, SMOTE, and CV tuning folds.

## Package dependencies

Scripts check for required packages and fail fast with install
instructions if any are missing, rather than silently attempting to
proceed. Packages used across the pipeline include: `tableone`,
`MatchIt`, `survival`, `caret`, `ranger`, `recipes`, `themis`, `pROC`,
`ggplot2`, `tidyselect`. `doParallel` is optional — the random forest step
uses parallel processing when it's available and CPU core detection
succeeds, and falls back to single-threaded execution if `doParallel` isn't
installed, `parallel::detectCores()` can't determine a usable core count
(e.g. in some sandboxed or restricted environments), or fewer than 2 cores
are available. This is a runtime speed optimization only and never blocks
the pipeline from completing.

Exact package versions are pinned in `renv.lock` via
[`renv`](https://rstudio.github.io/renv/). Restore the recorded versions
into a project-local library with `renv::restore()`.

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
