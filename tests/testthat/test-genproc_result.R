# Tests for the genproc_result S3 print method.
#
# Print method behavior is exercised via capture.output() and grep on
# the rendered text. We don't assert byte-for-byte output (that would
# be too brittle as we evolve the layout); instead we assert
# presence / absence of marker phrases.


# Helper: build a minimal genproc_result with a custom shape, used to
# stress specific branches of the print method without running real
# parallel workers.
mock_result <- function(parallel = NULL,
                        wall = 0.1,
                        per_case_durations = c(0.05),
                        status = "done",
                        n_success = NULL,
                        n_error   = NULL,
                        log_extra = NULL) {
  log <- data.frame(
    case_id       = sprintf("case_%04d", seq_along(per_case_durations)),
    success       = TRUE,
    error_message = NA_character_,
    traceback     = NA_character_,
    duration_secs = per_case_durations,
    stringsAsFactors = FALSE
  )
  if (!is.null(log_extra)) {
    for (nm in names(log_extra)) log[[nm]] <- log_extra[[nm]]
  }
  if (is.null(n_success)) n_success <- sum(log$success)
  if (is.null(n_error))   n_error   <- sum(!log$success)

  structure(
    list(
      log                 = log,
      reproducibility     = list(parallel = parallel),
      n_success           = n_success,
      n_error             = n_error,
      duration_total_secs = wall,
      status              = status
    ),
    class = "genproc_result"
  )
}


# === Basic print ============================================================

test_that("print displays Status, Cases, Duration", {
  r <- mock_result()
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "genproc result")
  expect_match(out, "Status\\s*:")
  expect_match(out, "Cases\\s*:")
  expect_match(out, "Duration\\s*:")
})

test_that("print returns its argument invisibly", {
  r <- mock_result()
  capture.output(res <- print(r))
  expect_identical(res, r)
})


# === F12: parallel-overhead hint =============================================

test_that("F12 hint fires when workers known and efficiency < 50%", {
  # 4 workers, 1.3s of cumulative work, wall 1.4s.
  # Ideal = 1.3/4 = 0.325s. Efficiency = 0.325/1.4 = 23% — far below 50%.
  r <- mock_result(
    parallel = list(strategy = "multisession", workers = 4L),
    wall = 1.4,
    per_case_durations = rep(1.3 / 87, 87L)
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "parallel startup dominated")
  expect_match(out, "4 workers")
  expect_match(out, "23% efficiency")
  expect_match(out, "consider sequential")
})

test_that("F12 hint fires (workers unknown, fallback metric) when wall > 1.2 * cumul", {
  # power-user: workers = NULL in the spec. Fallback: wall vs cumul.
  r <- mock_result(
    parallel = list(strategy = "multisession", workers = NULL),
    wall = 1.5,
    per_case_durations = rep(0.01, 4L)  # cumul = 0.04
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "parallel startup dominated")
  expect_match(out, "cumulative work")  # the fallback detail format
})

test_that("F12 hint does NOT fire on healthy parallel runs (high efficiency)", {
  # 4 workers, 4s cumulative work, wall 1.2s. Ideal = 1.0s.
  # Efficiency = 1.0/1.2 = 83% — above 50%, healthy.
  r <- mock_result(
    parallel = list(strategy = "multisession", workers = 4L),
    wall = 1.2,
    per_case_durations = rep(1.0, 4L)
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_false(grepl("parallel startup dominated", out))
})

test_that("F12 hint does NOT fire in sequential mode (no parallel spec)", {
  r <- mock_result(
    parallel = NULL,
    wall = 1.5,
    per_case_durations = rep(0.01, 4L)
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_false(grepl("parallel startup dominated", out))
})

test_that("F12 hint does NOT fire below the wall-clock noise floor", {
  # Below 0.5s wall, comparison is too noisy.
  r <- mock_result(
    parallel = list(strategy = "multisession", workers = 4L),
    wall = 0.4,
    per_case_durations = rep(0.01, 4L)
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_false(grepl("parallel startup dominated", out))
})

test_that("F12 fallback metric does NOT fire on a marginal slowdown (< 1.2x)", {
  # workers unknown, wall 1.1s vs cumul 1.0s = 1.1x. Below 1.2x threshold.
  r <- mock_result(
    parallel = list(strategy = "multisession", workers = NULL),
    wall = 1.1,
    per_case_durations = rep(0.25, 4L)
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_false(grepl("parallel startup dominated", out))
})


# === F5: enriched print fields ===============================================

# Helper: build a result with a fully-populated reproducibility snapshot.
mock_result_with_repro <- function(parallel = NULL, nonblocking = NULL,
                                    wall = 0.1) {
  r <- mock_result(parallel = parallel, wall = wall)
  r$reproducibility$timestamp   <- as.POSIXct("2026-04-29 12:34:56",
                                                tz = "UTC")
  r$reproducibility$nonblocking <- nonblocking
  r
}


test_that("print includes a Started timestamp from the repro snapshot", {
  r <- mock_result_with_repro()
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "Started")
  # Timestamp formatted ISO-ish (locale-tolerant).
  expect_match(out, "2026-04-29")
})

test_that("print Mode line shows 'sequential' on a sequential run", {
  r <- mock_result_with_repro()
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "Mode\\s*:\\s*sequential")
})

test_that("print Mode line shows worker count when parallel was used", {
  r <- mock_result_with_repro(
    parallel = list(strategy = "multisession", workers = 4L)
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "Mode\\s*:")
  expect_match(out, "parallel")
  expect_match(out, "4 workers")
})

test_that("print Mode line composes non-blocking + parallel", {
  r <- mock_result_with_repro(
    parallel    = list(strategy = "multisession", workers = 6L),
    nonblocking = list(strategy = "multisession")
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "non-blocking \\+ ")
  expect_match(out, "6 workers")
})

test_that("print emits an errors()/summary() hint when there are failures", {
  r <- mock_result_with_repro()
  r$n_error   <- 2L
  r$n_success <- 0L
  r$log <- data.frame(
    case_id       = c("case_0001", "case_0002"),
    success       = c(FALSE, FALSE),
    error_message = c("a", "b"),
    traceback     = c("x", "y"),
    duration_secs = c(0.01, 0.01),
    stringsAsFactors = FALSE
  )
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_match(out, "errors\\(")
  expect_match(out, "summary\\(")
})

test_that("print does NOT emit the errors() hint on a fully-successful run", {
  r <- mock_result_with_repro()
  out <- paste(capture.output(print(r)), collapse = "\n")
  expect_false(grepl("errors\\(", out))
})
