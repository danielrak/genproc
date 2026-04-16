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
#' @param x A `genproc_result` object.
#' @param ... Ignored (present for S3 method consistency).
#' @return `x`, invisibly.
#'
#' @export
print.genproc_result <- function(x, ...) {
  n_total <- x$n_success + x$n_error

  cat("genproc result\n")
  cat("  Status :", x$status, "\n")
  cat("  Cases  :", n_total,
      "(", x$n_success, "ok,", x$n_error, "error )\n")
  cat("  Duration:", round(x$duration_total_secs, 2), "secs\n")

  invisible(x)
}
