# Tests for the progressr integration in genproc().
#
# These tests verify that genproc() emits one `progression` condition
# per completed case in the sequential and parallel paths, and that
# the integration is a no-op when progressr is not enabled (no
# with_progress()) or when the path is non-blocking.
#
# Implementation note: we capture progression signals via
# `withCallingHandlers(..., progression = ...)` rather than running a
# real progress handler, to keep tests deterministic and silent.


# Helper: run an expression inside `progressr::with_progress()` and
# count the number of progression conditions emitted. Returns the
# (result, n_signals) pair.
count_progressions <- function(expr) {
  skip_if_not_installed("progressr")

  # Force a "void" handler so the test is deterministic across
  # session types: void emits the progression conditions but
  # neither renders them nor muffles them, so the outer
  # withCallingHandlers can capture them.
  old_handlers <- progressr::handlers()
  progressr::handlers("void")
  on.exit(progressr::handlers(old_handlers), add = TRUE)

  n <- 0L
  # `enable = TRUE` is critical here. progressr::with_progress()
  # defaults to consulting `interactive()` (via the
  # `progressr.enable` option) to decide whether to instantiate a
  # progressor at all. On a non-interactive session (R CMD check
  # on CI), the default declines, no progressor is created, and no
  # progression conditions are ever emitted — leaving the outer
  # withCallingHandlers with nothing to capture (n = 0). Forcing
  # enable = TRUE makes the helper deterministic everywhere.
  res <- progressr::with_progress(
    {
      withCallingHandlers(
        expr,
        progression = function(cond) {
          n <<- n + 1L
          # The restart name for progressr conditions is
          # "muffleProgression", not the generic "muffleCondition".
          # Without invokeRestart() the condition keeps
          # propagating and downstream handlers double-count it.
          if (!is.null(findRestart("muffleProgression"))) {
            invokeRestart("muffleProgression")
          }
        }
      )
    },
    enable = TRUE
  )
  list(result = res, n = n)
}


# === Sequential path =========================================================

test_that("progressr emits one signal per case in sequential mode", {
  out <- count_progressions(
    genproc(function(x) x * 2, data.frame(x = 1:5))
  )
  expect_s3_class(out$result, "genproc_result")
  expect_equal(out$result$n_success, 5L)
  # At least one signal per case. progressr may emit additional
  # bookkeeping signals (start / finish), so we assert >= n_cases.
  expect_gte(out$n, 5L)
})

test_that("progressr signals fire even when some cases error", {
  out <- count_progressions(
    genproc(
      function(x) if (x == 3) stop("boom") else x,
      data.frame(x = 1:5)
    )
  )
  expect_equal(out$result$n_success, 4L)
  expect_equal(out$result$n_error, 1L)
  # All 5 cases produce a progression, including the failed one.
  expect_gte(out$n, 5L)
})


# === No-op when not wrapped in with_progress() ===============================

test_that("genproc emits no visible progress without with_progress()", {
  skip_if_not_installed("progressr")
  # Without with_progress(), progressr signals are still emitted
  # internally but have no visible side effect (no handler is active).
  # We verify that the run completes normally and is silent at the
  # console.
  expect_silent(
    r <- genproc(function(x) x, data.frame(x = 1:3))
  )
  expect_equal(r$n_success, 3L)
})


# === Parallel path (sequential strategy for determinism) ====================

test_that("progressr signals are emitted in parallel-sequential mode", {
  skip_if_not_installed("progressr")
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")

  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  out <- count_progressions(
    genproc(
      f = function(x) x + 1L,
      mask = data.frame(x = 1:4),
      parallel = parallel_spec(strategy = "sequential")
    )
  )
  expect_equal(out$result$n_success, 4L)
  expect_gte(out$n, 4L)
})


# === Non-blocking path: integration is intentionally skipped ================

test_that("non-blocking path does not emit progressr signals during the run", {
  skip_if_not_installed("progressr")
  skip_if_not_installed("future")

  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  # Wrap with_progress() around both genproc() and await(): we want
  # to verify that no progression burst appears when the run is
  # finally collected — the design choice is to skip live progressr
  # in non-blocking mode entirely (see execute_cases monitor flag).
  # Force a void handler + enable = TRUE so this test exercises the
  # real "is the per-case burst suppressed?" check on non-interactive
  # CI sessions too. Without enable = TRUE, with_progress() defers to
  # interactive() and never creates a progressor on CI, which would
  # make this test pass trivially (n = 0) for the wrong reason.
  old_handlers <- progressr::handlers()
  progressr::handlers("void")
  on.exit(progressr::handlers(old_handlers), add = TRUE)

  n <- 0L
  progressr::with_progress(
    {
      withCallingHandlers(
        {
          x <- genproc(
            function(x) x, data.frame(x = 1:3),
            nonblocking = nonblocking_spec(strategy = "sequential")
          )
          x <- await(x)
        },
        progression = function(cond) {
          n <<- n + 1L
          if (!is.null(findRestart("muffleProgression"))) {
            invokeRestart("muffleProgression")
          }
        }
      )
    },
    enable = TRUE
  )
  expect_equal(x$n_success, 3L)
  # The non-blocking path passes monitor = FALSE to execute_cases,
  # so no per-case signals are emitted. progressr may still emit
  # bookkeeping signals (start of with_progress, etc.), so we
  # assert "no per-case burst" by checking n is small (0 or 1
  # bookkeeping signal, not 3 case signals).
  expect_lt(n, 3L)
})
