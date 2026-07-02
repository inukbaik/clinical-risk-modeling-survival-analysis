# Data Workflow

See also: [[01-pipeline-map]], [[06-agent-rules]]

## Synthetic data only

All data in this repository is generated programmatically by
`scripts/01_generate_synthetic_data.R`. There is no real patient data,
no protected health information, and no study-specific variable names.
Column names are intentionally generic (`clinical_binary_1`, `outcome_1`,
etc.) rather than clinically specific.

## Generation

`scripts/01_generate_synthetic_data.R` → `data/synthetic/synthetic_cohort.csv`

Produces a synthetic cohort with:
- `record_id` — row identifier
- `demo_age`, `demo_sex`, `demo_race` — demographics
- `clinical_binary_1`–`clinical_binary_6`, `clinical_continuous_1` — baseline predictors
- `exposure_group` — `Exposure_A` / `Exposure_B`
- `outcome_1`, `outcome_2` — binary event indicators
- `followup_time_1`, `followup_time_2` — outcome-specific follow-up time (years)
- `post_baseline_indicator` — post-baseline variable, deliberately excluded from
  predictive modeling to demonstrate leakage avoidance

The raw CSV is tracked in git. The full required-column list is enforced by
`.REQUIRED_COLUMNS` in `R/data_cleaning.R` and must match this schema.

## Cleaning

`scripts/02_clean_data.R` → `data/synthetic/synthetic_cohort_clean.rds`

Calls `clean_clinical_data()` (`R/data_cleaning.R`), which:
- Validates all required columns are present; stops with a clear error listing
  missing columns otherwise
- Drops records with missing or non-positive follow-up time
- Casts `demo_age`, `clinical_continuous_1`, follow-up times to numeric
- Casts `outcome_1`, `outcome_2` to integer
- Factors `exposure_group` (`Exposure_A` as reference level), `demo_sex`,
  `demo_race`, the six `clinical_binary_*` columns, and
  `post_baseline_indicator`

`create_age_subcohort(data, age_cutoff = 65)` filters a cleaned data frame to
`demo_age >= age_cutoff`; used to build the age 65+ cohort in downstream
steps. Requires `clean_clinical_data()` to have already run (checks that
`demo_age` is numeric).

Downstream scripts load the `.rds` file via `readRDS()`, not the CSV, so
factor levels and types are preserved exactly.

## Schema note

`CLAUDE.md` documents a target synthetic schema (`comorb_*`, `baseline_gfr`,
`outcome_ci`/`outcome_eskd`, etc.). The **current implemented code** uses a
different, already-generic naming scheme (`clinical_binary_1..6`,
`clinical_continuous_1`, `outcome_1`/`outcome_2`,
`followup_time_1`/`followup_time_2`) defined in `R/config.R` and
`R/data_cleaning.R`. Treat `R/config.R` as authoritative for what the code
actually does; do not assume the `CLAUDE.md` schema names are in use without
checking.
