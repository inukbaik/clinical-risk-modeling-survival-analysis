# CLAUDE.md

## Project purpose

A public-safe demonstration of an observational drug-safety analysis, built entirely on
synthetic data and organised around three problems rather than around a list of methods.

The repository covers two studies:

- **Study A** — propensity score matching, a nested Cox adjustment ladder, and random
  forest feature importance
- **Study B** — overlap weighting and competing-risks analysis with a Fine-Gray model

The notebooks in `notebooks/` are the deliverable. `R/` holds the code they share.

## Before editing

- Read `R/config.R` first. It is the single definition of the schema, the true parameter
  values, and the analysis constants.
- Inspect the relevant notebook and helper before changing either.
- Explain the planned change briefly.
- Do not rewrite unrelated files.

## Core rules

- Do not use real clinical data.
- Do not create or infer protected health information.
- Do not silently change schema names.
- Do not modify files outside the requested task scope.
- Do not commit changes automatically.
- Prefer simple, readable R code over unnecessary abstraction.
- Every notebook must render independently.
- Fail fast and loudly. Do not add skip-and-continue error handling.

## The truth is known — use it

Because the data is generated, the true parameter values are available in `R/config.R`
(`TRUE_A_OUTCOME_1`, `TRUE_B_EVENT`, and so on). Every notebook checks its estimates
against them using `stopifnot()`.

These assertions are the point, not decoration. When adding an analysis, add the check
that would fail if it were wrong. When an assertion fails, diagnose it — do not loosen the
tolerance or change the seed to make it pass. Tuning code to produce a desired number is
the one thing this repository exists to argue against.

## Schema

`R/config.R` is authoritative. Verify against it before relying on anything below.

Shared across both studies:

- `record_id` — identifier
- `exposure_group` — exposure; `STUDY_A_GROUP_LEVELS` / `STUDY_B_GROUP_LEVELS`, reference
  level first
- `demo_age`, `demo_sex`, `demo_race` — demographics; `demo_race` carries a literal
  `"null"` code before cleaning
- `clinical_binary_1` … `clinical_binary_6` — baseline comorbidities
- `clinical_continuous_1` — baseline lab measure

Study A adds `outcome_1`, `outcome_2`, `followup_time_1`, `followup_time_2`, and
`post_baseline_indicator`.

Study B adds `baseline_date`, `last_fu_date`, `event_date`, `death_month_date`, `death`,
and the derived `fu_years`, `cr_status`, `cs_event`.

## Data leakage rules

Predictor sets are built as **whitelists** from `BASELINE_PREDICTORS`. Do not replace this
with a blacklist of forbidden columns: a whitelist fails safe when a new column appears,
a blacklist fails silently.

Never admissible as a baseline predictor:

- follow-up time variables
- outcome and event indicators
- `post_baseline_indicator` or anything else measured after index
- `record_id`
- the `MatchIt` artifacts `distance`, `weights`, `subclass` (`MATCHIT_ARTIFACT_VARS`)

Cox and Fine-Gray models may use follow-up time only as the survival time.

## Statistical rules

- Judge balance on the standardized mean difference against `SMD_THRESHOLD`, never on a
  hypothesis test. At this sample size a test detects differences too small to matter.
- Compute post-adjustment SMDs against pre-adjustment denominators, so before and after
  are on one scale.
- Matched analyses carry `cluster(subclass)`; matched pairs are not independent.
- Weighted models and Fine-Gray fits use `id =` with `robust = TRUE`, and every interval
  and p-value comes from `fit$var` (sandwich), never `fit$naive.var`. Overlap weights are
  analytic, not frequency, weights.
- Never apply `cox.zph()` to a Fine-Gray fit. Use `ph_interval_test()` instead.
- Do not describe an estimator as robust unless the code implements it.
- Report effective sample size alongside any weighted analysis.
- State PH conclusions as absence of evidence, never as confirmation.

## Failure behavior

- Missing required columns: stop with a clear error. Do not rename columns automatically.
- Missing dependency file: stop and name the notebook that produces it.
- Model fitting fails: report the error. Do not fabricate outputs.
- Assertion fails: diagnose the cause. Do not weaken the assertion.
- Never wrap a whole block in `suppressWarnings()`. Root-cause the warning and scope any
  muffling to the specific message, with a comment saying why.

## Reference material rule

Real research materials may be consulted as a methodological reference only — for analysis
order, package usage, model structure, and validation logic.

Never carry across real data, real file paths, real variable names, real results, real
patient counts, or cohort-specific detail. All implementation uses the synthetic schema in
`R/config.R`.

## README style rules

- No "Phase" numbering to label pipeline steps.
- No progress tables with status columns.
- No terminology associated with AI-assisted workflows.
- Plain named sections.

## After editing

- Show changed files.
- Render the affected notebook and report the actual output.
- Mention remaining risks or assumptions.
- Update `PROJECT_LOG.md` when a task is complete.
