# Re-run only the cases impacted by an input diff.
#
# Closes the storytelling loop of the reproducibility layer:
#   1. Capture two runs r0 and r1 over time.
#   2. diff_inputs(r0, r1) reports which input files have drifted.
#   3. rerun_affected(r0, diff, f) re-runs only the cases that
#      referenced those files, on the original mask.
#
# Implementation notes:
#   - The mask is read from r0$reproducibility$mask_snapshot.
#     case_ids are the canonical handle linking diff -> mask rows.
#   - The case_id format is index-based (`case_NNNN`) and stable
#     within a single mask, so we can recover the row index via a
#     simple parse. If the case_id format changes to content-based
#     in a future version, this helper will need to look up the row
#     via a (case_id -> row) map stored in the result.
#   - The re-run produces a *fresh* genproc_result with its own
#     log/repro. Its case_ids are renumbered starting from
#     case_0001 within the subset — they are LOCAL to the re-run,
#     not aligned with r0's case_ids. Documented as such.


#' Re-run only the cases impacted by an input diff
#'
#' Filters the original mask of `r0` down to the cases that
#' referenced inputs reported as changed, removed, or added by
#' [diff_inputs()], and re-runs `genproc()` on that subset.
#'
#' This is the actionable end of the reproducibility layer: when an
#' upstream file silently drifts, you do not need to re-run the
#' whole mask. `rerun_affected()` produces a smaller run that
#' refreshes only the impacted outputs.
#'
#' @param r0 A `genproc_result` produced by [genproc()]. Its
#'   `$reproducibility$mask_snapshot` provides the original mask;
#'   it must contain `track_inputs = TRUE` (the default).
#' @param diff A `genproc_input_diff` produced by [diff_inputs()].
#' @param f A function. Typically the same function passed to the
#'   original `genproc()` call. The result object does not store
#'   `f`, so it must be supplied here.
#' @param parallel,nonblocking,track_inputs,input_cols,skip_input_cols
#'   Forwarded to [genproc()] for the re-run. By default, these
#'   inherit a sensible behaviour: `track_inputs = TRUE` (so the
#'   re-run is itself comparable), the other arguments default to
#'   `NULL` (sequential, blocking, automatic input tracking).
#'
#' @return A new `genproc_result` covering only the affected cases.
#'   Its `case_id`s are local to the subset (re-numbered starting at
#'   `case_0001`); the link back to the original `r0` is via the
#'   matching rows of `r0$reproducibility$mask_snapshot`. If `diff`
#'   reports no affected cases, the function returns `NULL` with a
#'   message — there is nothing to re-run.
#'
#' @examples
#' \dontrun{
#'   r0 <- genproc(my_fn, my_mask)
#'   # ... time passes, some upstream files change ...
#'   r1 <- genproc(my_fn, my_mask)
#'
#'   d <- diff_inputs(r0, r1)
#'   # d$cases_affected lists the case_ids whose inputs drifted.
#'
#'   refreshed <- rerun_affected(r0, d, f = my_fn)
#'   refreshed$log
#' }
#'
#' @seealso [diff_inputs()], [genproc()]
#' @export
rerun_affected <- function(r0, diff, f,
                           parallel        = NULL,
                           nonblocking     = NULL,
                           track_inputs    = TRUE,
                           input_cols      = NULL,
                           skip_input_cols = NULL) {
  # --- Preconditions ----------------------------------------------------
  if (!inherits(r0, "genproc_result")) {
    stop("`r0` must be a `genproc_result` object.", call. = FALSE)
  }
  if (!inherits(diff, "genproc_input_diff")) {
    stop("`diff` must be a `genproc_input_diff` object produced by ",
         "diff_inputs().", call. = FALSE)
  }
  if (!is.function(f)) {
    stop("`f` must be a function.", call. = FALSE)
  }

  mask <- r0$reproducibility$mask_snapshot
  if (is.null(mask) || !is.data.frame(mask) || nrow(mask) == 0L) {
    stop("`r0$reproducibility$mask_snapshot` is missing or empty. ",
         "rerun_affected() needs the original mask to filter from.",
         call. = FALSE)
  }

  affected_ids <- unique(diff$cases_affected$case_id)
  if (length(affected_ids) == 0L) {
    message("No cases affected by this diff. Nothing to re-run.")
    return(invisible(NULL))
  }

  # --- Map case_ids back to rows ---------------------------------------
  # The current case_id format is `case_NNNN`. We parse the integer
  # suffix to recover row indices. If genproc later moves to a
  # content-based case_id, this branch needs a (case_id -> row) map
  # stored in the result.
  row_idx <- tryCatch(
    as.integer(sub("^case_", "", affected_ids)),
    warning = function(w) integer(0),
    error   = function(e) integer(0)
  )
  if (length(row_idx) != length(affected_ids) || anyNA(row_idx)) {
    stop("Could not map case_ids to mask rows. Expected case_ids of ",
         "the form `case_NNNN`. Got: ",
         paste(shQuote(utils::head(affected_ids, 5L)), collapse = ", "),
         if (length(affected_ids) > 5L)
           paste0(" (+", length(affected_ids) - 5L, " more)") else "",
         ".", call. = FALSE)
  }
  if (any(row_idx < 1L) || any(row_idx > nrow(mask))) {
    stop("Some case_ids point outside the mask rows. The diff may ",
         "have been computed from a different run than `r0`.",
         call. = FALSE)
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
