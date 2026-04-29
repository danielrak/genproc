# Non-blocking interrogation methods for genproc_result.
#
# A non-blocking run returns a `genproc_result` skeleton immediately,
# with `status = "running"` and the underlying future stored in
# `attr(x, "future")`. `status()` is a cheap query of the future's
# state. `await()` blocks until the future resolves and splices the
# materialized fields back into the result.
#
# Both are idempotent on already-resolved objects so user code can
# safely call them multiple times.
#
# === status() distinguishes done from error ===
#
# `future::resolved(f)` only tells us "the future has finished",
# not whether it succeeded or threw. To distinguish the two, we
# call `future::value(f)` inside a tryCatch. The catch is that
# `value()` consumes the future: a subsequent call would fail.
# We solve this with a shared environment (attribute
# `shared_env`) attached to the skeleton at creation time. When
# `status()` peeks, it stores the result (or a captured error
# object) in this env. `await()` then prefers the cached result
# over a fresh call to `value()`. The shared env is a regular R
# environment, hence reference-mutated even though `x` is
# pass-by-value.


#' Query the status of a genproc run without blocking
#'
#' `status()` is a non-blocking S3 generic. On a `genproc_result`,
#' it returns one of:
#' \itemize{
#'   \item `"running"` — the underlying future is not yet resolved.
#'   \item `"done"` — the future has resolved successfully (the
#'     result is ready to be collected via [await()]).
#'   \item `"error"` — the wrapper future itself crashed. Call
#'     [await()] to retrieve the error message.
#' }
#'
#' For a synchronous (non-`nonblocking`) result, `status()` simply
#' returns `result$status` (`"done"` or `"error"`).
#'
#' `status()` peeks at the resolved future via `future::value()`
#' inside a `tryCatch`. Because `value()` consumes the future, the
#' peek result is cached in a shared environment so that a
#' subsequent [await()] does not re-materialize it.
#'
#' @param x An object. Methods exist for `genproc_result`.
#' @param ... Unused, for future extensions.
#'
#' @return A single character string: `"running"`, `"done"`, or
#'   `"error"`.
#'
#' @seealso [await()], [nonblocking_spec()]
#' @export
status <- function(x, ...) {
  UseMethod("status")
}

#' @rdname status
#' @export
status.genproc_result <- function(x, ...) {
  f <- attr(x, "future")
  if (is.null(f)) {
    return(x$status)
  }

  shared <- attr(x, "shared_env")

  # If a previous status() call has already peeked the resolved
  # future, return the cached classification.
  if (!is.null(shared) && exists("peek_state", envir = shared)) {
    return(shared$peek_state)
  }

  if (!future::resolved(f)) {
    return("running")
  }

  # Future is resolved. Peek to distinguish done from error.
  # tryCatch() makes this safe; the captured value (or error) is
  # cached so await() can re-use it without re-materializing.
  result <- tryCatch(
    future::value(f),
    error = function(e) {
      structure(
        list(message = conditionMessage(e)),
        class = "genproc_wrapper_error"
      )
    }
  )

  state <- if (inherits(result, "genproc_wrapper_error")) "error" else "done"

  if (!is.null(shared)) {
    shared$peek_state  <- state
    shared$peek_result <- result
  }

  state
}


#' Block until a non-blocking genproc run has resolved
#'
#' `await()` blocks until the background future of a non-blocking
#' [genproc()] run has resolved, then returns a `genproc_result`
#' with `log`, `n_success`, `n_error`, `duration_total_secs`, and
#' `status` populated. If the wrapper future itself crashed (a rare
#' case — user errors inside individual cases are caught by the
#' logging layer and are *not* wrapper crashes), the returned
#' object has `status = "error"` and a populated `error_message`.
#'
#' `await()` is idempotent: calling it on a result that has already
#' been materialized (or was synchronous to begin with) returns it
#' unchanged.
#'
#' @param x An object. Methods exist for `genproc_result`.
#' @param ... Unused, for future extensions.
#'
#' @return A `genproc_result` with `status != "running"`.
#'
#' @seealso [status()], [nonblocking_spec()]
#' @export
await <- function(x, ...) {
  UseMethod("await")
}

#' @rdname await
#' @export
await.genproc_result <- function(x, ...) {
  f <- attr(x, "future")

  # No future attached, or status already terminal: nothing to do.
  if (is.null(f) || !identical(x$status, "running")) {
    return(x)
  }

  shared <- attr(x, "shared_env")

  # If a previous status() call has already peeked, reuse the
  # cached result. Otherwise materialize the future ourselves.
  if (!is.null(shared) && exists("peek_result", envir = shared)) {
    materialized <- shared$peek_result
  } else {
    materialized <- tryCatch(
      future::value(f),
      error = function(e) {
        structure(
          list(message = conditionMessage(e)),
          class = "genproc_wrapper_error"
        )
      }
    )
  }

  # Once the future is collected, we can safely restore the previous
  # plan (if genproc() installed one for this run). We do this here,
  # not in on.exit of genproc(), because `future::plan()` shuts down
  # the current cluster on switch — doing it before collection kills
  # the very worker running the submitted future.
  oplan <- attr(x, "oplan")
  if (!is.null(oplan)) {
    try(future::plan(oplan), silent = TRUE)
  }
  attr(x, "oplan") <- NULL

  # Wrapper crash: expose via status = "error" + error_message.
  if (inherits(materialized, "genproc_wrapper_error")) {
    x$status        <- "error"
    x$error_message <- materialized$message
    attr(x, "future") <- NULL
    return(x)
  }

  # Normal path: splice in the fields produced inside the future.
  for (nm in names(materialized)) {
    x[[nm]] <- materialized[[nm]]
  }
  x$status <- "done"
  attr(x, "future") <- NULL
  x
}
