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
#' @param track_inputs Logical. When `TRUE` (default), genproc detects
#'   columns of `mask` that reference input files and records their
#'   size + mtime in `result$reproducibility$inputs`. Use [diff_inputs()]
#'   to compare two runs and detect silent input drift. Set to `FALSE`
#'   to skip input tracking entirely.
#' @param input_cols `NULL` (default) or a character vector of mask
#'   column names. When supplied, the heuristic detection is bypassed
#'   and exactly these columns are tracked. Paths that do not exist
#'   at capture time are recorded with `NA` size/mtime and a warning
#'   is emitted. Mutually exclusive with `skip_input_cols`.
#' @param skip_input_cols `NULL` (default) or a character vector of
#'   mask column names to exclude from heuristic detection. Useful
#'   when a label column happens to match an existing file. Mutually
#'   exclusive with `input_cols`.
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
#' ## Composing parallel and non-blocking
#'
#' When both `parallel` and `nonblocking` are supplied, the
#' non-blocking wrapper envelops the parallel dispatch (one outer
#' future submits the run, inner workers process the cases). On
#' platforms where the wrapper subprocess R inherits a restrictive
#' default for `getOption("mc.cores")` (typically 1 on Windows and in
#' some RStudio configurations), `parallelly` would otherwise refuse
#' to spawn the inner workers. `genproc()` works around this with
#' two surgical adjustments inside the wrapper subprocess, applied
#' *only* in the composed case and *only* when the user has not set
#' their own values:
#'
#' 1. Set `R_PARALLELLY_AVAILABLECORES_METHODS = "system"` so that
#'    `availableCores()` ignores the legacy `mc.cores` option and
#'    reports the true detected core count (lifts the hard-limit
#'    refusal).
#' 2. Raise `options(mc.cores)` from 1 to the system core count, so
#'    that `parallelly`'s soft-limit warning no longer fires with a
#'    misleading "only 1 CPU cores available" message.
#'
#' The calling session is never modified by either adjustment.
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
#' # Sequential run (the default). Returns immediately when done.
#' result <- genproc(
#'   f = function(x, y) x + y,
#'   mask = data.frame(x = c(1, 2, 3), y = c(10, 20, 30))
#' )
#' result$log
#'
#' # One-off parallel call: genproc installs a temporary multisession
#' # plan and restores the previous one on exit.
#' \dontrun{
#'   result <- genproc(
#'     f = slow_function,
#'     mask = big_mask,
#'     parallel = parallel_spec(workers = 4)
#'   )
#' }
#'
#' # Non-blocking + parallel composed: launch in the background,
#' # keep the console, collect later with await().
#' \dontrun{
#'   job <- genproc(
#'     f = slow_function,
#'     mask = big_mask,
#'     parallel    = parallel_spec(workers = 6),
#'     nonblocking = nonblocking_spec()
#'   )
#'   status(job)         # "running" until the future resolves
#'   job <- await(job)   # blocks; idempotent on already-resolved jobs
#'   job$log
#' }
#'
#' @export
genproc <- function(f, mask, f_mapping = NULL, parallel = NULL,
                    nonblocking = NULL,
                    track_inputs = TRUE,
                    input_cols = NULL,
                    skip_input_cols = NULL) {
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
  if (!is.logical(track_inputs) || length(track_inputs) != 1L ||
      is.na(track_inputs)) {
    stop("`track_inputs` must be a single TRUE/FALSE.", call. = FALSE)
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

  # --- Capture input fingerprints (sub-layer of reproducibility) ---
  inputs <- capture_input_fingerprints(
    mask, case_ids,
    track           = track_inputs,
    input_cols      = input_cols,
    skip_input_cols = skip_input_cols
  )

  # --- Capture reproducibility (mandatory layer) ---
  repro <- capture_reproducibility(mask,
                                   parallel    = parallel,
                                   nonblocking = nonblocking,
                                   inputs      = inputs)

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
  # Install the requested plan if a strategy was given, but DO NOT
  # restore it on exit. `future::plan()` shuts down the previous
  # cluster's workers when switched, which would kill the multisession
  # worker running our just-submitted future and surface a
  # "Future was canceled" error at await() time.
  #
  # Instead, we stash the previous plan on the skeleton and let
  # `await()` restore it once the future has been collected.
  oplan <- NULL
  if (!is.null(nonblocking$strategy)) {
    oplan <- future::plan(nonblocking$strategy)
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
      # --- Auto-config for nested parallel composition --------------------
      # When the user composes parallel + non-blocking on a typical
      # Windows + RStudio session, parallelly's resolution inside this
      # wrapper subprocess R reaches the `mc.cores` method first and
      # finds 1 (the legacy default for `parallel::mclapply` which is a
      # no-op on Windows). The parallel layer then refuses to spawn
      # multiple workers because workers / 1 > the localhost hard
      # limit. The composed call fails for a reason unrelated to the
      # user's machine.
      #
      # We work around this by forcing parallelly to use only the
      # `system` method (true detected core count) inside the wrapper
      # subprocess, *only when a parallel layer is actually composed*
      # and *only when the user has not set their own preference*.
      # Setting Sys.setenv() here mutates only the wrapper subprocess
      # — the calling session is untouched.
      if (!is.null(parallel) &&
          !nzchar(Sys.getenv("R_PARALLELLY_AVAILABLECORES_METHODS"))) {
        Sys.setenv(R_PARALLELLY_AVAILABLECORES_METHODS = "system")
      }
      # parallelly's `checkNumberOfLocalWorkers` also consults
      # getOption("mc.cores") directly for its soft-limit warning,
      # independently of AVAILABLECORES_METHODS. When the wrapper
      # subprocess inherits mc.cores = 1 (or unset), the user gets a
      # warning ("only 1 CPU cores available... 200% load") that is
      # misleading once we have already lifted the hard limit. We
      # therefore raise mc.cores here. Note: `options(mc.cores = 1)`
      # in user code stores a double, not an integer, so we use a
      # permissive numeric comparison rather than `identical(.., 1L)`.
      # We override only when mc.cores is unset or pinned to 1 (the
      # restrictive defaults on Windows / legacy mclapply); we never
      # touch a value the user has deliberately raised.
      mc_current <- getOption("mc.cores")
      mc_is_restrictive <-
        is.null(mc_current) ||
        (is.numeric(mc_current) && length(mc_current) == 1L &&
         !is.na(mc_current) && mc_current <= 1)
      if (!is.null(parallel) && mc_is_restrictive) {
        n_cores <- tryCatch(
          parallel::detectCores(logical = TRUE),
          error = function(e) NA_integer_
        )
        if (!is.na(n_cores) && n_cores >= 2L) {
          options(mc.cores = n_cores)
        }
      }

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
  # oplan is NULL if no strategy was installed (power-user mode):
  # await() will see NULL and skip the plan restoration step.
  attr(skeleton, "oplan")  <- oplan
  # Shared environment between status() and await(). If status()
  # peeks the resolved future, it caches the result (or wrapper
  # error) here; await() then consumes from the cache instead of
  # calling future::value() a second time. Pass-by-reference
  # semantics of `environment` are exactly what we need for the
  # cross-call coordination R's pass-by-value would otherwise break.
  attr(skeleton, "shared_env") <- new.env(parent = emptyenv())
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
