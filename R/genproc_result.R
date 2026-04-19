# S3 class: genproc_result
#
# Methods for the object returned by genproc().
# The class exists primarily for forward compatibility: future layers
# (parallel, non-blocking) will extend it with new fields and methods
# while preserving the existing interface.


#' Print a genproc result
#'
#' Displays a concise summary of the run: number of cases, success
#' rate, total duration, and status.
#'
#' For non-blocking results, the status is queried *live* from the
#' attached future (via [status()]) rather than read from the stored
#' field, which is frozen at the moment the skeleton is created. This
#' way, repeated `print(x)` calls reflect the actual progress of the
#' background run. Numeric fields stay `(pending)` until [await()] is
#' called to materialize the result.
#'
#' @param x A `genproc_result` object.
#' @param ... Ignored (present for S3 method consistency).
#' @return `x`, invisibly.
#'
#' @export
print.genproc_result <- function(x, ...) {
  live_status  <- status(x)
  has_future   <- !is.null(attr(x, "future"))
  materialized <- !is.null(x$n_success) && !is.null(x$n_error)

  cat("genproc result\n")
  cat("  Status :", live_status, "\n")

  if (materialized) {
    n_total <- x$n_success + x$n_error
    cat("  Cases  :", n_total,
        "(", x$n_success, "ok,", x$n_error, "error )\n")
  } else {
    cat("  Cases  : (pending)\n")
  }

  if (is.numeric(x$duration_total_secs)) {
    cat("  Duration:", round(x$duration_total_secs, 2), "secs\n")
  } else {
    cat("  Duration: (pending)\n")
  }

  if (identical(x$status, "error") && !is.null(x$error_message)) {
    cat("  Error  :", x$error_message, "\n")
  }

  # Hint: future has resolved but skeleton has not been materialized.
  if (has_future && !materialized && identical(live_status, "done")) {
    cat("  -> call await(x) to materialize the result.\n")
  }

  invisible(x)
}
