# Tests for rerun_failed()


# === Preconditions ============================================================

test_that("rerun_failed rejects non-genproc_result r0", {
  expect_error(rerun_failed(list(), function(x) x),
               "must be a `genproc_result`")
})

test_that("rerun_failed rejects non-function f", {
  r <- genproc(function(x) x, data.frame(x = 1))
  expect_error(rerun_failed(r, "not a function"),
               "must be a function")
})

test_that("rerun_failed errors on non-materialized result", {
  skel <- structure(
    list(log = NULL, status = "running",
         reproducibility = list(mask_snapshot = data.frame(x = 1))),
    class = "genproc_result"
  )
  expect_error(rerun_failed(skel, function(x) x),
               "not materialized")
})


# === No failures: nothing to do ==============================================

test_that("rerun_failed returns NULL with a message when no failures", {
  r <- genproc(function(x) x, data.frame(x = 1:3))
  expect_message(res <- rerun_failed(r, function(x) x),
                 "No failed cases")
  expect_null(res)
})


# === Happy path ==============================================================

test_that("rerun_failed runs only the previously-failed cases", {
  # First run: even values fail.
  r0 <- genproc(
    f = function(x) if (x %% 2 == 0) stop("even") else x,
    mask = data.frame(x = 1:6)
  )
  expect_equal(r0$n_error, 3L)

  # User fixes f. Now even values are absolute-valued instead of failing.
  fixed_f <- function(x) abs(x)
  r1 <- rerun_failed(r0, fixed_f)

  expect_s3_class(r1, "genproc_result")
  # Only 3 failed cases were re-run.
  expect_equal(nrow(r1$log), 3L)
  expect_equal(r1$n_success, 3L)
  expect_equal(r1$n_error, 0L)
  # The mask values of the re-run match the originally-failing rows.
  expect_setequal(r1$log$x, c(2L, 4L, 6L))
})

test_that("rerun_failed reuses the original mask from r0$reproducibility", {
  r0 <- genproc(
    f = function(a, b) if (a == 2) stop("boom") else a + b,
    mask = data.frame(a = 1:3, b = 10:12)
  )
  r1 <- rerun_failed(r0, function(a, b) a + b)
  # The re-run sees both columns of the original mask.
  expect_setequal(names(r1$log)[2:3], c("a", "b"))
  expect_equal(r1$log$a, 2)
  expect_equal(r1$log$b, 11)
})


# === Forwarded options =======================================================

test_that("rerun_failed forwards track_inputs", {
  r0 <- genproc(
    f = function(x) if (x %% 2 == 0) stop("even") else x,
    mask = data.frame(x = 1:4)
  )
  # Disable input tracking on the rerun.
  r1 <- rerun_failed(r0, function(x) abs(x), track_inputs = FALSE)
  expect_null(r1$reproducibility$inputs)
})


# === Bad case_ids =============================================================

test_that("rerun_failed errors clearly on unparseable case_ids", {
  r0 <- genproc(
    f = function(x) if (x == 1) stop("boom") else x,
    mask = data.frame(x = 1:3)
  )
  r0$log$case_id[!r0$log$success] <- "garbage_id"
  expect_error(rerun_failed(r0, function(x) abs(x)),
               "case_ids of the form")
})
