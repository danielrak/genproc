# Parallel execution specification
#
# parallel_spec() builds a configuration object passed as the
# `parallel` argument of genproc(). It records *intent* — which
# backend, how many workers, how to seed RNG — without starting any
# worker. Workers are created lazily by future when the plan is
# resolved at execution time.
#
# Design choices (state-of-the-art as of 2026):
#   - Backend: the future ecosystem (future + future.apply). Future
#     is the de-facto standard for R parallelism: pluggable backends
#     (sequential, multisession, multicore, cluster, callr-based),
#     proper L'Ecuyer-CMRG RNG handling, mature globals detection.
#   - Spec vs. plan: spec only records intent. The actual plan is
#     either supplied by the caller via future::plan(), or set
#     temporarily by genproc() when `strategy` is given.
#   - Seeds default to TRUE (reproducible CMRG streams). Setting
#     seed = FALSE silently breaks reproducibility and is only
#     recommended when the user code is known to be RNG-free.
#
# See R/genproc.R for the consumer side.


#' Specify a parallel execution strategy for genproc()
#'
#' Returns a configuration object to pass as the `parallel` argument
#' of [genproc()]. The object describes *how* to parallelize; the
#' actual execution is carried out by [future.apply::future_lapply()]
#' on top of the backend selected by [future::plan()].
#'
#' @param workers Integer >= 1, or `NULL`. Number of workers to use.
#'   Ignored when `strategy = "sequential"`. If `NULL`, the current
#'   `future::plan()` decides.
#' @param strategy Character, or `NULL`. One of `"sequential"`,
#'   `"multisession"`, `"multicore"`, `"cluster"`. If `NULL`
#'   (default), the current `future::plan()` is used unchanged. If
#'   specified, genproc temporarily sets the corresponding plan for
#'   the run and restores the previous plan on exit.
#' @param chunk_size Integer >= 1, or `NULL`. Number of iteration
#'   cases bundled per future. Larger values reduce scheduling
#'   overhead at the cost of load-balance granularity. `NULL`
#'   delegates to `future.apply`'s default heuristic.
#' @param seed Controls reproducible random-number generation
#'   across workers. Passed to `future.apply::future_lapply()`'s
#'   `future.seed` argument. Default `TRUE` derives independent
#'   L'Ecuyer-CMRG streams from a random master seed. A single
#'   integer fixes the master seed. `FALSE` disables reproducible
#'   RNG and is not recommended unless the user function is known
#'   to be RNG-free.
#' @param packages Character vector, or `NULL`. Extra packages to
#'   attach on each worker before running the user function.
#'   \pkg{genproc} itself is attached automatically for every
#'   strategy other than `"sequential"`.
#' @param globals Logical or character. Forwarded to
#'   `future.apply::future_lapply()`'s `future.globals`. Default
#'   `TRUE` enables automatic detection, which is correct in almost
#'   all cases. Set to a character vector only to override detection.
#'
#' @return A list of class `"genproc_parallel_spec"` with the
#'   validated, normalized fields.
#'
#' @section Choosing a strategy:
#'
#' - `"sequential"`: runs in the current process, no workers.
#'   Exercises the parallel code path without the overhead; useful
#'   for deterministic testing.
#' - `"multisession"`: portable (works on Windows), launches R
#'   subprocesses via \pkg{parallelly}. The default recommendation
#'   for most workloads.
#' - `"multicore"`: forks the current process (Unix/macOS only,
#'   **not available on Windows** and not reliable inside RStudio).
#'   Faster startup than multisession but loses portability.
#' - `"cluster"`: explicit cluster of workers, possibly on other
#'   machines. For large-scale batch execution.
#'
#' For most users, leaving `strategy = NULL` and calling
#' `future::plan()` once at the top of the session is the cleanest
#' setup.
#'
#' @section RNG reproducibility:
#'
#' With `seed = TRUE`, each case receives an independent
#' L'Ecuyer-CMRG stream derived from a random master seed. Same
#' master seed -> identical results regardless of worker count or
#' chunking. To pin the master seed, pass an integer
#' (`seed = 42L`).
#'
#' @examples
#' # Use whatever plan the caller has set
#' spec <- parallel_spec()
#'
#' # One-off parallel call with 4 workers, reproducible RNG
#' spec <- parallel_spec(workers = 4, strategy = "multisession",
#'                       seed = 42L)
#'
#' # Exercise the parallel code path deterministically in a test
#' spec <- parallel_spec(strategy = "sequential")
#'
#' @export
parallel_spec <- function(workers = NULL,
                          strategy = NULL,
                          chunk_size = NULL,
                          seed = TRUE,
                          packages = NULL,
                          globals = TRUE) {
  # --- workers ---
  if (!is.null(workers)) {
    if (!is.numeric(workers) || length(workers) != 1L ||
        is.na(workers) || workers < 1 ||
        workers != as.integer(workers)) {
      stop("`workers` must be NULL or a positive integer.", call. = FALSE)
    }
    workers <- as.integer(workers)
  }

  # --- strategy ---
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

  # --- chunk_size ---
  if (!is.null(chunk_size)) {
    if (!is.numeric(chunk_size) || length(chunk_size) != 1L ||
        is.na(chunk_size) || chunk_size < 1 ||
        chunk_size != as.integer(chunk_size)) {
      stop("`chunk_size` must be NULL or a positive integer.",
           call. = FALSE)
    }
    chunk_size <- as.integer(chunk_size)
  }

  # --- seed ---
  # Accepts TRUE/FALSE, a single integer master seed, or a list
  # (user-supplied L'Ecuyer-CMRG state).
  seed_ok <- (is.logical(seed)  && length(seed) == 1L && !is.na(seed)) ||
             (is.numeric(seed)  && length(seed) == 1L && !is.na(seed)) ||
             is.list(seed)
  if (!seed_ok) {
    stop(
      "`seed` must be TRUE/FALSE, a single integer master seed, or ",
      "a list (L'Ecuyer-CMRG state).",
      call. = FALSE
    )
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
      workers    = workers,
      strategy   = strategy,
      chunk_size = chunk_size,
      seed       = seed,
      packages   = packages,
      globals    = globals
    ),
    class = "genproc_parallel_spec"
  )
}


# Internal. Compute the strategy that genproc() will actually use
# given a parallel spec, applying the auto-default rule:
# `workers` passed without `strategy` => multisession. Returns NULL
# in power-user mode (no workers, no strategy → defer to the
# caller's current future::plan()). Used both by execute_cases (to
# install the temporary plan) and by capture_reproducibility (to
# record what was actually applied, alongside the user's request).
resolve_effective_strategy <- function(parallel) {
  if (is.null(parallel)) return(NULL)
  if (!is.null(parallel$strategy)) return(parallel$strategy)
  if (!is.null(parallel$workers))  return("multisession")
  NULL
}
