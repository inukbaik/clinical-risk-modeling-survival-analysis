# Clinical Risk Modeling & Survival Analysis

A reproducible walkthrough of an observational drug-safety analysis, rebuilt end to end on
synthetic data and organised around the three problems that took the most work to get
right.

Everything here runs from a fixed seed. No real patient data, no real results, and no real
cohort characteristics appear anywhere in this repository.

## Why It Is Organised Around Problems

Most analysis write-ups are organised around methods: here is the balance table, here is
the Cox model, here is the forest. That order describes what was produced but not what was
difficult, and it hides the decisions that actually determined whether the numbers meant
anything.

These notebooks are organised the other way round. Each of the three main sections starts
from something that did not work, or that produced a result which could not be taken at
face value, and follows it through to a resolution.

Because the data is simulated, the true parameter values are known, and every estimate is
checked against the value that generated it. That check is the thing a real analysis can
never do — and it is what turns "the model ran" into "the model recovered the answer".

## The Three Problems

**Matching ran, but it did not balance.** Nearest-neighbour matching without a caliper
returns matched pairs no matter how poor the matches are. In this cohort it made balance
*worse* than no matching at all — the largest standardized mean difference rose from 0.25
to 0.38 — while retaining 96% of subjects and raising no error. The fix is a caliper
search that logs every attempt and fails loudly when nothing achieves balance.

**Two random forests gave different answers.** One fitted on unmatched data with treatment
excluded, one on matched data with treatment included. They disagree because they answer
different questions, and neither estimates a treatment effect. With the truth known, this
can be shown rather than argued: a variable whose true effect is exactly zero ranks third,
while the variable with the largest true effect ranks seventh.

**A competing event that cannot be ignored.** Death competes with the outcome, and
censoring it overstates cumulative incidence. This section uses overlap weighting for
confounding control and a weighted Fine-Gray model for the subdistribution hazard, reports
the cause-specific hazard alongside it, explains why the robust sandwich variance is the
correct one for analytic weights, and surrounds the primary estimate with six sensitivity
analyses.

## The Two Studies

| | Study A | Study B |
|---|---|---|
| Confounding control | 1:1 nearest-neighbour matching on the propensity score | Overlap weighting |
| Outcome models | Nested Cox proportional hazards ladder | Fine-Gray and cause-specific Cox |
| Competing risks | Not modelled | Death as a competing event |
| Machine learning | Random forest feature importance | — |

Study B is where the design went after Study A. Matching had to chase balance by
tightening a caliper and paid for it in discarded subjects; overlap weighting balances
exactly, by construction, with no tuning parameter.

## Notebooks

| | Contents |
|---|---|
| `00-synthetic-data.qmd` | What is simulated, how, and what the masking preserves |
| `01-balance-and-psm.qmd` | Table 1, SMD-based balance, the caliper search |
| `02-cox-models.qmd` | Nested adjustment ladder, Kaplan-Meier curves, PH checks |
| `03-random-forest.qmd` | Matched and unmatched importance, side by side |
| `04-overlap-weighting.qmd` | Propensity model, three weighting schemes, effective sample size |
| `05-competing-risks.qmd` | Event definition, Fine-Gray, sensitivity analyses |

## Synthetic Data

The cohorts are generated rather than anonymised. Renaming the columns of a real dataset
leaves the values, counts and joint distribution real; regenerating from scratch does not.

What is preserved is the structure that makes the analysis non-trivial:

- a confounded exposure, where the same covariates drive treatment and outcome
- correlated comorbidities rather than independent draws
- a lab measure on the causal pathway, excluded from the propensity model and entered last
  in the adjustment ladder
- competing risks with month-precision death dates
- two genuine data defects: a literal `"null"` string in a character column, and negative
  follow-up times

Survival times come from a Weibull proportional hazards model, so `exp(β)` is a true
hazard ratio. Follow-up time is derived from the event and censoring times — never drawn
first and then used to predict the event, which would leave no hazard ratio for a Cox
model to estimate.

## Schema

| Variable | Role |
|---|---|
| `record_id` | Identifier |
| `exposure_group` | Exposure, reference level first |
| `demo_age`, `demo_sex`, `demo_race` | Demographics |
| `clinical_binary_1` … `clinical_binary_6` | Baseline comorbidities |
| `clinical_continuous_1` | Baseline lab measure, on the causal pathway |
| `outcome_1`, `outcome_2` | Event indicators (Study A) |
| `followup_time_1`, `followup_time_2` | Follow-up time in years (Study A) |
| `post_baseline_indicator` | Post-baseline flag, excluded from all models |
| `baseline_date`, `last_fu_date`, `event_date`, `death_month_date` | Dates (Study B) |
| `cr_status`, `cs_event`, `fu_years` | Derived competing-risk outcome (Study B) |

`R/config.R` is the single definition of this schema and of the true parameter values.

## Running It

```bash
Rscript -e 'renv::restore()'
quarto render
```

A cold render takes roughly two minutes and writes the site to `_site/`. Subsequent
renders reuse Quarto's freeze cache.

The synthetic cohorts are generated on first use and cached to `data/synthetic/`, which is
not tracked: the data is derived, it rebuilds in about two seconds, and a repository that
ships a data file it cannot regenerate is one you cannot check.

## Repository Layout

```
R/
  config.R      schema, true parameters, analysis constants
  simulate.R    both cohorts, including the competing-risks generator
  clean.R       cleaning decisions and attrition accounting
  balance.R     SMD helpers, caliper search, weighting diagnostics
  inference.R   model result extraction, PH testing
  setup.R       sourced by every notebook
notebooks/      the six analysis notebooks
outputs/tables/ result tables exported by the notebooks
```

Figures are embedded in the rendered notebooks rather than written to disk. Result tables
are exported so a number can be checked without re-rendering.

## Dependencies

R 4.6.0 with `renv`. The main analysis packages are `survival`, `MatchIt`, `cobalt`,
`survey`, `tableone`, `ranger`, `caret`, `recipes`, `themis` and `pROC`. Rendering needs
Quarto.

## License

MIT — see `LICENSE`.
