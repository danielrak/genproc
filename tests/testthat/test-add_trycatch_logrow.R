# Tests for add_trycatch_logrow()


# === Input validation =========================================================

test_that("rejects non-function input", {
  expect_error(add_trycatch_logrow(42), "must be a function")
  expect_error(add_trycatch_logrow("not a function"), "must be a function")
})


# === Log row structure ========================================================

test_that("returns a one-row data.frame on success", {
  fn <- add_trycatch_logrow(function(x) x + 1)
  result <- fn(10)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
})

test_that("log row contains all argument columns", {
  fn <- add_trycatch_logrow(function(a, b, c) a + b + c)
  result <- fn(1, 2, 3)

  expect_true(all(c("a", "b", "c") %in% names(result)))
  expect_equal(result$a, 1)
  expect_equal(result$b, 2)
  expect_equal(result$c, 3)
})

test_that("log row contains success, error_message, traceback, duration_secs", {
  fn <- add_trycatch_logrow(function(x) x)
  result <- fn(1)

  expected_cols <- c("success", "error_message", "traceback", "duration_secs")
  expect_true(all(expected_cols %in% names(result)))
})


# === Success cases ============================================================

test_that("success = TRUE and error fields are NA on success", {
  fn <- add_trycatch_logrow(function(x) x * 2)
  result <- fn(5)

  expect_true(result$success)
  expect_true(is.na(result$error_message))
  expect_true(is.na(result$traceback))
})

test_that("duration_secs is a positive number on success", {
  fn <- add_trycatch_logrow(function(x) {
    Sys.sleep(0.05)
    x
  })
  result <- fn(1)

  expect_true(is.numeric(result$duration_secs))
  expect_true(result$duration_secs >= 0.04)  # some tolerance
})


# === Error cases ==============================================================

test_that("success = FALSE on error", {
  fn <- add_trycatch_logrow(function(x) stop("boom"))
  result <- fn(1)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_false(result$success)
})

test_that("error_message captures the condition message", {
  fn <- add_trycatch_logrow(function(x) stop("something broke"))
  result <- fn(1)

  expect_equal(result$error_message, "something broke")
})

test_that("traceback is captured (not NA) on error", {
  fn <- add_trycatch_logrow(function(x) {
    inner_helper <- function() stop("deep error")
    inner_helper()
  })
  result <- fn(1)

  expect_false(is.na(result$traceback))
  expect_true(is.character(result$traceback))
  expect_true(nzchar(result$traceback))
})

test_that("traceback contains the failing call", {
  fn <- add_trycatch_logrow(function(x) {
    my_failing_function <- function() stop("fail here")
    my_failing_function()
  })
  result <- fn(1)

  # The traceback should mention the inner function
  expect_true(grepl("my_failing_function", result$traceback))
})

test_that("duration_secs is recorded even on error", {
  fn <- add_trycatch_logrow(function(x) {
    Sys.sleep(0.05)
    stop("after sleep")
  })
  result <- fn(1)

  expect_true(is.numeric(result$duration_secs))
  expect_true(result$duration_secs >= 0.04)
})

test_that("arguments are still captured on error", {
  fn <- add_trycatch_logrow(function(a, b) stop("nope"))
  result <- fn("hello", 42)

  expect_equal(result$a, "hello")
  expect_equal(result$b, 42)
})


# === Edge cases ===============================================================

test_that("works with a zero-argument function", {
  fn <- add_trycatch_logrow(function() 42)
  result <- fn()

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_true(result$success)
  # Should still have the meta columns
  expect_true("duration_secs" %in% names(result))
})

test_that("works with default argument values", {
  fn <- add_trycatch_logrow(function(x = 10, y = 20) x + y)
  result <- fn()  # use defaults

  expect_equal(result$x, 10)
  expect_equal(result$y, 20)
  expect_true(result$success)
})

test_that("string arguments are stored correctly in log", {
  fn <- add_trycatch_logrow(function(path) readLines(path))
  # readLines on a nonexistent file emits a warning before the error
  result <- suppressWarnings(fn("/nonexistent/file.txt"))

  expect_equal(result$path, "/nonexistent/file.txt")
  expect_false(result$success)
})
