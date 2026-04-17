# Non-blocking execution specification
#
# nonblocking_spec() builds a configuration object passed as the
# `nonblocking` argument of genproc(). It records *intent* only —
# where to run the wrapping future — without starting any worker.
#
# Design choices:
#   - The non-blocking layer is a single future that envelops the whole
#     run (validation excluded). One worker is enough; non-blocking
#     is about freeing the console, not about parallel throughput.
#     That is why nonblocking_spec() has no `workers` field: it would
#     never be anything but 1. The parallel layer (parallel_spec) is
#     the one that controls per-case parallelism.
#   - Default `strategy = "multisession"`. A function named
#     "nonblocking" must not silently become blocking because the
#     caller's current plan is sequential — which is the default
#     plan in a fresh R session. Users who manage their own plan can
#     pass `strategy = NULL` to defer to it.
#   - Seed is not exposed: the wrapper future itself does not run
#     user RNG code. Per-case RNG reproducibility is handled by the
#     parallel layer (parallel_spec$seed).
#
# See R/genproc.R for the consumer side.


#' Specify a non-blocking execution strategy for genproc()
#'
#' Returns a configuration object to pass as the `nonblocking`
#' argument of [genproc()]. When supplied, `genproc()` returns
#' immediately with a `genproc_result` of status `"running"` while
#' the actual work continues in a background future. Use [status()]
#' to poll the state and [await()] to block until completion.
#'
#' @param strategy Character, or `NULL`. One of `"sequential"`,
#'   `"multisession"`, `"multicore"`, `"cluster"`. Default
#'   `"multisession"`. Unlike [parallel_spec()], the default is
#'   not `NULL`: a function named "non-blocking" must not silently
#'   block because the current `future::plan()` is sequential. Pass
#'   `strategy = NULL` explicitly to defer to the caller's plan.
#'   `"sequential"` is accepted mainly for deterministic testing —
#'   it exercises the code path but does *not* actually free the
#'   console.
#' @param packages Character vector, or `NULL`. Extra packages to
#'   attach on the background worker before running. \pkg{genproc}
#'   itself is attached automatically for every strategy other than
#'   `"sequential"`.
#' @param globals Logical or character. Forwarded to
#'   `future::future()`'s `globals` argument. Default `TRUE` enables
#'   automatic detection.
#'
#' @return A list of class `"genproc_nonblocking_spec"` with the
#'   validated, normalized fields.
#'
#' @section Composition with parallel_spec():
#'
#' `nonblocking_spec()` and [parallel_spec()] are orthogonal and can
#' be combined. The non-blocking layer launches *one* outer future;
#' inside it, the parallel layer dispatches cases via
#' \pkg{future.apply}. With both strategies set to `"multisession"`,
#' \pkg{future} resolves the inner layer as `"sequential"` by default
#' (see `future::plan()` nesting rules) unless the caller installs an
#' explicit nested plan via `future::plan(list(...))`.
#'
#' @examples
#' # Launch in the background, keep the console
#' \dontrun{
#'   spec <- nonblocking_spec()
#'   job <- genproc(f = slow_fn, mask = mask, nonblocking = spec)
#'   status(job)           # "running"
#'   job <- await(job)     # blocks until done
#'   job$log
#' }
#'
#' # Deterministic test: exercise the code path without real async
#' spec <- nonblocking_spec(strategy = "sequential")
#'
#' @seealso [parallel_spec()], [status()], [await()]
#'
#' @export
nonblocking_spec <- function(strategy = "multisession",
                             packages = NULL,
                             globals = TRUE) {
  # --- strategy ---
  # NULL is allowed (defer to current future::plan()).
  valid_strategies <- c("sequential", "multisession", "multicore", "cluster")
  if (!is.null(strategy)) {
    if (!is.character(strategy) || length(strategy) != 1L ||
        is.na(strategy) || !strategy %in% valid_strategies) {
      stop(
        "`strategy` must be NULL or one of: ",
        paste(shQuote(valid_strategies), collapse = ", "), ".",
        call. = FALSE
      )
    }
  }

  # --- packages ---
  if (!is.null(packages)) {
    if (!is.character(packages) || any(is.na(packages)) ||
        any(!nzchar(packages))) {
      stop("`packages` must be NULL or a non-empty character vector.",
           call. = FALSE)
    }
  }

  # --- globals ---
  if (!is.logical(globals) && !is.character(globals)) {
    stop("`globals` must be logical or a character vector.",
         call. = FALSE)
  }

  structure(
    list(
      strategy = strategy,
      packages = packages,
      globals  = globals
    ),
    class = "genproc_nonblocking_spec"
  )
}
