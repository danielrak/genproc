#' genproc: robust, logged and reproducible iteration at organizational scale
#'
#' The `genproc` package wraps classical iteration constructs
#' (`for`, [base::lapply()], [purrr::pmap()], ...) with orthogonal
#' execution layers so that one-off scripts can be turned into
#' production-grade procedures without restructuring the user's code.
#'
#' Two layers are always active and cannot be disabled:
#'
#' * *Logged*: each case produces a structured log row with the real
#'   traceback (captured via `withCallingHandlers()`) and per-case
#'   timing.
#' * *Reproducibility*: each run records the R version, loaded package
#'   versions, execution environment, the exact mask used, and a
#'   stat-based fingerprint (size + modification time) of every input
#'   file referenced by the mask. Silent drift of an upstream file
#'   between two runs can then be detected via [diff_inputs()].
#'
#' Two optional, composable layers can be enabled per call:
#'
#' * *Parallel*: dispatch cases to workers via the
#'   [future][future::future] ecosystem and
#'   [future.apply::future_lapply()]. Configured through
#'   [parallel_spec()].
#' * *Non-blocking*: return a `genproc_result` skeleton immediately
#'   while the run continues in a background future. Poll with
#'   [status()], block with [await()]. Configured through
#'   [nonblocking_spec()].
#'
#' Further layers are on the roadmap: monitored progress, error replay,
#' content-hash input fingerprinting, content-based case identifiers.
#' They will be composable with the default layers and opt-in.
#'
#' This package has no Shiny dependency and is designed to be
#' consumable by a future companion Shiny package.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
