# Agent Rules

This page summarizes the operating rules for Claude Code sessions in this
repository. **`CLAUDE.md` at the repo root is authoritative** — if this
page and `CLAUDE.md` ever disagree, follow `CLAUDE.md` and treat this page
as stale.

See also: [[00-index]], [[02-data-workflow]]

## Non-negotiables

- No real clinical data, ever. No inferring or creating protected health
  information.
- Do not silently rename or reinterpret schema variable names — verify
  against `R/config.R`, not against this wiki or `CLAUDE.md`'s schema
  section, since implementations can diverge (see the schema note in
  [[02-data-workflow]]).
- Do not modify files outside the requested task scope.
- Do not commit changes automatically — the user commits.
- Do not delete existing outputs unless explicitly instructed.

## Data leakage

These must never be used as baseline predictors in random forest feature
importance (enforced in code via `LEAKAGE_VARS` in `R/config.R`):
- follow-up time variables
- event/outcome indicators
- post-baseline indicators
- record identifiers

Cox models may use follow-up time only as the survival time variable, not
as a predictor.

## Fail-fast expectations

- Missing required columns → stop with a clear error, do not auto-rename.
- Missing dependency file (e.g. a prior script's output) → stop and name
  which script must be run first.
- Model fitting failure → report the error; do not fabricate output files
  or silently suppress warnings.
- Validation failure → stop the pipeline step and explain what failed.

## Before editing

1. Inspect the relevant files first — don't assume this wiki is current.
2. Explain the planned change briefly before making it.
3. Don't rewrite unrelated files.

## After editing

1. Show changed files.
2. Run the relevant script and report its actual console/validation output.
3. Mention remaining risks or assumptions.
4. Update `PROJECT_LOG.md` if the task is completed (see existing entries
   for the expected format: Task / Files created/edited / Outputs produced
   / Validation results / Assumptions).

## Reference RMarkdown (if present)

Any real research RMarkdown that may be shared as a *methodological*
reference may inform analysis order, package usage, model structure, and
validation logic — but must never contribute real data, real paths, real
variable names, real results, or real patient counts into this public
repository.

## Using this wiki

This wiki (`docs/wiki/`) is maintained manually, not regenerated
automatically. It will drift from the code over time. Treat it as a map,
not the territory — confirm specifics (function names, column lists,
output paths) against the actual files before acting on them.
