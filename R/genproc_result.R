# S3 class: genproc_result
#
# Methods for the object returned by genproc().
# The class exists primarily for forward compatibility: future layers
# (parallel, non-blocking) will extend it with new fields and methods
# while preserving the existing interface.


#' Print a genproc result
#'
#' Displays a structured summary of the run: status, timestamp,
#' execution mode, case counts, total duration, and an actionable
#' hint when relevant.
#'
#' For non-blocking results, the status is queried *live* from the
#' attached future via [status()] rather than read from the stored
#' field. Repeated `print(x)` calls therefore reflect the actual
#' progress of the background run. `status()` distinguishes
#' `"done"` (the future resolved successfully) from `"error"` (the
#' wrapper future itself crashed). Numeric fields stay `(pending)`
#' until [await()] is called to materialize the result.
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

  # Status label distinguishes "done (not collected)" from "error
  # (not collected)" so the user can react before calling await().
  status_label <- if (has_future && !materialized) {
    if (identical(live_status, "done"))  "done (not collected)"
    else if (identical(live_status, "error")) "error (not collected)"
    else live_status
  } else {
    live_status
  }

  cat("genproc result\n")
  cat("  Status   :", status_label, "\n")

  # Timestamp from the reproducibility snapshot (captured at run
  # start). Only shown when the snapshot is available.
  ts <- x$reproducibility$timestamp
  if (inherits(ts, "POSIXt")) {
    cat("  Started  :", format(ts, "%Y-%m-%d %H:%M:%S %Z"), "\n")
  }

  # Execution mode: sequential / parallel x N / non-blocking /
  # non-blocking + parallel x N. Read from the repro snapshot.
  mode_str <- format_execution_mode(x)
  if (!is.null(mode_str)) {
    cat("  Mode     :", mode_str, "\n")
  }

  if (materialized) {
    n_total <- x$n_success + x$n_error
    cat("  Cases    :", n_total,
        "(", x$n_success, "ok,", x$n_error, "error )\n")
  } else {
    cat("  Cases    : (pending)\n")
  }

  if (is.numeric(x$duration_total_secs)) {
    cat("  Duration :", round(x$duration_total_secs, 2), "secs\n")
  } else {
    cat("  Duration : (pending)\n")
  }

  if (identical(x$status, "error") && !is.null(x$error_message)) {
    cat("  Error    :", x$error_message, "\n")
  }

  # Actionable hints. Resolve the user's variable name once for
  # copy-pasteable suggestions.
  var_name <- tryCatch(deparse(substitute(x)),
                       error = function(e) "x")
  if (!nzchar(var_name) || length(var_name) != 1L) var_name <- "x"

  if (has_future && !materialized && identical(live_status, "done")) {
    cat("  -> ", var_name, " <- await(", var_name, ")\n", sep = "")
  }
  if (has_future && !materialized && identical(live_status, "error")) {
    cat("  -> ", var_name, " <- await(", var_name,
        ")  # to retrieve the error message\n", sep = "")
  }
  # When materialized with errors, point to the inspection helpers.
  if (materialized && isTRUE(x$n_error > 0L)) {
    cat("  -> errors(", var_name, "), summary(", var_name, ")\n", sep = "")
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


# Internal: render the "Mode" line of print.genproc_result.
# Reads from x$reproducibility$parallel and $nonblocking. Returns
# NULL when the snapshot is not available (no Mode line printed).
format_execution_mode <- function(x) {
  repro <- x$reproducibility
  if (is.null(repro)) return(NULL)

  par_spec <- repro$parallel
  nb_spec  <- repro$nonblocking

  par_part <- if (is.null(par_spec)) {
    "sequential"
  } else {
    workers <- par_spec$workers
    strategy <- par_spec$strategy
    parts <- character()
    if (!is.null(strategy) && nzchar(strategy)) parts <- c(parts, strategy)
    parts <- c(parts, "parallel")
    label <- paste(parts, collapse = " ")
    if (is.numeric(workers) && length(workers) == 1L && !is.na(workers)) {
      sprintf("%s (%d workers)", label, as.integer(workers))
    } else {
      label
    }
  }

  if (is.null(nb_spec)) {
    par_part
  } else {
    paste0("non-blocking + ", par_part)
  }
}
