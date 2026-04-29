# Diff between two `inputs` snapshots
#
# Compares the `reproducibility$inputs$files` tables of two
# `genproc_result` objects produced by genproc(). Reports which input
# files have changed (size or mtime), which are unchanged, which were
# present in the first run but not in the second (`removed`), and
# which are new in the second (`added`).
#
# Matching key:
#   Files are matched by exact canonical path. A user re-running the
#   same code on the same machine sees stable absolute paths; cross-
#   machine comparisons would need a separate matcher (basename-only
#   or content-hash) and are out of scope for v0.1.
#
# Method check:
#   Both snapshots must use the same `method` (currently always
#   "stat"). Cross-method comparison is refused with an explicit
#   error so we stay forward-compatible when a hash method is added.
#
# The returned object is `genproc_input_diff` with a print method that
# formats the diff for human reading. Programmatic access is via the
# named list components.


#' Compare input file fingerprints between two genproc runs
#'
#' Takes two [genproc_result][genproc::genproc()] objects produced by
#' [genproc()] (the same function over the same mask, run at two
#' different times) and reports which referenced input files have
#' changed since the first run.
#'
#' Files are matched by canonical absolute path. The `method` field
#' must agree between the two runs.
#'
#' @param r0,r1 Two `genproc_result` objects. By convention, `r0` is
#'   the earlier run and `r1` the later one, but the function is
#'   symmetric with respect to `changed` / `unchanged`. The labels
#'   `removed` (present in `r0`, absent in `r1`) and `added` (the
#'   opposite) follow the asymmetric convention.
#'
#' @return An object of class `genproc_input_diff` (a named list)
#'   with components:
#'   \describe{
#'     \item{method}{Character, e.g. `"stat"`.}
#'     \item{changed}{A data.frame with columns `path`,
#'       `size_before`, `size_after`, `mtime_before`, `mtime_after`.
#'       One row per file whose size or mtime differs.}
#'     \item{unchanged}{Character vector of paths whose size and
#'       mtime are identical in both runs.}
#'     \item{removed}{Character vector of paths present in `r0`'s
#'       snapshot but absent in `r1`'s.}
#'     \item{added}{Character vector of paths present in `r1`'s
#'       snapshot but absent in `r0`'s.}
#'     \item{cases_affected}{A data.frame with columns `case_id`,
#'       `path`, `column`, `change_type` (one of `"changed"`,
#'       `"removed"`, `"added"`). One row per (case, input column)
#'       impacted by the diff. Pass to [rerun_affected()] to re-run
#'       only the impacted cases.}
#'   }
#'
#' @examples
#' # Two runs of the same procedure, with one input file rewritten
#' # in between. `diff_inputs()` reports the drift.
#' src <- file.path(tempdir(), "diff-inputs-demo")
#' dir.create(src, showWarnings = FALSE, recursive = TRUE)
#' write.csv(head(iris), file.path(src, "a.csv"), row.names = FALSE)
#'
#' mask <- data.frame(
#'   path = file.path(src, "a.csv"),
#'   stringsAsFactors = FALSE
#' )
#' read_one <- function(path) nrow(read.csv(path))
#'
#' r0 <- genproc(read_one, mask)
#'
#' # Rewrite the file with strictly more rows: size changes.
#' write.csv(iris, file.path(src, "a.csv"), row.names = FALSE)
#'
#' r1 <- genproc(read_one, mask)
#' diff_inputs(r0, r1)
#'
#' @export
diff_inputs <- function(r0, r1) {
  # --- Preconditions --------------------------------------------------
  if (!inherits(r0, "genproc_result") || !inherits(r1, "genproc_result")) {
    stop("`r0` and `r1` must both be `genproc_result` objects.",
         call. = FALSE)
  }
  inp0 <- r0$reproducibility$inputs
  inp1 <- r1$reproducibility$inputs
  if (is.null(inp0) || is.null(inp1)) {
    stop(
      "One or both runs were produced with `track_inputs = FALSE`. ",
      "diff_inputs() needs both runs to have tracked inputs.",
      call. = FALSE
    )
  }
  if (!identical(inp0$method, inp1$method)) {
    stop(
      "Cannot diff snapshots produced with different methods ",
      "(`r0` uses ", shQuote(inp0$method), ", ",
      "`r1` uses ", shQuote(inp1$method), ").",
      call. = FALSE
    )
  }

  # --- Match files by canonical path ---------------------------------
  f0 <- inp0$files
  f1 <- inp1$files

  paths0 <- f0$path
  paths1 <- f1$path

  removed <- setdiff(paths0, paths1)
  added   <- setdiff(paths1, paths0)
  shared  <- intersect(paths0, paths1)

  # Align rows in the shared subset for direct comparison.
  i0 <- match(shared, paths0)
  i1 <- match(shared, paths1)

  size0  <- f0$size[i0];  size1  <- f1$size[i1]
  mtime0 <- f0$mtime[i0]; mtime1 <- f1$mtime[i1]

  changed_idx <- !equal_with_na(size0, size1) |
                 !equal_with_na(mtime0, mtime1)

  changed <- data.frame(
    path         = shared[changed_idx],
    size_before  = size0[changed_idx],
    size_after   = size1[changed_idx],
    mtime_before = mtime0[changed_idx],
    mtime_after  = mtime1[changed_idx],
    stringsAsFactors = FALSE
  )

  unchanged <- shared[!changed_idx]

  # --- Build cases_affected -----------------------------------------
  # For each path that has changed/been removed/been added, list every
  # case_id of r0 (changed/removed) or r1 (added) that referenced that
  # path. This is the actionable handle: the user can pass the diff
  # to `rerun_affected()` to re-run only the impacted cases.
  cases_affected <- build_cases_affected(
    refs0       = inp0$refs,
    refs1       = inp1$refs,
    changed_paths = changed$path,
    removed     = removed,
    added       = added
  )

  structure(
    list(
      method         = inp0$method,
      changed        = changed,
      unchanged      = unchanged,
      removed        = removed,
      added          = added,
      cases_affected = cases_affected
    ),
    class = "genproc_input_diff"
  )
}


