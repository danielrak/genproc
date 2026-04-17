# Tests for genproc()


# === Input validation =========================================================

test_that("rejects non-function f", {
  expect_error(genproc(42, data.frame(x = 1)), "must be a function")
})

test_that("rejects non-data.frame mask", {
  expect_error(genproc(function(x) x, list(x = 1)), "must be a data.frame")
})

test_that("rejects empty mask", {
  expect_error(genproc(function(x) x, data.frame(x = numeric(0))),
               "at least one row")
})

test_that("rejects missing param without default and not in mask", {
  fn <- function(x, y) x + y
  mask <- data.frame(x = 1)
  expect_error(genproc(fn, mask), "Parameter `y`")
})


# === Return structure =========================================================

test_that("returns a genproc_result with expected components", {
  result <- genproc(function(x) x, data.frame(x = 1))

  expect_s3_class(result, "genproc_result")
  expect_true(is.list(result))
  expected <- c("log", "reproducibility", "n_success",
                "n_error", "duration_total_secs", "status")
  expect_true(all(expected %in% names(result)))
})

test_that("status is 'done' for synchronous runs", {
  result <- genproc(function(x) x, data.frame(x = 1))
  expect_equal(result$status, "done")
})

test_that("log is a data.frame with one row per case", {
  mask <- data.frame(x = c(1, 2, 3))
  result <- genproc(function(x) x * 2, mask)

  expect_s3_class(result$log, "data.frame")
  expect_equal(nrow(result$log), 3)
})

test_that("log contains case_id, success, error_message, traceback, duration_secs", {
  result <- genproc(function(x) x, data.frame(x = 1))

  expected_cols <- c("case_id", "success", "error_message",
                     "traceback", "duration_secs")
  expect_true(all(expected_cols %in% names(result$log)))
})

test_that("log contains parameter columns", {
  result <- genproc(function(a, b) a + b,
                    data.frame(a = 1, b = 2))

  expect_true(all(c("a", "b") %in% names(result$log)))
  expect_equal(result$log$a, 1)
  expect_equal(result$log$b, 2)
})

test_that("case_id is first column", {
  result <- genproc(function(x) x, data.frame(x = 1))
  expect_equal(names(result$log)[1], "case_id")
})


# === Successful execution =====================================================

test_that("all-success run has correct counts", {
  result <- genproc(
    function(x) x + 1,
    data.frame(x = c(1, 2, 3))
  )

  expect_equal(result$n_success, 3)
  expect_equal(result$n_error, 0)
  expect_true(all(result$log$success))
})

test_that("case_ids are sequential and zero-padded", {
  mask <- data.frame(x = 1:3)
  result <- genproc(function(x) x, mask)

  expect_equal(result$log$case_id,
               c("case_0001", "case_0002", "case_0003"))
})

test_that("duration_total_secs is non-negative", {
  result <- genproc(function(x) x, data.frame(x = 1))

  expect_true(is.numeric(result$duration_total_secs))
  expect_true(result$duration_total_secs >= 0)
})


# === Error handling ===========================================================

test_that("errors in individual cases do not stop the run", {
  fn <- function(x) {
    if (x == 2) stop("case 2 failed")
    x * 10
  }
  result <- genproc(fn, data.frame(x = c(1, 2, 3)))

  expect_equal(nrow(result$log), 3)
  expect_equal(result$n_success, 2)
  expect_equal(result$n_error, 1)
})

test_that("error_message is captured for failing cases", {
  fn <- function(x) stop("boom")
  result <- genproc(fn, data.frame(x = c(1, 2)))

  expect_true(all(result$log$error_message == "boom"))
})

test_that("traceback is captured for failing cases", {
  fn <- function(x) {
    inner <- function() stop("deep")
    inner()
  }
  result <- genproc(fn, data.frame(x = 1))

  expect_false(is.na(result$log$traceback[1]))
  expect_true(grepl("inner", result$log$traceback[1]))
})

test_that("successful cases have NA error_message and traceback", {
  result <- genproc(function(x) x, data.frame(x = 1))

  expect_true(is.na(result$log$error_message[1]))
  expect_true(is.na(result$log$traceback[1]))
})


# === Parameter matching =======================================================

test_that("extra mask columns are silently ignored", {
  result <- genproc(
    function(x) x * 2,
    data.frame(x = c(1, 2), extra = c("a", "b"))
  )

  expect_equal(nrow(result$log), 2)
  expect_true(all(result$log$success))
})

test_that("params with defaults not in mask use defaults", {
  fn <- function(x, multiplier = 10) x * multiplier
  result <- genproc(fn, data.frame(x = c(1, 2, 3)))

  expect_equal(nrow(result$log), 3)
  expect_true(all(result$log$success))
})


# === f_mapping integration ====================================================

