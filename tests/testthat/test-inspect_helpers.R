# Tests for errors() and summary.genproc_result()


# === errors() ================================================================

test_that("errors() returns the failed-case rows of the log", {
  r <- genproc(
    f = function(x) if (x %% 2 == 0) stop("even") else x,
    mask = data.frame(x = 1:6)
  )
  e <- errors(r)
  expect_s3_class(e, "data.frame")
  expect_equal(nrow(e), 3L)
  expect_true(all(e$success == FALSE))
  expect_setequal(e$x, c(2L, 4L, 6L))
  expect_true(all(e$error_message == "even"))
})

test_that("errors() returns an empty data.frame when there are no failures", {
  r <- genproc(function(x) x, data.frame(x = 1:3))
  e <- errors(r)
  expect_s3_class(e, "data.frame")
  expect_equal(nrow(e), 0L)
  # Same columns as the log.
  expect_setequal(names(e), names(r$log))
})

test_that("errors() has the same columns as result$log", {
  r <- genproc(function(x) if (x == 2) stop("boom") else x,
               data.frame(x = 1:3))
  e <- errors(r)
  expect_equal(names(e), names(r$log))
})

test_that("errors() returns NULL with a message on a non-materialized result", {
  # Build a synthetic skeleton like a non-blocking result before await.
  skel <- structure(
    list(log = NULL, status = "running"),
    class = "genproc_result"
  )
  expect_message(res <- errors(skel), "not materialized")
  expect_null(res)
})


# === summary() ===============================================================

test_that("summary() returns a genproc_result_summary with expected fields", {
  r <- genproc(
    f = function(x) if (x %% 2 == 0) stop("even") else x,
    mask = data.frame(x = 1:6)
  )
  s <- summary(r)
  expect_s3_class(s, "genproc_result_summary")
  expect_true(s$materialized)
  expect_equal(s$status, "done")
  expect_equal(s$n_cases, 6L)
  expect_equal(s$n_success, 3L)
  expect_equal(s$n_error, 3L)
  expect_equal(s$success_rate, 0.5)
  expect_s3_class(s$top_errors, "data.frame")
})

test_that("summary() top_errors ranks by occurrence and respects the limit", {
  r <- genproc(
    f = function(x) {
      if (x <= 4) stop("alpha")
      if (x <= 6) stop("beta")
      stop("gamma")
    },
    mask = data.frame(x = 1:8)
  )
  s <- summary(r)
  # "alpha" 4x, "beta" 2x, "gamma" 2x.
  expect_equal(s$top_errors$count[1], 4L)
  expect_equal(s$top_errors$error_message[1], "alpha")
  expect_true(all(diff(s$top_errors$count) <= 0))  # sorted desc

  s2 <- summary(r, top_errors = 2L)
  expect_equal(nrow(s2$top_errors), 2L)
})

test_that("summary() handles a fully successful run (no top_errors)", {
  r <- genproc(function(x) x, data.frame(x = 1:3))
  s <- summary(r)
  expect_equal(s$n_error, 0L)
  expect_equal(nrow(s$top_errors), 0L)
})

test_that("summary() rejects invalid top_errors", {
  r <- genproc(function(x) x, data.frame(x = 1))
  expect_error(summary(r, top_errors = -1), "non-negative")
  expect_error(summary(r, top_errors = NA), "non-negative")
  expect_error(summary(r, top_errors = c(1, 2)), "non-negative")
})

test_that("summary() flags a non-materialized run", {
  skel <- structure(
    list(log = NULL, status = "running"),
    class = "genproc_result"
  )
  s <- summary(skel)
  expect_false(s$materialized)
  expect_equal(s$status, "running")
  expect_equal(nrow(s$top_errors), 0L)
})

test_that("summary print method renders the digest", {
  r <- genproc(
    f = function(x) if (x %% 2 == 0) stop("even") else x,
    mask = data.frame(x = 1:6)
  )
  s <- summary(r)
  out <- paste(capture.output(print(s)), collapse = "\n")
  expect_match(out, "genproc result summary")
  expect_match(out, "Cases\\s+:\\s+6")
  expect_match(out, "Success\\s+:\\s+50%")
  expect_match(out, "Top errors")
  expect_match(out, "even")
})

test_that("summary print method handles non-materialized result", {
  skel <- structure(
    list(log = NULL, status = "running"),
    class = "genproc_result"
  )
  s <- summary(skel)
  out <- paste(capture.output(print(s)), collapse = "\n")
  expect_match(out, "not materialized")
  expect_match(out, "await")
})

test_that("duration_stats records the slowest case", {
  fast <- function(x) x
  slow_one <- function(x) {
    if (x == 3) Sys.sleep(0.05)
    x
  }
  r <- genproc(slow_one, data.frame(x = 1:5))
  s <- summary(r)
  expect_equal(s$duration_stats$slowest_case_id, "case_0003")
  expect_true(s$duration_stats$max >= 0.04)
})
