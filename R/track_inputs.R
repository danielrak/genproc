# Input file fingerprinting (Piste B)
#
# Captures a stat-based fingerprint (size + mtime) of every file
# referenced in the mask, so that two runs of the same procedure can be
# compared and any silent change of an upstream file flagged via
# `diff_inputs()`.
#
# Why stat (size + mtime), not a content hash?
#   - For the most common case (the same user re-running the same code
#     on the same machine after possibly editing an input), size + mtime
#     detects all legitimate modifications and costs O(syscall) per file.
#   - A content hash (MD5/xxhash) would multiply the run startup cost
#     by N x file_size and add a dependency. Reserved for a later
#     extension via the `method` field.
#
# Heuristic for column detection (default mode):
#   A column of the mask is treated as containing input file paths iff
#     - it is character,
#     - it has at least one non-NA value,
#     - every non-NA value satisfies `file.exists() && !dir.exists()`,
#     - at least one non-NA value contains a path separator
#       (filters short labels that incidentally match a file in cwd).
#
# Override semantics:
#   - input_cols = c(...)        -> bypass heuristic, take exactly these
#                                   columns. Missing files yield rows
#                                   with size = NA, mtime = NA, plus a
#                                   warning. NA values in the mask are
#                                   recorded in `refs` with path = NA.
#   - skip_input_cols = c(...)   -> heuristic applied first, then these
#                                   columns are removed from selection.
#   - Both at once is an error: the two flags express contradictory
#     intentions and we'd rather force the user to clarify.
#
# Output structure (stored in result$reproducibility$inputs):
#   list(
#     method = "stat",
#     files  = data.frame(path, size, mtime),     # one row per file
#     refs   = data.frame(case_id, column, path)  # one row per
#                                                 # (case, input column)
#   )
#
# `files` is deduplicated by canonical path: the same file referenced
# from many cases produces a single row in `files` and many rows in
# `refs`. This keeps the snapshot economical on masks where most cases
# share configuration files.


# --- Heuristic ----------------------------------------------------------

# Detect whether a single mask column looks like a column of input file
# paths. Returns TRUE / FALSE. NA-tolerant: ignores NA values when
# checking existence and separator presence, but requires at least one
# non-NA value overall.
is_input_column <- function(col) {
  if (!is.character(col)) return(FALSE)

  non_na <- col[!is.na(col)]
  if (length(non_na) == 0L) return(FALSE)

  # All non-NA values must point to an existing regular file.
  exists_ok <- all(file.exists(non_na) & !dir.exists(non_na))
  if (!exists_ok) return(FALSE)

  # At least one value must look path-shaped.
  any(grepl("[/\\\\]", non_na))
}


# Pick the names of mask columns to be tracked, given user overrides.
# Returns a (possibly empty) character vector of column names.
#
# Errors out on inconsistent overrides; otherwise applies, in order:
#   1. exact list via `input_cols`, OR
#   2. heuristic on every column, then removal of `skip_input_cols`.
select_input_columns <- function(mask,
                                 input_cols = NULL,
                                 skip_input_cols = NULL) {
  if (!is.null(input_cols) && !is.null(skip_input_cols)) {
    stop(
      "`input_cols` and `skip_input_cols` cannot be used together. ",
      "Use one or the other to declare your intention explicitly.",
      call. = FALSE
    )
  }

  mask_cols <- names(mask)

  if (!is.null(input_cols)) {
    if (!is.character(input_cols) || any(is.na(input_cols)) ||
        any(!nzchar(input_cols))) {
      stop("`input_cols` must be a non-empty character vector.",
           call. = FALSE)
    }
    missing <- setdiff(input_cols, mask_cols)
    if (length(missing)) {
      stop(
        "`input_cols` references unknown column(s): ",
        paste(shQuote(missing), collapse = ", "), ".",
        call. = FALSE
      )
    }
    return(input_cols)
  }

  detected <- mask_cols[vapply(mask_cols,
                               function(c) is_input_column(mask[[c]]),
                               logical(1))]

  if (!is.null(skip_input_cols)) {
    if (!is.character(skip_input_cols) || any(is.na(skip_input_cols)) ||
        any(!nzchar(skip_input_cols))) {
      stop("`skip_input_cols` must be a non-empty character vector.",
           call. = FALSE)
    }
    missing <- setdiff(skip_input_cols, mask_cols)
    if (length(missing)) {
      stop(
        "`skip_input_cols` references unknown column(s): ",
        paste(shQuote(missing), collapse = ", "), ".",
        call. = FALSE
      )
    }
    detected <- setdiff(detected, skip_input_cols)
  }

  detected
}


