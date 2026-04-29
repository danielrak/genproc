# Inspection helpers on a genproc_result.
#
# Two complementary surfaces:
#   * `errors(result)` — programmatic handle: returns the subset of
#     the log corresponding to failed cases. The user can then filter,
#     join, or feed it to `rerun_failed()`.
#   * `summary(result)` — human-readable digest: counts, success rate,
#     duration stats, top error messages by occurrence.
#
# These helpers do NOT replace direct access to `result$log`. They
# document the most common patterns, so the user does not have to
# rebuild them every time.


#' Subset a genproc result to its failed cases
#'
#' Returns the rows of `result$log` corresponding to cases where
#' `success == FALSE`. The columns are exactly those of
#' `result$log` (case_id, mask parameters, success, error_message,
#' traceback, duration_secs).
#'
#' @param x A `genproc_result` produced by [genproc()].
#' @param ... Unused, for future extensions.
#'
#' @return A data.frame with one row per failed case. Empty
#'   data.frame (with the same columns) if there are no failures.
#'   Returns `NULL` (with a message) if the run is non-blocking and
#'   has not been materialized yet.
#'
#' @examples
#' result <- genproc(
#'   f = function(x) if (x %% 2 == 0) x / 0 else x,
#'   mask = data.frame(x = 1:6)
#' )
#' errors(result)[, c("case_id", "x", "error_message")]
#'
#' @seealso [rerun_failed()], [summary.genproc_result()]
#' @export
errors <- function(x, ...) {
  UseMethod("errors")
}

#' @rdname errors
#' @export
errors.genproc_result <- function(x, ...) {
  if (is.null(x$log)) {
    message("Result is not materialized yet. ",
            "Call await() before inspecting errors.")
    return(invisible(NULL))
  }
  x$log[!x$log$success, , drop = FALSE]
}


#' Summarise a genproc result
#'
#' Produces a compact digest of the run: status, success rate,
#' duration stats, and the top recurring error messages. Useful
#' on runs with a lot of cases where the raw log is too noisy to
#' eyeball.
#'
#' @param object A `genproc_result` produced by [genproc()].
#' @param top_errors Integer. Maximum number of distinct error
#'   messages to include in the summary, ranked by occurrence.
#'   Default 10.
#' @param ... Unused, for future extensions.
#'
#' @return An object of class `genproc_result_summary` (a list)
#'   with components:
#'   \describe{
#'     \item{materialized}{Logical. `FALSE` if the run is
#'       non-blocking and has not been collected via [await()].
#'       In that case the other fields are `NA`.}
#'     \item{status}{Character, mirrors `result$status`.}
#'     \item{n_cases}{Integer.}
#'     \item{n_success, n_error}{Integers.}
#'     \item{success_rate}{Numeric in 0..1.}
#'     \item{duration_total_secs}{Numeric, wall-clock total.}
#'     \item{duration_stats}{List with `total`, `mean`, `max`,
#'       and `slowest_case_id`. `NULL` if no per-case durations.}
#'     \item{top_errors}{data.frame with columns `error_message` and
#'       `count`, sorted by count descending. Trimmed to
#'       `top_errors` rows.}
#'   }
#'
#' @examples
#' result <- genproc(
#'   f = function(x) {
#'     if (x %% 2 == 0) stop("even")
#'     if (x %% 3 == 0) stop("multiple of three")
#'     x
#'   },
#'   mask = data.frame(x = 1:12)
#' )
#' summary(result)
#'
#' @seealso [errors()], [rerun_failed()]
#' @export
summary.genproc_result <- function(object, top_errors = 10L, ...) {
  if (!is.numeric(top_errors) || length(top_errors) != 1L ||
      is.na(top_errors) || top_errors < 0) {
    stop("`top_errors` must be a non-negative integer.", call. = FALSE)
  }
  top_errors <- as.integer(top_errors)

  log <- object$log
  if (is.null(log)) {
    return(structure(
      list(
        materialized        = FALSE,
        status              = if (is.null(object$status)) NA_character_
                              else object$status,
        n_cases             = NA_integer_,
        n_success           = NA_integer_,
        n_error             = NA_integer_,
        success_rate        = NA_real_,
        duration_total_secs = NA_real_,
        duration_stats      = NULL,
        top_errors          = data.frame(
          error_message = character(0),
          count         = integer(0),
          stringsAsFactors = FALSE
        )
      ),
      class = "genproc_result_summary"
    ))
  }

  n_cases <- nrow(log)
  err_rows <- log[!log$success, , drop = FALSE]

  # Top errors by recurrence.
  if (nrow(err_rows) > 0L) {
    tab <- sort(table(err_rows$error_message), decreasing = TRUE)
    keep <- seq_len(min(length(tab), top_errors))
    top_err_df <- data.frame(
      error_message = names(tab)[keep],
      count         = as.integer(tab)[keep],
      stringsAsFactors = FALSE
    )
  } else {
    top_err_df <- data.frame(
      error_message = character(0),
      count         = integer(0),
      stringsAsFactors = FALSE
    )
  }

  # Per-case duration stats.
  durs <- log$duration_secs
  durs <- durs[!is.na(durs)]
  if (length(durs) > 0L) {
    slowest_idx <- which.max(log$duration_secs)
    duration_stats <- list(
      total            = sum(durs),
      mean             = mean(durs),
      max              = max(durs),
      slowest_case_id  = log$case_id[slowest_idx]
    )
  } else {
    duration_stats <- NULL
  }

  structure(
    list(
      materialized        = TRUE,
      status              = object$status,
      n_cases             = n_cases,
      n_success           = object$n_success,
      n_error             = object$n_error,
      success_rate        = if (n_cases > 0L)
                              object$n_success / n_cases else NA_real_,
      duration_total_secs = object$duration_total_secs,
      duration_stats      = duration_stats,
      top_errors          = top_err_df
    ),
    class = "genproc_result_summary"
  )
}


