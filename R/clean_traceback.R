# Clean traceback utility
#
# Filters and truncates a raw call stack captured by sys.calls() to
# produce a human-readable traceback. Removes genproc's internal
# machinery (tryCatch, withCallingHandlers, do.call, the injected
# wrapper body) so the user sees only their own code and the functions
# it called.


#' Clean a raw traceback from sys.calls()
#'
#' Filters out internal genproc frames and R error-handling machinery,
#' then truncates long lines for readability. The goal is to show only
#' the user's own call chain leading to the error.
#'
#' @param calls A list of call objects (typically from `sys.calls()`).
#' @param max_width Integer. Maximum character width per line before
#'   truncation. Default 120.
#' @return Character(1). The cleaned, numbered, collapsed traceback
#'   string, or `NA_character_` if no user frames remain after
#'   filtering. Frames are numbered sequentially (1 = outermost call).
#'
#' @details
#' ## Filtering rules
#'
#' A frame is removed if its deparsed text matches any of these
#' patterns:
#' - R error-handling internals: `tryCatch`, `tryCatchList`,
#'   `tryCatchOne`, `doTryCatch`, `withCallingHandlers`
#' - genproc injection: lines containing `.__` (the double-underscore
#'   convention used by `add_trycatch_logrow()`)
#' - `do.call(f_logged, ...)` (genproc's internal dispatch)
#' - `genproc::genproc(` or `genproc(` at the top of the stack
#' - Error signalling mechanism: `stop()`, `simpleError()`,
#'   `simpleCondition()`, `.handleSimpleError()`
#'
#' ## Formatting
#'
#' Each surviving line is truncated to `max_width` characters (with
#' ` ...` appended if truncated), then numbered sequentially.
#'
#' @noRd
clean_traceback <- function(calls, max_width = 120L) {
  if (length(calls) == 0) return(NA_character_)

  # Deparse each call to a single-line string
  lines <- vapply(calls, function(cl) {
    paste(deparse(cl, width.cutoff = 500L), collapse = " ")
  }, character(1))

  # --- Filter out internal frames ---
  # Pattern 1: R error-handling internals
  is_internal <- grepl(
    "^(tryCatch|tryCatchList|tryCatchOne|doTryCatch|withCallingHandlers)\\(",
    lines
  )

  # Pattern 2: genproc injected code (.__variables__)
  is_injected <- grepl("\\.__[a-zA-Z]", lines)

  # Pattern 3: do.call(f_logged, ...) — genproc's internal iteration
  is_docall <- grepl("^do\\.call\\(f_logged", lines)

  # Pattern 4: genproc() or genproc::genproc() at the top
  is_genproc_call <- grepl("^(genproc::)?genproc\\(", lines)

  # Pattern 5: error signalling internals (stop, simpleError, simpleCondition)
  # These are the mechanism, not the cause — the user cares about what
  # called stop(), not stop() itself.
  is_signal <- grepl(
    "^(stop|simpleError|simpleCondition|\\.handleSimpleError)\\(",
    lines
  )

  keep <- !(is_internal | is_injected | is_docall |
              is_genproc_call | is_signal)
  lines <- lines[keep]

  if (length(lines) == 0) return(NA_character_)

  # --- Truncate long lines ---
  too_long <- nchar(lines) > max_width
  lines[too_long] <- paste0(substr(lines[too_long], 1, max_width - 4), " ...")

  # --- Number frames (most recent = 1, i.e. bottom-up reading order) ---
  n <- length(lines)
  numbered <- paste0(seq_len(n), ". ", lines)

  paste(numbered, collapse = "\n")
}