test_that("f_mapping renames parameters before execution", {
  fn <- function(param_1, param_2) param_1 + param_2
  mask <- data.frame(x = c(1, 2), y = c(10, 20))
  result <- genproc(fn, mask,
                    f_mapping = c(param_1 = "x", param_2 = "y"))

  expect_equal(nrow(result$log), 2)
  expect_true(all(result$log$success))
  expect_equal(result$log$x, c(1, 2))
  expect_equal(result$log$y, c(10, 20))
})


# === Reproducibility ==========================================================

test_that("reproducibility captures R version", {
  result <- genproc(function(x) x, data.frame(x = 1))

  repro <- result$reproducibility
  expect_true("r_version" %in% names(repro))
  expect_equal(repro$r_version, R.version.string)
})

test_that("reproducibility captures packages", {
  result <- genproc(function(x) x, data.frame(x = 1))

  repro <- result$reproducibility
  expect_true("packages" %in% names(repro))
  expect_true(is.character(repro$packages))
})

test_that("reproducibility captures mask snapshot", {
  mask <- data.frame(x = c(1, 2), y = c("a", "b"),
                     stringsAsFactors = FALSE)
  result <- genproc(function(x, y) paste(x, y), mask)

  expect_equal(result$reproducibility$mask_snapshot, mask)
})

test_that("reproducibility captures timestamp", {
  before <- Sys.time()
  result <- genproc(function(x) x, data.frame(x = 1))
  after <- Sys.time()

  ts <- result$reproducibility$timestamp
  expect_true(inherits(ts, "POSIXct"))
  expect_true(ts >= before && ts <= after)
})


# === Full pipeline integration ================================================

test_that("full pipeline: expression -> function -> rename -> mask -> genproc", {
  e <- new.env(parent = baseenv())
  e$input_val <- 42
  e$factor <- 2

  # Step 1: expression to function
  fn <- from_example_to_function(
    expression(input_val * factor),
    env = e
  )

  # Step 2: derive template mask
  template <- from_function_to_mask(fn)
  expect_equal(template$param_1, 42)
  expect_equal(template$param_2, 2)

  # Step 3: build full mask with multiple cases
  mask <- data.frame(
    value   = c(1, 5, 10, 100),
    factor  = c(2, 3, 10, 0)
  )

  # Step 4: run with f_mapping
  result <- genproc(fn, mask,
                    f_mapping = c(param_1 = "value", param_2 = "factor"))

  expect_equal(nrow(result$log), 4)
  expect_equal(result$n_success, 4)
  expect_equal(result$n_error, 0)
  expect_equal(result$log$case_id,
               c("case_0001", "case_0002", "case_0003", "case_0004"))
})

test_that("mixed success/error pipeline", {
  fn <- function(path) {
    if (!file.exists(path)) stop(paste("file not found:", path))
    readLines(path)
  }

  mask <- data.frame(path = c(
    system.file("DESCRIPTION", package = "base"),
    "/nonexistent/file.txt",
    system.file("DESCRIPTION", package = "utils")
  ), stringsAsFactors = FALSE)

  result <- suppressWarnings(genproc(fn, mask))

  expect_equal(nrow(result$log), 3)
  expect_equal(result$n_success, 2)
  expect_equal(result$n_error, 1)
  expect_true(result$log$success[1])
  expect_false(result$log$success[2])
  expect_true(result$log$success[3])
  expect_true(grepl("not found", result$log$error_message[2]))
})


# === print method ==============================================================

test_that("print.genproc_result outputs summary and returns invisibly", {
  result <- genproc(function(x) x, data.frame(x = c(1, 2, 3)))

  out <- capture.output(ret <- print(result))
  expect_identical(ret, result)
  expect_true(any(grepl("genproc result", out)))
  expect_true(any(grepl("done", out)))
  expect_true(any(grepl("3", out)))
})

test_that("print.genproc_result handles a running skeleton (NULL fields)", {
  skeleton <- structure(
    list(
      log                 = NULL,
      reproducibility     = list(),
      n_success           = NULL,
      n_error             = NULL,
      duration_total_secs = NULL,
      status              = "running"
    ),
    class = "genproc_result"
  )

  expect_silent(out <- capture.output(print(skeleton)))
  expect_true(any(grepl("running", out)))
  expect_true(any(grepl("pending", out)))
})

test_that("print.genproc_result surfaces wrapper error message", {
  errored <- structure(
    list(
      log                 = NULL,
      reproducibility     = list(),
      n_success           = NULL,
      n_error             = NULL,
      duration_total_secs = NULL,
      status              = "error",
      error_message       = "wrapper future crashed"
    ),
    class = "genproc_result"
  )

  expect_silent(out <- capture.output(print(errored)))
  expect_true(any(grepl("error", out)))
  expect_true(any(grepl("wrapper future crashed", out)))
})
