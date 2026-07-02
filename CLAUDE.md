# CLAUDE.md

## Before editing: read the wiki first

Before making any change in this repository, read
`docs/wiki/00-index.md` and `docs/wiki/06-agent-rules.md`. The wiki
(`docs/wiki/`) is manually maintained project context — it explains the
pipeline, data workflow, and output inventory — but it is **not**
authoritative. It can drift from the code. Verify any specific claim
(column names, function signatures, file paths, script order) against the
actual files (starting with `R/config.R`) before relying on it.

## Project purpose

This repository is a public-safe clinical modeling demo using synthetic data.  
It demonstrates a reproducible workflow for:

- synthetic cohort generation
- data cleaning and validation
- descriptive cohort comparison
- propensity score matching
- Cox proportional hazards modeling
- random forest feature importance

The project should not contain real patient data.

## Core rules

- Do not use real clinical data.
- Do not create or infer protected health information.
- Do not silently change schema names.
- Do not modify files outside the requested task scope.
- Do not commit changes automatically.
- Do not delete existing outputs unless explicitly instructed.
- Prefer simple, readable R code over unnecessary abstraction.
- Every script should be runnable independently.
- Every major step should fail fast if required inputs are missing.
- Every major step should fail fast if required inputs have unexpected types.

## Data leakage rules

The following variables must not be used as baseline predictors in random forest feature importance:

- follow-up time variables
- death indicators
- post-baseline indicators
- outcome variables
- variables created after index date

Cox models may use follow-up time only as the survival time variable.

## Schema rules

Use stable synthetic variable names, as defined in `R/config.R`. That file
is authoritative for schema — verify against it before relying on the list
below.

Identifier:
- record_id

Exposure:
- exposure_group

Demographics:
- demo_age
- demo_sex
- demo_race

Clinical (baseline predictors):
- clinical_binary_1
- clinical_binary_2
- clinical_binary_3
- clinical_binary_4
- clinical_binary_5
- clinical_binary_6
- clinical_continuous_1

Outcomes (event indicators):
- outcome_1
- outcome_2

Follow-up time:
- followup_time_1
- followup_time_2

Post-baseline:
- post_baseline_indicator

## Reference RMarkdown rule

The actual research RMarkdown may be used only as a methodological reference.

Claude may use it to understand:
- analysis order
- package usage
- model structure
- table/figure generation
- Cox modeling logic
- propensity score matching logic
- random forest feature importance logic
- validation and event-count checks

Claude must not:
- copy real data
- copy real data paths
- preserve private cohort-specific details
- preserve unmapped real variable names
- include real model results
- include real patient counts
- expose sensitive research context

All implementation in this public demo must use the synthetic schema defined in `R/config.R`.

## Required behavior

Before editing:
- Inspect the relevant files.
- Explain the planned change briefly.
- Do not rewrite unrelated files.

After editing:
- Show changed files.
- Run the relevant script.
- Report validation output.
- Mention remaining risks or assumptions.
- Update PROJECT_LOG.md if the task is completed.

## README style rules

- Do not use "Phase" numbering (e.g. "Phase 1", "Phase 2") to label pipeline steps.
- Do not use pipeline progress tables with status columns (e.g. Complete / Planned).
- Do not use terms associated with AI-assisted or "vibe coding" workflows.
- Use plain named sections (e.g. "## Synthetic Data", "## Data Cleaning") as in the original README structure.
- The planned workflow may be a numbered list but should not imply any step is complete unless it is.

## Failure behavior

If required columns are missing:
- Stop with a clear error.
- Do not rename columns automatically unless the user explicitly asks.

If a dependency file is missing:
- Stop and explain which previous script must be run.

If model fitting fails:
- Report the error.
- Do not create fake output files.
- Do not suppress warnings without explanation.

If validation fails:
- Stop the pipeline.
- Explain what failed.