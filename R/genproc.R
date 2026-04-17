#' Run a function over a mask with mandatory logging and reproducibility
#'
#' This is the central function of the genproc package. It takes a
#' function and an iteration mask (data.frame), calls the function once
#' per row of the mask, and returns a structured result with:
#' - a log data.frame (one row per case, with success/error/traceback/timing)
#' - reproducibility information (R version, packages, environment, parallel spec)
#' - the exact mask used
#' - stable case IDs linking log rows to mask rows
#'
#' The *logged* and *reproducibility* layers are always active and
#' cannot be disabled. The *parallel* layer is optional: pass a
#' [parallel_spec()] to `parallel` to enable it.
#'
#' @param f A function to apply to each row of the mask. Each formal
#'   of `f` should correspond to a column in `mask` (or have a default
#'   value). Can be produced by [from_example_to_function()] or written
#'   by hand.
#' @param mask A data.frame where each row is an iteration case and
#'   each column is a parameter value. Can be produced by
#'   [from_function_to_mask()] and expanded by the user.
#' @param f_mapping Optional named character vector to rename `f`'s
#'   parameters before execution. Passed to [rename_function_params()].
#'   Names are current parameter names, values are new names matching
#'   `mask` columns.
#' @param parallel `NULL` (default, sequential execution) or a
#'   `genproc_parallel_spec` object produced by [parallel_spec()].
#'   When supplied, cases are dispatched to workers via
#'   [future.apply::future_lapply()].
#' @param nonblocking `NULL` (default, synchronous call) or a
#'   `genproc_nonblocking_spec` object produced by
#'   [nonblocking_spec()]. When supplied, `genproc()` returns
#'   immediately with a `genproc_result` of status `"running"`, and
#'   the run continues in a background future. Use [status()] to
#'   poll the state and [await()] to block until resolution. Can be
#'   combined with `parallel` — the non-blocking wrapper envelops
#'   the parallel dispatch.
#'
#' @return An object of class `genproc_result` (a named list) with
#'   components:
#'   \describe{
#'     \item{log}{A data.frame with one row per case. Contains all
#'       parameter values, plus `case_id`, `success`, `error_message`,
#'       `traceback`, and `duration_secs`.}
#'     \item{reproducibility}{A list of environment information
#'       captured at run start (R version, packages, OS, locale,
#'       timezone, mask snapshot, parallel spec if any).
#'       See `capture_reproducibility()`.}
#'     \item{n_success}{Integer, number of successful cases.}
#'     \item{n_error}{Integer, number of failed cases.}
#'     \item{duration_total_secs}{Numeric, total wall-clock time for
#'       the entire run.}
#'     \item{status}{Character. `"done"` for synchronous runs.
#'       Future execution layers (non-blocking) may return
#'       `"running"` or `"error"` here.}
#'   }
#'
#'   The `genproc_result` class is designed for forward compatibility.
#'   Existing fields (`log`, `reproducibility`, `n_success`, `n_error`,
#'   `duration_total_secs`) are guaranteed stable. Future versions may
#'   add new fields (e.g. `worker_id` in the log for parallel runs,
#'   or `collect()`/`poll()` methods for non-blocking execution) but
#'   will never remove or rename existing ones.
#'
#' @details
#' ## Execution model
#'
#' Cases are executed **sequentially** in row order by default. Supply
#' `parallel = parallel_spec(...)` to dispatch them in parallel via
#' the \pkg{future} ecosystem. The logging and reproducibility layers
#' remain active in both modes; the parallel layer is strictly
#' additive.
#'
#' Parallel execution preserves the mask row order in the resulting
#' `log` data.frame, regardless of the order in which workers return.
#'
#' Parallel execution requires \pkg{genproc} to be installed (not only
#' loaded via `devtools::load_all()`) on each worker, because the
#' logging layer serializes closures whose environments reference
#' genproc internals. The only exception is
#' `parallel_spec(strategy = "sequential")`, which runs in the
#' current process and needs nothing extra — this is the recommended
#' mode for deterministic testing.
#'
#' ## Error handling
#'
#' Errors in individual cases do **not** stop the run. Each case is
#' wrapped with [add_trycatch_logrow()], which captures the error
#' message and the real traceback (via `withCallingHandlers`). The
#' run continues with the next case. This holds identically in
#' sequential and parallel mode.
#'
#' ## Case IDs
#'
#' Each row of the mask receives a `case_id` (currently index-based:
#' `case_0001`, `case_0002`, ...). This ID appears in the log and
#' can be used for replay, monitoring, and cross-referencing.
#'
#' ## Parameter matching
#'
#' The mask does not need to contain a column for every parameter of
#' `f`. Parameters not present in the mask will use their default
#' values. However, parameters without defaults that are also missing
#' from the mask will cause an error before execution starts.
#'
#' Extra columns in the mask (not matching any parameter) are silently
#' ignored.
#'
#' @examples
#' # Sequential (default)
#' result <- genproc(
#'   f = function(x, y) x + y,
#'   mask = data.frame(x = c(1, 2, 3), y = c(10, 20, 30))
#' )
#' result$log
#'
#' # Parallel — uses whatever future::plan() is currently set
#' \dontrun{
#'   future::plan(future::multisession, workers = 4)
#'   result <- genproc(
#'     f = slow_function,
#'     mask = big_mask,
#'     parallel = parallel_spec(seed = 42L)
#'   )
#' }
#'
#' # One-off parallel call, temporary plan, restored on exit
#' \dontrun{
#'   result <- genproc(
#'     f = my_fn,
#'     mask = my_mask,
#'     parallel = parallel_spec(strategy = "multisession", workers = 4)
#'   )
#' }
#'
#' # Non-blocking: return immediately, keep the console, collect later
#' \dontrun{
#'   job <- genproc(
#'     f = slow_fn,
#'     mask = big_mask,
#'     nonblocking = nonblocking_spec()
#'   )
#'   status(job)              # "running" or "done"
#'   job <- await(job)        # blocks until resolution
#'   job$log
#' }
#'
#' # Parallel + non-blocking composed
#' \dontrun{
#'   job <- genproc(
#'     f = slow_fn,
#'     mask = big_mask,
#'     parallel    = parallel_spec(workers = 6),
#'     nonblocking = nonblocking_spec()
#'   )
#'   # do other work here
#'   job <- await(job)
#' }
#'
#' @export
genproc <- function(f, mask, f_mapping = NULL, parallel = NULL,
                    nonblocking = NULL) {
  # --- Input validation ---
  if (!is.function(f)) {
    stop("`f` must be a function.", call. = FALSE)
  }
  if (!is.data.frame(mask)) {
    stop("`mask` must be a data.frame.", call. = FALSE)
  }
  if (nrow(mask) == 0) {
    stop("`mask` must have at least one row.", call. = FALSE)
  }
  if (!is.null(parallel) && !inherits(parallel, "genproc_parallel_spec")) {
    stop(
      "`parallel` must be NULL or a `genproc_parallel_spec` object ",
      "produced by parallel_spec().",
      call. = FALSE
    )
  }
  if (!is.null(nonblocking) &&
      !inherits(nonblocking, "genproc_nonblocking_spec")) {
    stop(
      "`nonblocking` must be NULL or a `genproc_nonblocking_spec` ",
      "object produced by nonblocking_spec().",
      call. = FALSE
    )
  }

  # --- Optional parameter rename ---
  if (!is.null(f_mapping)) {
    f <- rename_function_params(f, f_mapping)
  }

  # --- Validate mask against function parameters ---
  f_params <- names(formals(f))
  mask_cols <- names(mask)

  params_from_mask <- intersect(f_params, mask_cols)

  params_missing <- setdiff(f_params, mask_cols)
  fmls <- formals(f)
  for (p in params_missing) {
    has_default <- tryCatch(
      {
        v <- fmls[[p]]
        !(is.symbol(v) && !nzchar(as.character(v)))
      },
      error = function(e) FALSE
    )
    if (!has_default) {
      stop(
        "Parameter `", p, "` has no default value and is not a column ",
        "in `mask`. Either add a `", p, "` column to the mask or give ",
        "`f` a default value for this parameter.",
        call. = FALSE
      )
    }
  }

  # --- Wrap function with logging (mandatory layer) ---
  f_logged <- add_trycatch_logrow(f)

  # --- Generate case IDs ---
  case_ids <- generate_case_ids(mask)

  # --- Capture reproducibility (mandatory layer) ---
  repro <- capture_reproducibility(mask,
                                   parallel    = parallel,
                                   nonblocking = nonblocking)

  # --- Build per-case argument lists ---
  args_list <- lapply(seq_len(nrow(mask)), function(i) {
    as.list(mask[i, params_from_mask, drop = FALSE])
  })

  # --- Sync path ---------------------------------------------------------
  if (is.null(nonblocking)) {
    run_start <- proc.time()[["elapsed"]]
    log_rows  <- execute_cases(f_logged, args_list, parallel)
    run_end   <- proc.time()[["elapsed"]]

    payload <- assemble_result_payload(log_rows, case_ids,
                                       run_end - run_start)

    return(structure(
      list(
        log                 = payload$log,
        reproducibility     = repro,
        n_success           = payload$n_success,
        n_error             = payload$n_error,
        duration_total_secs = payload$duration_total_secs,
        status              = "done"
      ),
      class = "genproc_result"
    ))
  }

  # --- Non-blocking path -------------------------------------------------
  # Temporarily install the wrapper plan if a strategy was given; we
  # restore it on exit. `future::future()` captures the active plan at
  # creation time, so the restore below does not affect the submitted
  # future.
  if (!is.null(nonblocking$strategy)) {
    oplan <- future::plan(nonblocking$strategy)
    on.exit(future::plan(oplan), add = TRUE)
  }

  # Packages the worker must attach. `"sequential"` runs in-process and
  # needs nothing extra; any real async backend needs `genproc` so that
  # the two internal helpers resolved below can execute on the worker.
  is_seq_wrapper <- identical(nonblocking$strategy, "sequential")
  wrapper_pkgs   <- if (is_seq_wrapper) {
    nonblocking$packages
  } else {
    unique(c("genproc", nonblocking$packages))
  }

  # Resolve internal helpers through getFromNamespace() rather than
  # `genproc:::name`. Two reasons:
  #   - R CMD check flags `pkg:::` calls to the package's own
  #     namespace with a NOTE; getFromNamespace() is the canonical
  #     alternative.
  #   - It also gives us a plain function binding that future's
  #     globals detection picks up cleanly.
  execute_cases_fn <- utils::getFromNamespace("execute_cases",
                                               "genproc")
  assemble_fn      <- utils::getFromNamespace("assemble_result_payload",
                                               "genproc")

  fut <- future::future(
    {
      run_start <- proc.time()[["elapsed"]]
      log_rows  <- execute_cases_fn(f_logged, args_list, parallel)
      run_end   <- proc.time()[["elapsed"]]
      assemble_fn(log_rows, case_ids, run_end - run_start)
    },
    seed     = TRUE,
    globals  = nonblocking$globals,
    packages = wrapper_pkgs
  )

  skeleton <- structure(
    list(
      log                 = NULL,
      reproducibility     = repro,
      n_success           = NULL,
      n_error             = NULL,
      duration_total_secs = NULL,
      status              = "running"
    ),
    class = "genproc_result"
  )
  attr(skeleton, "future") <- fut
  skeleton
}