# Internal. Joins the `refs` tables of the two runs against the
# changed / removed / added path lists to produce a tidy data.frame
# of impacted case_ids. The resulting frame is sorted by case_id so
# that consumers can deduplicate predictably.
build_cases_affected <- function(refs0, refs1,
                                 changed_paths, removed, added) {
  parts <- list()
  if (length(changed_paths) > 0L && nrow(refs0) > 0L) {
    sub <- refs0[refs0$path %in% changed_paths, , drop = FALSE]
    if (nrow(sub) > 0L) {
      parts$changed <- data.frame(
        case_id     = sub$case_id,
        path        = sub$path,
        column      = sub$column,
        change_type = "changed",
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(removed) > 0L && nrow(refs0) > 0L) {
    sub <- refs0[refs0$path %in% removed, , drop = FALSE]
    if (nrow(sub) > 0L) {
      parts$removed <- data.frame(
        case_id     = sub$case_id,
        path        = sub$path,
        column      = sub$column,
        change_type = "removed",
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(added) > 0L && nrow(refs1) > 0L) {
    sub <- refs1[refs1$path %in% added, , drop = FALSE]
    if (nrow(sub) > 0L) {
      parts$added <- data.frame(
        case_id     = sub$case_id,
        path        = sub$path,
        column      = sub$column,
        change_type = "added",
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(parts) == 0L) {
    return(data.frame(
      case_id     = character(0),
      path        = character(0),
      column      = character(0),
      change_type = character(0),
      stringsAsFactors = FALSE
    ))
  }
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out[order(out$case_id, out$path), , drop = FALSE]
}


# Element-wise equality that treats NA == NA as TRUE. Used for the
# diff predicate: a file with NA size in both snapshots (e.g. a path
# declared via input_cols that didn't exist either time) should not
# be flagged as "changed".
equal_with_na <- function(a, b) {
  both_na  <- is.na(a) & is.na(b)
  same_val <- !is.na(a) & !is.na(b) & a == b
  both_na | same_val
}


#' @rdname diff_inputs
#' @param x A `genproc_input_diff` object.
#' @param ... Ignored (present for S3 method consistency).
#' @export
print.genproc_input_diff <- function(x, ...) {
  cat("genproc input diff (method: ", x$method, ")\n", sep = "")
  cat("  Changed:   ", nrow(x$changed),   "\n", sep = "")
  cat("  Unchanged: ", length(x$unchanged), "\n", sep = "")
  cat("  Removed:   ", length(x$removed),   "\n", sep = "")
  cat("  Added:     ", length(x$added),     "\n", sep = "")

  n_affected <- length(unique(x$cases_affected$case_id))
  if (n_affected > 0L) {
    cat("  Cases affected: ", n_affected, "\n", sep = "")
  }

  if (nrow(x$changed) > 0L) {
    cat("\nChanged files:\n")
    for (i in seq_len(nrow(x$changed))) {
      r <- x$changed[i, , drop = FALSE]
      cat("  ", r$path, "\n", sep = "")
      if (!equal_with_na(r$size_before, r$size_after)) {
        # When the rounded human-readable size is identical for
        # before and after (small delta on a >1KB file), show the
        # byte delta explicitly so the change is not invisible.
        s_before <- format_size(r$size_before)
        s_after  <- format_size(r$size_after)
        suffix   <- ""
        if (identical(s_before, s_after) &&
            !is.na(r$size_before) && !is.na(r$size_after)) {
          delta  <- r$size_after - r$size_before
          sign   <- if (delta >= 0) "+" else "-"
          suffix <- sprintf(" (%s%d B)", sign, abs(delta))
        }
        cat("      size:  ", s_before, " -> ", s_after, suffix,
            "\n", sep = "")
      }
      if (!equal_with_na(r$mtime_before, r$mtime_after)) {
        cat("      mtime: ", format(r$mtime_before),
            " -> ",         format(r$mtime_after), "\n", sep = "")
      }
    }
  }

  if (length(x$removed) > 0L) {
    cat("\nRemoved (in first run only):\n")
    for (p in utils::head(x$removed, 10L)) cat("  ", p, "\n", sep = "")
    if (length(x$removed) > 10L)
      cat("  (+", length(x$removed) - 10L, " more)\n", sep = "")
  }

  if (length(x$added) > 0L) {
    cat("\nAdded (in second run only):\n")
    for (p in utils::head(x$added, 10L)) cat("  ", p, "\n", sep = "")
    if (length(x$added) > 10L)
      cat("  (+", length(x$added) - 10L, " more)\n", sep = "")
  }

  # Cases affected: actionable handle. Show up to 10 distinct case_ids,
  # then summarise. The full data.frame is always available via
  # `x$cases_affected` for programmatic use, and as input to
  # `rerun_affected()`.
  if (n_affected > 0L) {
    case_ids <- unique(x$cases_affected$case_id)
    cat("\nCases affected (use rerun_affected() to re-run):\n  ")
    cat(paste(utils::head(case_ids, 10L), collapse = ", "))
    if (length(case_ids) > 10L) {
      cat(" (+", length(case_ids) - 10L, " more)", sep = "")
    }
    cat("\n")
  }

  invisible(x)
}


# Pretty-print a byte size with NA-tolerance. Kept private; the diff
# print is the only caller for now.
format_size <- function(n) {
  if (is.na(n)) return("NA")
  if (n < 1024)        return(paste0(n, " B"))
  if (n < 1024^2)      return(sprintf("%.1f KB", n / 1024))
  if (n < 1024^3)      return(sprintf("%.1f MB", n / 1024^2))
  sprintf("%.2f GB", n / 1024^3)
}
