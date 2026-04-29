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
#' When the parallel layer was used and startup overhead clearly
#' dominated the run, the print method emits a `Note` hinting at
#' the issue — a pattern that often surprises users on small
#' workloads. Two metrics depending on whether `workers` is known:
#' parallel efficiency (`(cumulative / workers) / wall`) below 50%
#' when `workers` is supplied, or `wall > cumulative * 1.2` in
#' power-user mode (workers unknown). Both require `wall > 0.5s` to
#' avoid noise on very short runs.
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

  # When the future has resolved but the user has not called await(),
  # the object's numeric fields are still NULL (R is pass-by-value —
  # the skeleton cannot self-update). We label this "done (not
  # collected)" so it doesn't read as a contradiction with the
  # (pending) Cases / Duration lines.
  status_label <- if (has_future && !materialized &&
                      identical(live_status, "done")) {
    "done (not collected)"
  } else {
    live_status
  }

  cat("genproc result\n")
  cat("  Status :", status_label, "\n")

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

  # Explicit, copy-pasteable hint using the user's actual variable
  # name where possible.
  if (has_future && !materialized && identical(live_status, "done")) {
    var_name <- tryCatch(deparse(substitute(x)),
                         error = function(e) "x")
    if (!nzchar(var_name) || length(var_name) != 1L) var_name <- "x"
    cat("  -> ", var_name, " <- await(", var_name, ")\n", sep = "")
  }

  # F12 — Hint when parallel was used but startup overhead clearly
  # dominated the run.
  #
  # Two metrics, depending on whether the user passed `workers`:
  #
  # (a) workers known: parallel efficiency =
  #       (cumulative_work / workers) / wall_clock.
  #     Below 50% efficiency, parallel did not amortize its startup
  #     cost. Catches the typical case of `parallel_spec(workers=4)`
  #     on a small workload where each case takes a few ms.
  #
  # (b) workers unknown (power-user mode, plan set by the caller):
  #     fallback to wall > cumulative * 1.2. Less precise but still
  #     catches the cases where parallel was strictly slower than a
  #     hypothetical sequential run.
  #
  # In both cases we require wall > 0.5s to avoid noise on very
  # short runs where measurement granularity dominates.
  if (materialized &&
      !is.null(x$reproducibility) &&
      !is.null(x$reproducibility$parallel) &&
      is.numeric(x$duration_total_secs) &&
      !is.null(x$log) &&
      "duration_secs" %in% names(x$log)) {
    total_work <- sum(x$log$duration_secs, na.rm = TRUE)
    wall       <- x$duration_total_secs
    workers    <- x$reproducibility$parallel$workers

    # Compute the trigger.
    fire <- FALSE
    detail_line <- ""
    if (wall > 0.5 && total_work > 0) {
      if (is.numeric(workers) && length(workers) == 1L && workers >= 2L) {
        ideal      <- total_work / workers
        efficiency <- ideal / wall
        if (efficiency < 0.5) {
          fire <- TRUE
          detail_line <- sprintf(
            "            wall-clock %.2fs vs ideal %.2fs (%d workers, %.0f%% efficiency)\n",
            wall, ideal, workers, 100 * efficiency)
        }
      } else if (wall > total_work * 1.2) {
        fire <- TRUE
        detail_line <- sprintf(
          "            wall-clock %.2fs vs cumulative work %.2fs\n",
          wall, total_work)
      }
    }

    if (fire) {
      cat("  Note    : parallel startup dominated this run\n")
      cat(detail_line)
      cat("            -> consider sequential for short workloads\n")
    }
  }

  invisible(x)
}