# Internal. Take a list of one-row log data.frames (as produced by
# execute_cases), the case_ids vector, and the total wall-clock
# duration, and produce the named list that becomes / fills a
# genproc_result: `log` (well-ordered columns), `n_success`,
# `n_error`, `duration_total_secs`.
#
# Used by both the synchronous path and the non-blocking future body,
# so that the assembled output is bit-identical between the two.
assemble_result_payload <- function(log_rows, case_ids, total_duration) {
  for (i in seq_along(log_rows)) {
    log_rows[[i]]$case_id <- case_ids[i]
  }

  log <- do.call(rbind, log_rows)

  meta_cols  <- c("case_id", "success", "error_message",
                  "traceback", "duration_secs")
  param_cols <- setdiff(names(log), meta_cols)
  log <- log[, c("case_id", param_cols,
                 "success", "error_message",
                 "traceback", "duration_secs"),
             drop = FALSE]

  list(
    log                 = log,
    n_success           = sum(log$success),
    n_error             = sum(!log$success),
    duration_total_secs = total_duration
  )
}


# Internal dispatcher.
# Runs `f_logged` over `args_list`, sequentially if `parallel` is NULL,
# otherwise through future.apply with the fields of `parallel`.
# Returns a list of one-row data.frames, in input order.
execute_cases <- function(f_logged, args_list, parallel) {
  if (is.null(parallel)) {
    # --- Sequential path ---
    return(lapply(args_list, function(args) do.call(f_logged, args)))
  }

  # --- Parallel path ---
  # Requires future and future.apply (declared in Imports).

  # Effective strategy. If the user passed `workers` but no `strategy`,
  # default to "multisession" — the portable, user-friendly choice.
  # Without this default, `workers` would be silently ignored whenever
  # the caller's current future::plan() is the session default
  # (sequential), which is the most common UX footgun in this layer.
  effective_strategy <- parallel$strategy
  if (is.null(effective_strategy) && !is.null(parallel$workers)) {
    effective_strategy <- "multisession"
  }

  # Temporarily install a plan if we have a strategy to install;
  # restore on exit. If `effective_strategy` is NULL, the caller's
  # current plan is used unchanged (power-user mode).
  if (!is.null(effective_strategy)) {
    if (effective_strategy == "sequential" || is.null(parallel$workers)) {
      oplan <- future::plan(effective_strategy)
    } else {
      oplan <- future::plan(effective_strategy, workers = parallel$workers)
    }
    on.exit(future::plan(oplan), add = TRUE)
  }

  # Packages to attach on each worker. For non-sequential strategies we
  # *must* ensure `genproc` is loaded on the worker so that the logged
  # closure's environment (which references clean_traceback via the
  # genproc namespace) resolves correctly after deserialization.
  is_sequential <- !is.null(parallel$strategy) &&
    parallel$strategy == "sequential"
  fpkgs <- if (is_sequential) {
    parallel$packages
  } else {
    unique(c("genproc", parallel$packages))
  }

  future.apply::future_lapply(
    X                 = args_list,
    FUN               = function(args) do.call(f_logged, args),
    future.seed       = parallel$seed,
    future.chunk.size = parallel$chunk_size,
    future.globals    = parallel$globals,
    future.packages   = fpkgs
  )
}
