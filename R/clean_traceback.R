# Clean traceback utility
#
# Filters and truncates a raw call stack captured by sys.calls() to
# produce a human-readable traceback. Removes genproc's internal
# machinery (tryCatch, withCallingHandlers, the injected wrapper body,
# R's own error-signalling frames, dispatcher / worker frames) so the
# user sees only their own code and the functions it called.
#
# === Filtering layers ===
#
# Three independent filters are applied to the captured `sys.calls()`:
#
# 1. **tryCatch/withCallingHandlers block (position-based)**. genproc
#    always nests user code inside `tryCatch(withCallingHandlers({...}))`,
#    so we locate the contiguous block of frames whose head is in that
#    family and drop it wholesale.
# 2. **R error-signalling frames (symbol-based)**. simpleError,
#    .handleSimpleError, etc. — R's machinery for raising the
#    condition, never the cause itself.
# 3. **Anonymous-function-call frames (structural)**. genproc's
#    injected error handler is `(function(.__e__){...})(err)`. Its
#    head is a call object, not a symbol; we use that structural
#    difference to recognize and drop it.
# 4. **Leading dispatcher/worker frames (head-position-based)**. The
#    sequential dispatcher (`execute_cases`, `do.call`, `FUN`, the
#    `lapply` callback) and the PSOCK worker (`workRSOCK`, `workLoop`,
#    `workCommand`, `makeSOCKmaster`) and the future runner
#    (`future_lapply`, `future_xapply`) are always at the top of the
#    captured stack. We drop them by consuming frames *from the head*
#    while they belong to a known dispatcher/worker name. This is
#    safe even if the user calls `lapply()` or `do.call()` themselves
#    inside their function — those frames are not at the head.
#
# === Why match on call HEAD, not deparse text? ===
#
# A previous implementation used regex on the deparsed frame text.
# That was fragile: the deparse of a frame contains its *arguments*,
# so a frame like ".handleSimpleError(h, msg, call = withCallingHandlers(...))"
# deparses to text that *contains* "withCallingHandlers" but does NOT
# start with it — simple anchored or non-anchored patterns then either
# miss it (too strict) or over-match legitimate user code (too loose).
#
# The current implementation inspects `cl[[1]]` — the call's head —
# directly. For a normal call like `my_func()`, the head is the symbol
# `my_func`. For anonymous function invocations (e.g. the injected
# error handler `(function(.__e__){...})(err)`), the head is itself
# a call object, not a symbol.


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
#' ## Filtering strategy
#'
#' 1. **Position-based block drop.** The genproc wrapper always nests
#'    user code inside `tryCatch(withCallingHandlers({ ... }))`. We
#'    locate the contiguous block of frames whose head is one of
#'    `tryCatch`, `tryCatchList`, `tryCatchOne`, `doTryCatch`,
#'    `withCallingHandlers` and drop it wholesale.
#' 2. **Symbol-based signal drop.** Frames whose head is a symbol in
#'    `{simpleError, simpleCondition, .handleSimpleError,
#'    .signalCondition, signalCondition}` are dropped — these are R's
#'    error-signalling mechanism, not a cause.
#' 3. **Anonymous-function-call drop.** Frames whose head is not a
#'    symbol (e.g. `(function(.__e__){...})(err)`) are dropped. In
#'    practice these are always genproc's injected handlers.
#' 4. **Leading dispatcher/worker drop.** Frames at the top of the
#'    stack whose head is a known internal dispatcher
#'    (`execute_cases`, `do.call`, `FUN`), future runner
#'    (`future_lapply`, `future_xapply`), or PSOCK worker
#'    (`workRSOCK`, `workLoop`, `workCommand`, `makeSOCKmaster`) are
#'    consumed from the head, until a non-dispatcher frame is reached.
#'    This is safe against user code that calls `lapply()` or
#'    `do.call()` itself — those frames are never at the very top.
#'
#' ## Formatting
#'
#' Each surviving line is truncated to `max_width` characters (with
#' ` ...` appended if truncated), then numbered sequentially.
#'
#' @noRd
clean_traceback <- function(calls, max_width = 120L) {
  if (length(calls) == 0) return(NA_character_)

  # --- Extract each frame's head (the function being called) ---
  heads <- lapply(calls, function(cl) {
    if (length(cl) == 0L) NULL else cl[[1L]]
  })
  head_is_symbol <- vapply(heads, is.symbol, logical(1))
  head_names <- vapply(seq_along(heads), function(i) {
    if (isTRUE(head_is_symbol[i])) as.character(heads[[i]]) else NA_character_
  }, character(1))

  # --- Drop the tryCatch/withCallingHandlers machinery block ---
  machinery_fns <- c(
    "tryCatch", "tryCatchList", "tryCatchOne",
    "doTryCatch", "withCallingHandlers"
  )
  machinery_idx <- which(!is.na(head_names) & head_names %in% machinery_fns)

  if (length(machinery_idx) > 0L) {
    drop_range <- seq(min(machinery_idx), max(machinery_idx))
    keep_idx <- setdiff(seq_along(calls), drop_range)
    calls <- calls[keep_idx]
    head_names <- head_names[keep_idx]
    head_is_symbol <- head_is_symbol[keep_idx]
  }

  # --- Drop R error-signalling internals ---
  signal_fns <- c(
    "simpleError", "simpleCondition",
    ".handleSimpleError", ".signalCondition", "signalCondition"
  )
  is_signal <- !is.na(head_names) & head_names %in% signal_fns

  # --- Drop anonymous-function invocations (genproc's injected handlers) ---
  is_anon_fn_call <- !head_is_symbol

  keep <- !(is_signal | is_anon_fn_call)
  calls <- calls[keep]

  if (length(calls) == 0L) return(NA_character_)

  # --- Drop leading dispatcher / worker frames ---
  # Internal frames that sit at the very top of the captured stack
  # before user code starts. We consume them from the head only.
  # Exception: the *real* top-of-stack `execute_cases` call is
  # always present (sequential path). PSOCK worker frames are present
  # in the parallel path. future runner frames may appear in nested
  # configurations.
  dispatcher_fns <- c(
    # genproc entry point and dispatcher
    "genproc", "execute_cases",
    # The lapply() call that genproc uses internally to dispatch
    # cases sequentially, plus its callback machinery. These are
    # safe to drop *from the head* even though the user might call
    # lapply()/do.call() inside their own function: such user calls
    # are mid-stack (they come after the user fn frame), not at the
    # head, so the head-position filter never reaches them.
    "lapply", "do.call", "FUN",
    # future / future.apply runners
    "future_lapply", "future_xapply",
    # PSOCK worker
    "workRSOCK", "workLoop", "workCommand", "makeSOCKmaster",
    # invocation context (when called via source()/eval())
    "source", "withVisible", "eval"
  )
  while (length(calls) > 0L) {
    head1 <- calls[[1L]][[1L]]
    if (!is.symbol(head1)) break
    if (!as.character(head1) %in% dispatcher_fns) break
    calls <- calls[-1L]
  }

  if (length(calls) == 0L) return(NA_character_)

  # --- Deparse surviving frames ---
  lines <- vapply(calls, function(cl) {
    paste(deparse(cl, width.cutoff = 500L), collapse = " ")
  }, character(1))

  # --- Safety net: drop any line that still leaks internal markers ---
  # Defensive belt-and-braces. Shouldn't fire given the structural
  # filtering above, but it guarantees the invariant.
  leak <- grepl("withCallingHandlers\\(|[`.]__[A-Za-z]", lines)
  lines <- lines[!leak]

  if (length(lines) == 0L) return(NA_character_)

  # --- Truncate long lines ---
  too_long <- nchar(lines) > max_width
  lines[too_long] <- paste0(substr(lines[too_long], 1L, max_width - 4L), " ...")

  # --- Number frames (1 = outermost) ---
  n <- length(lines)
  numbered <- paste0(seq_len(n), ". ", lines)

  paste(numbered, collapse = "\n")
}
