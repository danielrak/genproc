# Non-blocking interrogation methods for genproc_result.
#
# A non-blocking run returns a `genproc_result` skeleton immediately,
# with `status = "running"` and the underlying future stored in
# `attr(x, "future")`. `status()` is a cheap, non-blocking query of
# the future's state. `await()` blocks until the future resolves and
# splices the materialized fields back into the result.
#
# Both are idempotent on already-resolved objects so user code can
# safely call them multiple times.


#' Query the status of a genproc run without blocking
#'
#' `status()` is a non-blocking S3 generic. On a `genproc_result`,
#' it returns `"running"` while a background future is unresolved,
#' and `"done"` once it has resolved (or if the object is already
#' synchronous-done). It does *not* materialize the result — use
#' [await()] for that. If you want to know whether the wrapper
#' future itself crashed, you must call [await()].
#'
#' @param x An object. Methods exist for `genproc_result`.
#' @param ... Unused, for future extensions.
#'
#' @return A single character string.
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
  if (future::resolved(f)) {
    return("done")
  }
  "running"
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

  # Block on the wrapper future.
  materialized <- tryCatch(
    future::value(f),
    error = function(e) {
      structure(
        list(message = conditionMessage(e)),
        class = "genproc_wrapper_error"
      )
    }
  )

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
