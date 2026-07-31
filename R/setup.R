# setup.R
#
# Sourced at the top of every notebook. Loads the project's own code and
# creates the output directories. Deliberately does not attach analysis
# packages -- each notebook attaches what it uses, so that reading a notebook
# tells you what that notebook depends on.

source("R/config.R")
source("R/simulate.R")
source("R/clean.R")
source("R/balance.R")
source("R/inference.R")

for (p in c(PATHS$output_tables, dirname(PATHS$study_a))) {
  dir.create(p, recursive = TRUE, showWarnings = FALSE)
}

#' Load a study cohort, generating it on first use.
#'
#' The cached .rds is an optimisation, not a source of truth: it is derived
#' entirely from a fixed seed and can be deleted at any time. Nothing in the
#' repository depends on a data file that cannot be rebuilt.
load_study <- function(study = c("a", "b"), refresh = FALSE) {
  study <- match.arg(study)
  path  <- if (study == "a") PATHS$study_a else PATHS$study_b

  if (!refresh && file.exists(path)) return(readRDS(path))

  df <- if (study == "a") simulate_study_a() else simulate_study_b()
  saveRDS(df, path)
  df
}

#' Write a table to outputs/tables and return it unchanged, for piping.
save_table <- function(df, name) {
  utils::write.csv(df, file.path(PATHS$output_tables, paste0(name, ".csv")),
                   row.names = FALSE)
  df
}