# --- Stat -------------------------------------------------------------

# Stat a vector of paths. Returns a data.frame
# (path, size, mtime), one row per *unique* canonical path, in input
# order. Paths are normalized via normalizePath(mustWork = FALSE).
# Non-existing paths yield size = NA and mtime = NA.
stat_files <- function(paths) {
  if (length(paths) == 0L) {
    return(data.frame(
      path  = character(0),
      size  = numeric(0),
      mtime = .POSIXct(numeric(0)),
      stringsAsFactors = FALSE
    ))
  }

  canon <- normalizePath(paths, winslash = "/", mustWork = FALSE)
  canon <- unique(canon)

  exists_flag <- file.exists(canon) & !dir.exists(canon)

  size  <- ifelse(exists_flag, file.size(canon),  NA_real_)
  mtime <- as.POSIXct(rep(NA_real_, length(canon)),
                      origin = "1970-01-01")
  mtime[exists_flag] <- file.mtime(canon[exists_flag])

  data.frame(
    path  = canon,
    size  = size,
    mtime = mtime,
    stringsAsFactors = FALSE
  )
}


# --- Top-level capture ------------------------------------------------

# Build the full inputs snapshot for a run. Returns NULL when tracking
# is disabled. Otherwise returns a list with `method`, `files`, `refs`.
#
# Why a top-level NULL when disabled (rather than empty data.frames)?
#   - `is.null(result$reproducibility$inputs)` is the canonical "this
#     run did not track inputs" check, useful for diff_inputs() to
#     refuse comparison.
#   - It also keeps the snapshot small for users who explicitly opt out.
capture_input_fingerprints <- function(mask, case_ids,
                                       track = TRUE,
                                       input_cols = NULL,
                                       skip_input_cols = NULL) {
  if (isFALSE(track)) {
    if (!is.null(input_cols) || !is.null(skip_input_cols)) {
      stop(
        "`input_cols` / `skip_input_cols` cannot be used when ",
        "`track_inputs = FALSE`.",
        call. = FALSE
      )
    }
    return(NULL)
  }
  if (!isTRUE(track)) {
    stop("`track_inputs` must be TRUE or FALSE.", call. = FALSE)
  }

  cols <- select_input_columns(mask,
                               input_cols      = input_cols,
                               skip_input_cols = skip_input_cols)

  # No input columns to track -> empty but well-formed snapshot.
  if (length(cols) == 0L) {
    return(list(
      method = "stat",
      files  = stat_files(character(0)),
      refs   = data.frame(
        case_id = character(0),
        column  = character(0),
        path    = character(0),
        stringsAsFactors = FALSE
      )
    ))
  }

  # Build refs table: one row per (case_id, column).
  # Paths are canonicalized so that the join against `files` is exact.
  ref_chunks <- lapply(cols, function(col) {
    raw <- as.character(mask[[col]])
    canon <- ifelse(
      is.na(raw),
      NA_character_,
      normalizePath(raw, winslash = "/", mustWork = FALSE)
    )
    data.frame(
      case_id = case_ids,
      column  = col,
      path    = canon,
      stringsAsFactors = FALSE
    )
  })
  refs <- do.call(rbind, ref_chunks)

  # Stat the unique non-NA paths.
  unique_paths <- unique(stats::na.omit(refs$path))
  files <- stat_files(unique_paths)

  # If the user forced a column via `input_cols` and some files don't
  # exist, warn (the snapshot is still produced, with NA size / mtime).
  if (!is.null(input_cols) && nrow(files) > 0L) {
    missing_files <- files$path[is.na(files$size)]
    if (length(missing_files)) {
      warning(
        "Some paths declared via `input_cols` do not exist at capture ",
        "time and were recorded with NA size/mtime: ",
        paste(shQuote(utils::head(missing_files, 5L)),
              collapse = ", "),
        if (length(missing_files) > 5L)
          paste0(" (+", length(missing_files) - 5L, " more)") else "",
        ".",
        call. = FALSE
      )
    }
  }

  list(
    method = "stat",
    files  = files,
    refs   = refs
  )
}