#' Print method for genproc_result_summary
#'
#' @param x A `genproc_result_summary` produced by
#'   [summary.genproc_result()].
#' @param ... Unused, for S3 method consistency.
#' @return `x`, invisibly.
#'
#' @export
print.genproc_result_summary <- function(x, ...) {
  cat("genproc result summary\n")

  if (isFALSE(x$materialized)) {
    cat("  Status     : ", x$status, " (not materialized)\n", sep = "")
    cat("  -> call await() to materialize before summarising.\n")
    return(invisible(x))
  }

  cat(sprintf("  Status     : %s\n", x$status))
  cat(sprintf("  Cases      : %d (%d ok, %d error)\n",
              x$n_cases, x$n_success, x$n_error))
  if (!is.na(x$success_rate)) {
    cat(sprintf("  Success    : %.0f%%\n", 100 * x$success_rate))
  }
  if (is.numeric(x$duration_total_secs) &&
      !is.na(x$duration_total_secs)) {
    cat(sprintf("  Total time : %.2fs\n", x$duration_total_secs))
  }
  if (!is.null(x$duration_stats)) {
    cat(sprintf(
      "  Per case   : mean %.3fs, max %.3fs (slowest: %s)\n",
      x$duration_stats$mean,
      x$duration_stats$max,
      x$duration_stats$slowest_case_id))
  }

  if (nrow(x$top_errors) > 0L) {
    cat("\nTop errors:\n")
    for (i in seq_len(nrow(x$top_errors))) {
      msg <- x$top_errors$error_message[i]
      # Trim very long error messages to keep the summary scannable.
      if (nchar(msg) > 80L) msg <- paste0(substr(msg, 1L, 77L), "...")
      cat(sprintf("  %3dx  %s\n", x$top_errors$count[i], msg))
    }
  }

  invisible(x)
}
