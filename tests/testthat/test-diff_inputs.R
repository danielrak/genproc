# Tests for diff_inputs()


# Helper: produce two genproc_result objects from the same mask, with
# an optional mutation in between (a function that takes the input
# paths and is called between the two runs).
make_two_runs <- function(mutation = NULL) {
  d <- tempfile("diff_inputs_"); dir.create(d)
  paths <- file.path(d, sprintf("data_%02d.csv", 1:3))
  for (p in paths) writeLines("x,y\n1,2\n", p)

  mask <- data.frame(csv_in = paths, stringsAsFactors = FALSE)
  f <- function(csv_in) nrow(read.csv(csv_in))

  r0 <- genproc(f, mask)
  if (!is.null(mutation)) mutation(paths)
  r1 <- genproc(f, mask)

  list(r0 = r0, r1 = r1, paths = paths)
}


# === Preconditions ============================================================

test_that("diff_inputs rejects non-genproc_result inputs", {
  expect_error(diff_inputs(list(), list()), "must both be")
  r <- genproc(function(x) x, data.frame(x = 1))
  expect_error(diff_inputs(r, list()), "must both be")
})

test_that("diff_inputs refuses runs with no inputs tracking", {
  r0 <- genproc(function(x) x, data.frame(x = 1), track_inputs = FALSE)
  r1 <- genproc(function(x) x, data.frame(x = 1), track_inputs = FALSE)
  expect_error(diff_inputs(r0, r1), "track_inputs = FALSE")
})


# === No mutation ==============================================================

test_that("diff_inputs reports all unchanged when nothing changed", {
  runs <- make_two_runs()
  d <- diff_inputs(runs$r0, runs$r1)

  expect_s3_class(d, "genproc_input_diff")
  expect_equal(nrow(d$changed),   0)
  expect_equal(length(d$removed), 0)
  expect_equal(length(d$added),   0)
  expect_equal(length(d$unchanged), 3)
})


# === Content change ===========================================================

test_that("diff_inputs detects a content change (size + mtime)", {
  runs <- make_two_runs(mutation = function(paths) {
    Sys.sleep(1.1)  # ensure mtime tick on filesystems with 1s resolution
    writeLines("x,y\n1,2\n3,4\n5,6\n", paths[1])
  })

  d <- diff_inputs(runs$r0, runs$r1)
  expect_equal(nrow(d$changed), 1)
  expect_equal(length(d$unchanged), 2)
  expect_true(d$changed$size_after[1] > d$changed$size_before[1])
})


# === Removed / added ==========================================================

test_that("diff_inputs reports added paths when r1 has more files", {
  d_path <- tempfile("diff_added_"); dir.create(d_path)
  p1 <- file.path(d_path, "a.csv")
  p2 <- file.path(d_path, "b.csv")
  writeLines("x\n1\n", p1)
  writeLines("x\n2\n", p2)

  f <- function(csv_in) nrow(read.csv(csv_in))

  r0 <- genproc(f, data.frame(csv_in = p1, stringsAsFactors = FALSE))
  r1 <- genproc(f, data.frame(csv_in = c(p1, p2),
                              stringsAsFactors = FALSE))

  d <- diff_inputs(r0, r1)
  expect_equal(length(d$added), 1)
  expect_equal(length(d$removed), 0)
  expect_equal(length(d$unchanged), 1)
})

test_that("diff_inputs reports removed paths when r0 has more files", {
  d_path <- tempfile("diff_removed_"); dir.create(d_path)
  p1 <- file.path(d_path, "a.csv")
  p2 <- file.path(d_path, "b.csv")
  writeLines("x\n1\n", p1)
  writeLines("x\n2\n", p2)

  f <- function(csv_in) nrow(read.csv(csv_in))

  r0 <- genproc(f, data.frame(csv_in = c(p1, p2),
                              stringsAsFactors = FALSE))
  r1 <- genproc(f, data.frame(csv_in = p1, stringsAsFactors = FALSE))

  d <- diff_inputs(r0, r1)
  expect_equal(length(d$removed), 1)
  expect_equal(length(d$added), 0)
})


# === Method mismatch ==========================================================

test_that("diff_inputs refuses to compare across different methods", {
  runs <- make_two_runs()
  # Simulate a future hash-based snapshot by mutating the method tag.
  runs$r1$reproducibility$inputs$method <- "md5"
  expect_error(diff_inputs(runs$r0, runs$r1),
               "different methods")
})


# === Print method ============================================================

test_that("print.genproc_input_diff returns its argument invisibly", {
  runs <- make_two_runs()
  d <- diff_inputs(runs$r0, runs$r1)
  out <- capture.output(res <- print(d))
  expect_identical(res, d)
  # Some output was produced
  expect_true(length(out) > 0)
})

test_that("print.genproc_input_diff shows changed file detail", {
  # Mutation must change BOTH size and mtime so the print method shows
  # both "size:" and "mtime:" lines. We rewrite the file with strictly
  # more content. NB: a same-length rewrite would only flip mtime on
  # Linux (tie at the byte level) but flip both on Windows (CRLF
  # expansion makes the length differ). Either way, picking a clearly
  # longer payload removes the platform-dependent ambiguity.
  runs <- make_two_runs(mutation = function(paths) {
    Sys.sleep(1.1)
    writeLines("x,y\n1,2\n3,4\n5,6\n7,8\n", paths[1])
  })
  d <- diff_inputs(runs$r0, runs$r1)
  out <- paste(capture.output(print(d)), collapse = "\n")
  expect_match(out, "Changed:")
  expect_match(out, "size:")
  expect_match(out, "mtime:")
})
