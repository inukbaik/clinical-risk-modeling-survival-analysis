# Project Wiki — Index

This is a manually maintained Obsidian-backed wiki for the
`clinical-risk-modeling-survival-analysis` repository. The repo folder
itself is the Obsidian vault — there is no separate copied vault.

This wiki is **project context**, not a source of truth. Implementation
details (column names, function signatures, script order) can drift from
these notes. Before relying on a specific claim here, verify it against the
actual file (`R/config.R`, the relevant script, etc.).

## Pages

- [[01-pipeline-map]] — scripts, `R/` modules, and how they connect
- [[02-data-workflow]] — synthetic data generation and cleaning
- [[03-modeling-workflow]] — descriptive tables, PSM, Cox, random forest
- [[04-output-inventory]] — what's in `outputs/` and how each file is produced
- [[05-reproducibility]] — running the pipeline end to end, seeds, dependencies
- [[06-agent-rules]] — rules for Claude Code sessions working in this repo

## Start here for common tasks

- **"What does this pipeline do?"** → [[01-pipeline-map]]
- **"What columns exist and where are they defined?"** → [[02-data-workflow]], then `R/config.R`
- **"How do I regenerate outputs?"** → [[05-reproducibility]]
- **"What am I not allowed to do as an agent?"** → [[06-agent-rules]] and the repo's `CLAUDE.md`

## Repository purpose

A public-safe, fully synthetic demo of an observational clinical modeling
workflow: synthetic cohort generation → cleaning → descriptive comparison →
propensity score matching → Cox proportional hazards modeling → random
forest feature importance. No real patient data is used or referenced.
