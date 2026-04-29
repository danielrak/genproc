# Re-run only the cases that failed in a previous run.
#
# Sibling of `rerun_affected()`: same general pattern, different
# selection criterion (failed cases vs cases impacted by an input
# diff). Both filter the original mask down via case_ids and call
# genproc() on the subset. Kept as separate helpers for clarity at
# the API level — combining them under a single configurable
# `rerun()` is a possibility for a later release once we have more
# selection criteria.
#
# Implementation note: the case_id -> mask row mapping is the same
# parser used in `rerun_affected()` (index-based `case_NNNN`).
# Refactor candidate when a 3rd helper appears.


#' Re-run only the cases that failed
#'
#' Filters the original mask of `r0` down to the cases for which
#' `success == FALSE` and re-runs `genproc()` on that subset. Useful
#' when a transient external problem caused some cases to fail and
#' the user has fixed the cause: rather than re-running the whole
#' mask, only the failed cases are refreshed.
#'
#' @param r0 A `genproc_result` produced by [genproc()]. Its
#'   `$reproducibility$mask_snapshot` provides the original mask.
#' @param f A function. Typically the same function passed to the
#'   original `genproc()` call. The result object does not store
#'   `f`, so it must be supplied here. If the previous failures
#'   were caused by a bug in `f`, pass the corrected version.
#' @param parallel,nonblocking,track_inputs,input_cols,skip_input_cols
#'   Forwarded to [genproc()] for the re-run.
#'
#' @return A new `genproc_result` covering only the failed cases.
#'   Its `case_id`s are local to the subset (re-numbered starting at
#'   `case_0001`); the link back to the original `r0` is via the
#'   matching rows of `r0$reproducibility$mask_snapshot`. If `r0`
#'   has zero failed cases, the function returns `NULL` with a
#'   message — there is nothing to re-run.
#'
#' @examples
#' r0 <- genproc(
#'   f = function(x) if (x %% 2 == 0) stop("even") else x,
#'   mask = data.frame(x = 1:6)
#' )
#' # 3 cases failed (the even ones). After fixing f, retry only those:
#' \dontrun{
#'   r1 <- rerun_failed(r0, f = function(x) abs(x))
#'   r1$log
#' }
#'
#' @seealso [rerun_affected()], [errors()], [summary.genproc_result()]
#' @export
rerun_failed <- function(r0, f,
                         parallel        = NULL,
                         nonblocking     = NULL,
                         track_inputs    = TRUE,
                         input_cols      = NULL,
                         skip_input_cols = NULL) {
  # --- Preconditions ----------------------------------------------------
  if (!inherits(r0, "genproc_result")) {
    stop("`r0` must be a `genproc_result` object.", call. = FALSE)
  }
  if (!is.function(f)) {
    stop("`f` must be a function.", call. = FALSE)
  }

  if (is.null(r0$log)) {
    stop("`r0` is not materialized yet. Call await() first.",
         call. = FALSE)
  }

  mask <- r0$reproducibility$mask_snapshot
  if (is.null(mask) || !is.data.frame(mask) || nrow(mask) == 0L) {
    stop("`r0$reproducibility$mask_snapshot` is missing or empty. ",
         "rerun_failed() needs the original mask to filter from.",
         call. = FALSE)
  }

  failed_ids <- r0$log$case_id[!r0$log$success]
  if (length(failed_ids) == 0L) {
    message("No failed cases to re-run.")
    return(invisible(NULL))
  }

  # --- Map case_ids back to rows ---------------------------------------
  row_idx <- tryCatch(
    as.integer(sub("^case_", "", failed_ids)),
    warning = function(w) integer(0),
    error   = function(e) integer(0)
  )
  if (length(row_idx) != length(failed_ids) || anyNA(row_idx)) {
    stop("Could not map case_ids to mask rows. Expected case_ids of ",
         "the form `case_NNNN`. Got: ",
         paste(shQuote(utils::head(failed_ids, 5L)), collapse = ", "),
         if (length(failed_ids) > 5L)
           paste0(" (+", length(failed_ids) - 5L, " more)") else "",
         ".", call. = FALSE)
  }
  if (any(row_idx < 1L) || any(row_idx > nrow(mask))) {
    stop("Some case_ids point outside the mask rows. Did you mutate ",
         "the result before calling rerun_failed()?", call. = FALSE)
  }

  subset_mask <- mask[sort(unique(row_idx)), , drop = FALSE]
  rownames(subset_mask) <- NULL

  genproc(
    f               = f,
    mask            = subset_mask,
    parallel        = parallel,
    nonblocking     = nonblocking,
    track_inputs    = track_inputs,
    input_cols      = input_cols,
    skip_input_cols = skip_input_cols
  )
}
