# Wrap a function body with error handling and structured logging
#
# This module provides add_trycatch_logrow(), which takes a plain function
# and returns a new function whose body:
#   1. Captures arguments as a data.frame row
#   2. Records start/end time and elapsed duration
#   3. Executes the original body inside withCallingHandlers + tryCatch
#      so that on error the REAL traceback is captured (not lost by
#      tryCatch's stack unwinding)
#   4. Returns a one-row log data.frame with columns:
#      - all original arguments
#      - success (logical)
#      - error_message (character or NA)
#      - traceback (character or NA) — the formatted call stack at error
#      - duration_secs (numeric) — elapsed wall-clock seconds
#
# WHY withCallingHandlers + tryCatch (not tryCatch alone):
#   tryCatch unwinds the call stack before entering the error handler.
#   By that point, sys.calls() returns the handler's stack, not the
#   error's. withCallingHandlers observes the condition WHILE the
#   original stack is intact — we capture the traceback there, store it
#   in a local variable, then let the error propagate to an outer
#   tryCatch that builds the log row.


#' Wrap a function with error handling and a structured log row
#'
#' Takes a function and returns a modified version that:
#' - always returns a one-row data.frame (the "log row")
#' - captures errors without stopping, recording the error message
#'   and the **real** traceback (call stack at the point of failure)
#' - records wall-clock execution time
#'
#' @param f A function to wrap.
#' @return A function with the same formals as `f`, whose return value
#'   is a one-row data.frame with columns: all original arguments,
#'   `success` (logical), `error_message` (character or `NA`),
#'   `traceback` (character or `NA`), `duration_secs` (numeric).
#'
#' @details
#' ## Why not plain tryCatch?
#'
#' `tryCatch()` unwinds the call stack before entering the error handler.
#' This means `sys.calls()` inside a `tryCatch` error handler returns
#' the handler's own stack, not the stack that led to the error.
#'
#' This function uses `withCallingHandlers()` (which fires while the
#' original stack is still intact) to capture the traceback, then lets
#' the error propagate to an outer `tryCatch()` for control flow.
#'
#' ## Log row structure
#'
#' The returned data.frame always has one row. Columns:
#' - One column per formal argument of `f`, with the value passed
#' - `success`: `TRUE` if the body executed without error
#' - `error_message`: the error's `conditionMessage()`, or `NA`
#' - `traceback`: the formatted call stack at the error, or `NA`
#' - `duration_secs`: wall-clock seconds elapsed
#'
#' @examples
#' safe_sqrt <- add_trycatch_logrow(function(x) sqrt(x))
#' safe_sqrt(4)    # success = TRUE, duration_secs > 0
#' safe_sqrt("a")  # success = FALSE, error_message filled, traceback filled
#'
#' @export
add_trycatch_logrow <- function(f) {
  if (!is.function(f)) {
    stop("`f` must be a function.", call. = FALSE)
  }

  arg_names <- names(formals(f))
  old_body <- body(f)

  # Capture a direct reference to clean_traceback so it works
  # regardless of f's environment (which may not see the namespace).
  .__clean_tb_fn__ <- clean_traceback

  # Build the new body using bquote for hygiene.
  # Variables prefixed with .__ are internal and unlikely to collide
  # with user code.
  new_body <- bquote({
    # --- Capture arguments ---
    .__args__ <- as.list(environment())
    .__args__ <- .__args__[.(arg_names)]

    # --- Timing ---
    .__start__ <- proc.time()[["elapsed"]]

    # --- Error capture slots ---
    .__captured_error_msg__ <- NA_character_
    .__captured_traceback__ <- NA_character_

    # --- Execute with traceback capture ---
    .__result__ <- tryCatch(
      withCallingHandlers(
        {
          .(old_body)
        },
        error = function(.__e__) {
          # We are still inside the original call stack here.
          # Capture the traceback before tryCatch unwinds it.
          .__calls__ <- sys.calls()
          # Drop the error handler frame itself
          .__calls__ <- .__calls__[-length(.__calls__)]
          # Clean: filter out genproc internals, truncate long lines
          .__tb__ <- (.(.__clean_tb_fn__))(.__calls__)
          # Store into parent scope (the function body's environment)
          .__captured_error_msg__ <<- conditionMessage(.__e__)
          .__captured_traceback__ <<- .__tb__
          # Do NOT handle the condition — let it propagate to tryCatch
        }
      ),
      error = function(.__e__) {
        # tryCatch handler: error is now handled (execution continues).
        # We already captured everything in withCallingHandlers above.
        NULL
      }
    )

    # --- Timing ---
    .__end__ <- proc.time()[["elapsed"]]
    .__duration__ <- .__end__ - .__start__

    # --- Build log row ---
    .__success__ <- is.na(.__captured_error_msg__)

    # Build a one-row data.frame from arguments.
    # When there are no arguments, as.data.frame(list()) gives 0 rows,
    # so we need a fallback to ensure exactly 1 row.
    if (length(.__args__) > 0) {
      .__log__ <- as.data.frame(.__args__, stringsAsFactors = FALSE)
    } else {
      .__log__ <- data.frame(.row = 1L)[, -1L, drop = FALSE]
    }
    .__log__$success <- .__success__
    .__log__$error_message <- .__captured_error_msg__
    .__log__$traceback <- .__captured_traceback__
    .__log__$duration_secs <- .__duration__

    .__log__
  })

  body(f) <- new_body
  f
}
