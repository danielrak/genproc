# Tests for the non-blocking execution layer of genproc().
#
# Most tests use nonblocking_spec(strategy = "sequential") so that the
# wrapper future resolves immediately at creation time — the code path
# is exercised deterministically, no real background session, no timing
# flakiness.
#
# A real multisession non-blocking test would need skip_on_cran() and
# polling; it is not included here because the deterministic path
# already covers the contract.


# === Argument validation ======================================================

test_that("nonblocking must be NULL or a genproc_nonblocking_spec", {
  expect_error(
    genproc(function(x) x, data.frame(x = 1), nonblocking = TRUE),
    "genproc_nonblocking_spec"
  )
  expect_error(
    genproc(function(x) x, data.frame(x = 1), nonblocking = list()),
    "genproc_nonblocking_spec"
  )
  expect_error(
    genproc(function(x) x, data.frame(x = 1),
            nonblocking = "multisession"),
    "genproc_nonblocking_spec"
  )
})


# === Immediate skeleton =======================================================

test_that("nonblocking run returns immediately with a genproc_result", {
  x <- genproc(function(x) x, data.frame(x = 1:3),
               nonblocking = nonblocking_spec(strategy = "sequential"))
  expect_s3_class(x, "genproc_result")
})

test_that("skeleton carries reproducibility captured synchronously", {
  x <- genproc(function(x) x, data.frame(x = 1:3),
               nonblocking = nonblocking_spec(strategy = "sequential"))
  expect_false(is.null(x$reproducibility))
  expect_false(is.null(x$reproducibility$timestamp))
  expect_false(is.null(x$reproducibility$mask_snapshot))
})

test_that("skeleton has a future attached as attribute", {
  x <- genproc(function(x) x, data.frame(x = 1),
               nonblocking = nonblocking_spec(strategy = "sequential"))
  expect_false(is.null(attr(x, "future")))
  expect_s3_class(attr(x, "future"), "Future")
})


# === Parity with synchronous run after await() ================================

test_that("after await(), log is identical to synchronous run", {
  mask <- data.frame(x = c(1, 2, 3, 4))
  sync_result <- genproc(function(x) x * 10, mask)
  nb_result   <- genproc(function(x) x * 10, mask,
                         nonblocking = nonblocking_spec(
                           strategy = "sequential"))
  nb_result <- await(nb_result)

  cmp_cols <- setdiff(names(sync_result$log), "duration_secs")
  expect_equal(nb_result$log[, cmp_cols],
               sync_result$log[, cmp_cols])
  expect_equal(nb_result$n_success, sync_result$n_success)
  expect_equal(nb_result$n_error,   sync_result$n_error)
})

test_that("case_id order is preserved through await()", {
  mask <- data.frame(x = 1:5)
  result <- genproc(function(x) x, mask,
                    nonblocking = nonblocking_spec(
                      strategy = "sequential"))
  result <- await(result)

  expect_equal(result$log$case_id,
               c("case_0001", "case_0002", "case_0003",
                 "case_0004", "case_0005"))
  expect_equal(result$log$x, 1:5)
})


# === Error handling ===========================================================

test_that("errors in individual cases are captured in log, not wrapper", {
  fn <- function(x) {
    if (x == 2) stop("case 2 failed")
    x * 10
  }
  result <- genproc(fn, data.frame(x = c(1, 2, 3)),
                    nonblocking = nonblocking_spec(
                      strategy = "sequential"))
  result <- await(result)

  expect_equal(result$status, "done")
  expect_equal(result$n_success, 2)
  expect_equal(result$n_error, 1)
  expect_equal(result$log$error_message[2], "case 2 failed")
})

test_that("status() returns 'done' once the sequential future has resolved", {
  x <- genproc(function(x) x, data.frame(x = 1:2),
               nonblocking = nonblocking_spec(strategy = "sequential"))
  # sequential plan => future already resolved
  expect_equal(status(x), "done")
})


# === Reproducibility snapshot records the non-blocking spec ===================

test_that("sync run: reproducibility$nonblocking is NULL", {
  result <- genproc(function(x) x, data.frame(x = 1))
  expect_null(result$reproducibility$nonblocking)
})

test_that("non-blocking run: reproducibility$nonblocking records the spec", {
  # We use "stats" (base R) rather than a Suggests package so this test
  # also passes under R CMD check --no-suggests / rhub nosuggests:
  # the worker library() call requires the package to actually exist.
  spec <- nonblocking_spec(strategy = "sequential",
                           packages = "stats")
  result <- genproc(function(x) x, data.frame(x = c(1, 2)),
                    nonblocking = spec)
  result <- await(result)

  nb <- result$reproducibility$nonblocking
  expect_false(is.null(nb))
  expect_equal(nb$strategy, "sequential")
  expect_equal(nb$packages, "stats")
})


# === Composition: parallel × nonblocking ======================================

test_that("composition: parallel + nonblocking (both sequential) -> parity", {
  mask <- data.frame(x = 1:4)
  fn <- function(x) x * 10
  sync_result <- genproc(fn, mask)

  composed <- genproc(
    fn, mask,
    parallel    = parallel_spec(strategy = "sequential"),
    nonblocking = nonblocking_spec(strategy = "sequential")
  )
  composed <- await(composed)

  cmp_cols <- setdiff(names(sync_result$log), "duration_secs")
  expect_equal(composed$log[, cmp_cols],
               sync_result$log[, cmp_cols])
  expect_equal(composed$n_success, sync_result$n_success)
  expect_equal(composed$n_error, sync_result$n_error)
})

test_that("composition: reproducibility captures both specs", {
  result <- genproc(
    function(x) x, data.frame(x = 1:2),
    parallel    = parallel_spec(strategy = "sequential", seed = 1L),
    nonblocking = nonblocking_spec(strategy = "sequential")
  )
  result <- await(result)

  expect_false(is.null(result$reproducibility$parallel))
  expect_false(is.null(result$reproducibility$nonblocking))
  expect_equal(result$reproducibility$parallel$strategy,    "sequential")
  expect_equal(result$reproducibility$nonblocking$strategy, "sequential")
})


# === Plan restoration =========================================================

test_that("temporary plan set by nonblocking strategy is restored on exit", {
  skip_if_not_installed("future")

  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)

  x <- genproc(function(x) x, data.frame(x = 1:2),
               nonblocking = nonblocking_spec(strategy = "sequential"))
  x <- await(x)

  expect_true(inherits(future::plan(), "sequential"))
})


# === Regression: multisession future must not be canceled =====================

test_that("multisession non-blocking run materializes without cancellation", {
  # Regression: previously `genproc()` called `on.exit(future::plan(oplan))`
  # in the non-blocking path, which shut down the multisession cluster
  # and canceled the pending wrapper future. `await()` then surfaced a
  # "Future was canceled" error. This test exercises the full real
  # multisession path end-to-end.
  skip_on_cran()
  skip_if_not_installed("future")
  skip_if_not_installed("future.apply")
  # Multisession workers load packages via library(), which only sees
  # installed packages. devtools::load_all() does NOT install, so this
  # test is skipped in dev mode — run it after R CMD INSTALL.
  skip_if_not(
    "genproc" %in% rownames(utils::installed.packages()),
    "genproc not installed — skip (multisession needs installed pkg)"
  )

  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)

  x <- genproc(function(x) x * 2, data.frame(x = 1:3),
               nonblocking = nonblocking_spec(strategy = "multisession"))
  x <- await(x)

  expect_equal(x$status, "done")
  expect_equal(x$n_success, 3L)
  expect_equal(x$n_error, 0L)
  expect_equal(x$log$x, 1:3)
})
