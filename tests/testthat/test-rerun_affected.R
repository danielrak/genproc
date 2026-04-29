# Tests for rerun_affected()


# Helper: produce two runs where exactly the first file has been
# mutated, plus the function used in both runs.
make_two_runs_with_drift <- function(n = 3L) {
  d <- tempfile("rerun_affected_"); dir.create(d)
  paths <- file.path(d, sprintf("data_%02d.csv", seq_len(n)))
  for (p in paths) writeLines("x,y\n1,2\n", p)

  mask <- data.frame(csv_in = paths, stringsAsFactors = FALSE)
  f <- function(csv_in) nrow(read.csv(csv_in))

  r0 <- genproc(f, mask)
  Sys.sleep(1.1)
  writeLines("x,y\n1,2\n3,4\n5,6\n", paths[1])  # only paths[1] changes
  r1 <- genproc(f, mask)

  list(r0 = r0, r1 = r1, paths = paths, f = f, mask = mask)
}


# === Preconditions ============================================================

test_that("rerun_affected rejects non-genproc_result r0", {
  d <- diff_inputs(
    genproc(function(x) x, data.frame(x = 1)),
    genproc(function(x) x, data.frame(x = 1))
  )
  expect_error(rerun_affected(list(), d, function(x) x),
               "must be a `genproc_result`")
})

test_that("rerun_affected rejects non-input-diff diff", {
  r0 <- genproc(function(x) x, data.frame(x = 1))
  expect_error(rerun_affected(r0, list(), function(x) x),
               "must be a `genproc_input_diff`")
})

test_that("rerun_affected rejects non-function f", {
  ctx <- make_two_runs_with_drift()
  d <- diff_inputs(ctx$r0, ctx$r1)
  expect_error(rerun_affected(ctx$r0, d, "not a function"),
               "must be a function")
})


# === Empty diff: nothing to do ===============================================

test_that("rerun_affected returns NULL with a message on empty diff", {
  ctx <- make_two_runs_with_drift()
  # Build a no-op diff (compare a run with itself).
  d_empty <- diff_inputs(ctx$r0, ctx$r0)
  expect_message(
    res <- rerun_affected(ctx$r0, d_empty, ctx$f),
    "No cases affected"
  )
  expect_null(res)
})


# === Happy path ==============================================================

test_that("rerun_affected runs only the impacted cases", {
  ctx <- make_two_runs_with_drift()  # only paths[1] changes
  d <- diff_inputs(ctx$r0, ctx$r1)

  refreshed <- rerun_affected(ctx$r0, d, ctx$f)

  expect_s3_class(refreshed, "genproc_result")
  expect_equal(nrow(refreshed$log), 1)            # only one case re-run
  expect_equal(refreshed$n_success, 1L)
  expect_equal(refreshed$n_error, 0L)
  # The re-run sees the new content of paths[1]: 3 rows.
  expect_equal(refreshed$log$csv_in, ctx$paths[1])
})

test_that("rerun_affected handles multiple impacted cases", {
  ctx <- make_two_runs_with_drift(n = 5L)
  # Mutate two more files between r0 and r1 to simulate broader drift.
  Sys.sleep(1.1)
  writeLines("x,y\n9,9\n", ctx$paths[3])
  writeLines("x,y\n8,8\n8,8\n", ctx$paths[4])
  r1b <- genproc(ctx$f, ctx$mask)

  d <- diff_inputs(ctx$r0, r1b)
  refreshed <- rerun_affected(ctx$r0, d, ctx$f)

  expect_equal(nrow(refreshed$log), nrow(d$changed))
  # Compare paths after canonicalization. The mask carries the
  # paths in the user-supplied form (which may contain backslashes
  # on Windows), while `diff$changed$path` carries them in the
  # normalized form used by the inputs snapshot.
  expect_setequal(
    normalizePath(refreshed$log$csv_in, winslash = "/", mustWork = FALSE),
    normalizePath(d$changed$path,        winslash = "/", mustWork = FALSE)
  )
})


# === Mask snapshot reuse =====================================================

test_that("rerun_affected reuses the mask from r0$reproducibility", {
  # The user does not need to pass a mask: r0 carries its mask.
  ctx <- make_two_runs_with_drift()
  d <- diff_inputs(ctx$r0, ctx$r1)
  refreshed <- rerun_affected(ctx$r0, d, ctx$f)

  expect_s3_class(refreshed, "genproc_result")
  # Columns of the re-run mask snapshot should match the original.
  expect_equal(
    names(refreshed$reproducibility$mask_snapshot),
    names(ctx$r0$reproducibility$mask_snapshot)
  )
})


# === Diff with malformed case_ids ============================================

test_that("rerun_affected errors clearly on unparseable case_ids", {
  ctx <- make_two_runs_with_drift()
  d <- diff_inputs(ctx$r0, ctx$r1)
  d$cases_affected$case_id <- "not_a_case_id_format"
  expect_error(rerun_affected(ctx$r0, d, ctx$f),
               "case_ids of the form")
})
