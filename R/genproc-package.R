#' genproc: composable execution layers for iterative R procedures
#'
#' The `genproc` package wraps classical iteration constructs
#' (`for`, [base::lapply()], [purrr::pmap()], ...) with orthogonal
#' execution layers so that one-off scripts can be turned into
#' production-grade procedures without restructuring the user's code.
#'
#' Two layers are always active (they cannot be disabled):
#'
#' * *Logged*: each case produces a structured log row with the real
#'   traceback (captured through `withCallingHandlers()`) and timing.
#' * *Reproducibility*: each run records the R version, loaded package
#'   versions, execution environment, the exact mask used, and hashes of
#'   the file inputs referenced by the mask, so that silent
#'   non-reproducibility between runs can be flagged to the user.
#'
#' Further layers are planned (parallel, non-blocking, monitored, error
#' replay). They will be composable with the default layers and opt-in.
#'
#' This package has no Shiny dependency and is intended to be reusable
#' from a future companion Shiny package.
#'
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL
