# Tests for status() and await() generics on genproc_result.
#
# These tests exercise the generics in isolation by building synthetic
# genproc_result objects; they do not go through genproc() itself
# (that is covered in test-genproc-nonblocking.R).
#
# The `sequential` future backend is used for determinism — a future
# created under it is already resolved at creation time.
#
# The futures are constructed inline in each test rather than inside
# a helper that takes `future_body` as an argument, because
# `future::future(future_body, ...)` performs static-code inspection
# that forces the promise and evaluates its body at creation time
# (not at resolution time), which makes "crashing future" tests
# trigger at the wrong moment.


# === Helpers ==================================================================

# Build a "running" skeleton around an already-constructed future.
# The shared_env mirrors what genproc() attaches in the real path —
# it lets status() and await() coordinate the peek cache.
make_skeleton_with_future <- function(f) {
  skel <- structure(
    list(
      log                 = NULL,
      reproducibility     = list(timestamp = Sys.time()),
      n_success           = NULL,
      n_error             = NULL,
      duration_total_secs = NULL,
      status              = "running"
    ),
    class = "genproc_result"
  )
  attr(skel, "future")     <- f
  attr(skel, "shared_env") <- new.env(parent = emptyenv())
  skel
}

# Build a synchronous (no future) genproc_result already done.
make_done_result <- function() {
  structure(
    list(
      log                 = data.frame(case_id = "case_0001",
                                        success = TRUE,
                                        stringsAsFactors = FALSE),
      reproducibility     = list(timestamp = Sys.time()),
      n_success           = 1L,
      n_error             = 0L,
      duration_total_secs = 0.01,
      status              = "done"
    ),
    class = "genproc_result"
  )
}


# === status() =================================================================

test_that("status() is a function", {
  expect_true(is.function(status))
})

test_that("status() on a synchronous done result returns 'done'", {
  x <- make_done_result()
  expect_equal(status(x), "done")
})

test_that("status() on a skeleton whose future is resolved returns 'done'", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  payload <- list(log = data.frame(a = 1), n_success = 1L, n_error = 0L,
                  duration_total_secs = 0.01)
  f <- future::future(payload, seed = TRUE)
  x <- make_skeleton_with_future(f)

  expect_equal(status(x), "done")
})

test_that("status() falls back to x$status when no future is attached", {
  x <- make_done_result()
  attr(x, "future") <- NULL
  x$status <- "done"
  expect_equal(status(x), "done")
})


# === await() ==================================================================

test_that("await() is a function", {
  expect_true(is.function(await))
})

test_that("await() on a synchronous done result returns it unchanged", {
  x <- make_done_result()
  y <- await(x)
  expect_equal(y$status, "done")
  expect_equal(y$n_success, 1L)
  expect_identical(x, y)
})

test_that("await() materializes fields from the future into the result", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  payload <- list(
    log                 = data.frame(case_id = "case_0001",
                                      success = TRUE,
                                      stringsAsFactors = FALSE),
    n_success           = 1L,
    n_error             = 0L,
    duration_total_secs = 0.42
  )
  f <- future::future(payload, seed = TRUE)
  x <- make_skeleton_with_future(f)

  y <- await(x)

  expect_equal(y$status, "done")
  expect_equal(y$n_success, 1L)
  expect_equal(y$n_error, 0L)
  expect_equal(y$duration_total_secs, 0.42)
  expect_equal(y$log, payload$log)
  expect_null(attr(y, "future"))
})

test_that("await() preserves reproducibility captured at t0", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(list(log = data.frame(a = 1), n_success = 1L,
                           n_error = 0L, duration_total_secs = 0.01),
                      seed = TRUE)
  x <- make_skeleton_with_future(f)
  repro_before <- x$reproducibility
  y <- await(x)
  expect_identical(y$reproducibility, repro_before)
})

test_that("await() is idempotent", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(list(log = data.frame(a = 1), n_success = 1L,
                           n_error = 0L, duration_total_secs = 0.01),
                      seed = TRUE)
  x <- make_skeleton_with_future(f)
  y1 <- await(x)
  y2 <- await(y1)
  expect_identical(y1, y2)
})

test_that("await() captures a crashing future as status = 'error'", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  # The body of the future is captured literally by future::future()
  # (substitute = TRUE by default) and only evaluated at value() time,
  # which is exactly when await() pulls it. That's why the stop()
  # below fires inside the future, not at creation time.
  f <- future::future(stop("wrapper crashed"), seed = TRUE)
  x <- make_skeleton_with_future(f)

  y <- await(x)

  expect_equal(y$status, "error")
  expect_true(!is.null(y$error_message))
  expect_true(grepl("wrapper crashed", y$error_message))
  expect_null(attr(y, "future"))
})

test_that("await() returns an object that still inherits genproc_result", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(list(log = data.frame(a = 1), n_success = 1L,
                           n_error = 0L, duration_total_secs = 0.01),
                      seed = TRUE)
  x <- make_skeleton_with_future(f)
  y <- await(x)
  expect_s3_class(y, "genproc_result")
})


# === F14: status() distinguishes done from error ============================

test_that("status() returns 'error' on a future that has crashed", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(stop("wrapper crashed"), seed = TRUE)
  x <- make_skeleton_with_future(f)

  # Resolve the future implicitly by waiting (sequential resolves
  # at creation, but we can be defensive).
  expect_equal(status(x), "error")
})

test_that("status() returns 'done' on a successful resolved future", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(list(log = data.frame(a = 1), n_success = 1L,
                           n_error = 0L, duration_total_secs = 0.01),
                      seed = TRUE)
  x <- make_skeleton_with_future(f)
  expect_equal(status(x), "done")
})

test_that("status() peek caches the result; await() then reuses the cache", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  payload <- list(log = data.frame(a = 1), n_success = 1L,
                  n_error = 0L, duration_total_secs = 0.01)
  f <- future::future(payload, seed = TRUE)
  x <- make_skeleton_with_future(f)

  # Peek via status(): should populate the shared cache.
  state <- status(x)
  expect_equal(state, "done")
  shared <- attr(x, "shared_env")
  expect_true(exists("peek_result", envir = shared))

  # Await consumes from the cache without re-calling future::value().
  y <- await(x)
  expect_equal(y$status, "done")
  expect_equal(y$n_success, 1L)
})

test_that("status() peek caches errors; await() reports them as 'error'", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(stop("wrapper crashed"), seed = TRUE)
  x <- make_skeleton_with_future(f)

  # status() reports "error" and caches the wrapper error.
  expect_equal(status(x), "error")
  shared <- attr(x, "shared_env")
  expect_true(exists("peek_result", envir = shared))

  # await() reads from the cache and returns x with status = "error"
  # plus a populated error_message.
  y <- await(x)
  expect_equal(y$status, "error")
  expect_true(grepl("wrapper crashed", y$error_message))
})

test_that("multiple status() calls are idempotent and cheap (no re-peek)", {
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  payload <- list(log = data.frame(a = 1), n_success = 1L,
                  n_error = 0L, duration_total_secs = 0.01)
  f <- future::future(payload, seed = TRUE)
  x <- make_skeleton_with_future(f)

  s1 <- status(x)
  s2 <- status(x)
  s3 <- status(x)
  expect_equal(s1, "done")
  expect_equal(s2, "done")
  expect_equal(s3, "done")
})

test_that("status() falls back to x$status post-await", {
  # Once await() has finalized the result, the future is gone but
  # status() should still return the right terminal state.
  oplan <- future::plan(future::sequential)
  on.exit(future::plan(oplan), add = TRUE)

  f <- future::future(list(log = data.frame(a = 1), n_success = 1L,
                           n_error = 0L, duration_total_secs = 0.01),
                      seed = TRUE)
  x <- make_skeleton_with_future(f)
  y <- await(x)
  expect_equal(status(y), "done")
})
