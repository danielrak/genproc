#' Run a function over a mask with mandatory logging and reproducibility
#'
#' This is the central function of the genproc package. It takes a
#' function and an iteration mask (data.frame), calls the function once
#' per row of the mask, and returns a structured result with:
#' - a log data.frame (one row per case, with success/error/traceback/timing)
#' - reproducibility information (R version, packages, environment)
#' - the exact mask used
#' - stable case IDs linking log rows to mask rows
#'
#' The *logged* and *reproducibility* layers are always active and
#' cannot be disabled.
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
#'
#' @return A list with components:
#'   \describe{
#'     \item{log}{A data.frame with one row per case. Contains all
#'       parameter values, plus `case_id`, `success`, `error_message`,
#'       `traceback`, and `duration_secs`.}
#'     \item{reproducibility}{A list of environment information
#'       captured at run start (R version, packages, OS, locale,
#'       timezone, mask snapshot). See `capture_reproducibility()`.}
#'     \item{n_success}{Integer, number of successful cases.}
#'     \item{n_error}{Integer, number of failed cases.}
#'     \item{duration_total_secs}{Numeric, total wall-clock time for
#'       the entire run.}
#'   }
#'
#' @details
#' ## Execution model (v0.1)
#'
#' Cases are executed **sequentially** in row order. Parallel and
#' non-blocking execution will be added in future versions as
#' composable, opt-in layers.
#'
#' ## Error handling
#'
#' Errors in individual cases do **not** stop the run. Each case is
#' wrapped with [add_trycatch_logrow()], which captures the error
#' message and the real traceback (via `withCallingHandlers`). The
#' run continues with the next case.
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
#' # Simple example: add two numbers
#' result <- genproc(
#'   f = function(x, y) x + y,
#'   mask = data.frame(x = c(1, 2, 3), y = c(10, 20, 30))
#' )
#' result$log
#' result$n_success
#'
#' # With the full pipeline:
#' my_val <- 100
#' fn <- from_example_to_function(expression(my_val * 2))
#' fn <- rename_function_params(fn, c(param_1 = "value"))
#' mask <- data.frame(value = c(1, 5, 10))
#' result <- genproc(fn, mask)
#'
#' # Using f_mapping (rename at call time):
#' fn2 <- from_example_to_function(expression(my_val * 2))
#' result2 <- genproc(fn2, mask, f_mapping = c(param_1 = "value"))
#'
#' @export
genproc <- function(f, mask, f_mapping = NULL) {
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

  # --- Optional parameter rename ---
  if (!is.null(f_mapping)) {
    f <- rename_function_params(f, f_mapping)
  }

  # --- Validate mask against function parameters ---
  f_params <- names(formals(f))
  mask_cols <- names(mask)

  # Determine which params will be supplied from the mask
  params_from_mask <- intersect(f_params, mask_cols)

  # Params not in mask must have defaults
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
  repro <- capture_reproducibility(mask)

  # --- Sequential execution ---
  run_start <- proc.time()[["elapsed"]]
  log_rows <- vector("list", nrow(mask))

  for (i in seq_len(nrow(mask))) {
    # Extract arguments from mask (only columns that match params)
    args <- as.list(mask[i, params_from_mask, drop = FALSE])

    # Call the logged function
    log_rows[[i]] <- do.call(f_logged, args)

    # Attach case_id
    log_rows[[i]]$case_id <- case_ids[i]
  }

  run_end <- proc.time()[["elapsed"]]

  # --- Assemble log ---
  log <- do.call(rbind, log_rows)

  # Reorder columns: case_id first, then params, then meta
  meta_cols <- c("case_id", "success", "error_message",
                 "traceback", "duration_secs")
  param_cols <- setdiff(names(log), meta_cols)
  log <- log[, c("case_id", param_cols,
                  "success", "error_message",
                  "traceback", "duration_secs"),
             drop = FALSE]

  # --- Summary ---
  n_success <- sum(log$success)
  n_error <- sum(!log$success)

  # --- Return structured result ---
  list(
    log                = log,
    reproducibility    = repro,
    n_success          = n_success,
    n_error            = n_error,
    duration_total_secs = run_end - run_start
  )
}
