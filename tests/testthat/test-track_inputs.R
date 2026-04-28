# Tests for input fingerprint helpers in R/track_inputs.R.
#
# We exercise the three building blocks (`is_input_column`,
# `select_input_columns`, `stat_files`, `capture_input_fingerprints`)
# directly via getFromNamespace(), then a few integration cases via
# the public genproc() entry point.

is_input_column         <- utils::getFromNamespace("is_input_column",
                                                   "genproc")
select_input_columns    <- utils::getFromNamespace("select_input_columns",
                                                   "genproc")
stat_files              <- utils::getFromNamespace("stat_files",
                                                   "genproc")
capture_input_fingerprints <- utils::getFromNamespace(
  "capture_input_fingerprints", "genproc"
)


# Helper: create N CSV-like files in a fresh per-test tempdir.
# Returns the vector of absolute paths.
make_files <- function(n = 3, ext = ".csv", contents = "x,y\n1,2\n") {
  d <- tempfile("track_inputs_")
  dir.create(d)
  paths <- file.path(d, sprintf("data_%02d%s", seq_len(n), ext))
  for (p in paths) writeLines(contents, p)
  paths
}


# === is_input_column ==========================================================

test_that("is_input_column accepts a column of existing paths with separators", {
  paths <- make_files(2)
  expect_true(is_input_column(paths))
})

test_that("is_input_column rejects non-character columns", {
  expect_false(is_input_column(1:3))
  expect_false(is_input_column(c(TRUE, FALSE)))
})

test_that("is_input_column rejects all-NA columns", {
  expect_false(is_input_column(NA_character_))
})

test_that("is_input_column rejects when any non-NA value doesn't exist", {
  paths <- make_files(2)
  expect_false(is_input_column(c(paths, "/nonexistent/path.csv")))
})

test_that("is_input_column rejects columns of bare names without separators", {
  # Even if a file 'README' happens to exist in cwd, plain names
  # without separators must not trigger the heuristic.
  expect_false(is_input_column(c("alpha", "beta", "gamma")))
})

test_that("is_input_column tolerates partial NAs", {
  paths <- make_files(2)
  expect_true(is_input_column(c(paths, NA_character_)))
})

test_that("is_input_column rejects directories", {
  d <- tempfile("track_inputs_dir_")
  dir.create(d)
  expect_false(is_input_column(d))
})


# === select_input_columns =====================================================

test_that("select_input_columns picks character columns of paths", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in = paths,
    label  = c("alpha", "beta"),
    n      = c(1, 2),
    stringsAsFactors = FALSE
  )
  expect_equal(select_input_columns(mask), "csv_in")
})

test_that("select_input_columns honors explicit input_cols (bypasses heuristic)", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in   = paths,
    rds_out  = c("/tmp/out_01.rds", "/tmp/out_02.rds"),  # don't exist
    stringsAsFactors = FALSE
  )
  expect_equal(
    select_input_columns(mask, input_cols = c("csv_in", "rds_out")),
    c("csv_in", "rds_out")
  )
})

test_that("select_input_columns errors on unknown input_cols", {
  mask <- data.frame(x = "a")
  expect_error(
    select_input_columns(mask, input_cols = "missing"),
    "unknown column"
  )
})

test_that("select_input_columns honors skip_input_cols", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in = paths,
    cfg    = paths,
    stringsAsFactors = FALSE
  )
  expect_equal(
    select_input_columns(mask, skip_input_cols = "cfg"),
    "csv_in"
  )
})

test_that("select_input_columns errors if both overrides are given", {
  mask <- data.frame(x = "a")
  expect_error(
    select_input_columns(mask, input_cols = "x", skip_input_cols = "x"),
    "cannot be used together"
  )
})


# === stat_files ===============================================================

test_that("stat_files returns size and mtime for existing files", {
  paths <- make_files(2)
  out <- stat_files(paths)

  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 2)
  expect_named(out, c("path", "size", "mtime"))
  expect_true(all(out$size > 0))
  expect_s3_class(out$mtime, "POSIXct")
})

test_that("stat_files deduplicates identical paths", {
  paths <- make_files(1)
  out <- stat_files(c(paths, paths, paths))
  expect_equal(nrow(out), 1)
})

test_that("stat_files handles empty input", {
  out <- stat_files(character(0))
  expect_equal(nrow(out), 0)
  expect_named(out, c("path", "size", "mtime"))
})

test_that("stat_files records NA for missing files", {
  out <- stat_files("/nonexistent/file.csv")
  expect_equal(nrow(out), 1)
  expect_true(is.na(out$size))
  expect_true(is.na(out$mtime))
})


# === capture_input_fingerprints ===============================================

test_that("capture_input_fingerprints returns NULL when track = FALSE", {
  paths <- make_files(2)
  mask <- data.frame(csv_in = paths, stringsAsFactors = FALSE)
  out <- capture_input_fingerprints(mask, c("c1", "c2"), track = FALSE)
  expect_null(out)
})

test_that("capture_input_fingerprints rejects overrides when track = FALSE", {
  mask <- data.frame(x = "a")
  expect_error(
    capture_input_fingerprints(mask, "c1", track = FALSE,
                               input_cols = "x"),
    "cannot be used when"
  )
})

test_that("capture_input_fingerprints builds the expected snapshot", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in = paths,
    label  = c("a", "b"),
    stringsAsFactors = FALSE
  )
  out <- capture_input_fingerprints(mask, c("c1", "c2"))

  expect_named(out, c("method", "files", "refs"))
  expect_equal(out$method, "stat")
  expect_equal(nrow(out$files), 2)
  expect_equal(nrow(out$refs), 2)
  expect_equal(out$refs$column, c("csv_in", "csv_in"))
  expect_equal(out$refs$case_id, c("c1", "c2"))
})

test_that("capture_input_fingerprints deduplicates shared files", {
  paths <- make_files(1)  # one shared config
  mask <- data.frame(
    cfg = c(paths, paths, paths),
    stringsAsFactors = FALSE
  )
  out <- capture_input_fingerprints(mask,
                                    c("c1", "c2", "c3"))
  expect_equal(nrow(out$files), 1)   # deduped
  expect_equal(nrow(out$refs), 3)    # one per case
})

test_that("capture_input_fingerprints returns empty (well-formed) when no input columns", {
  mask <- data.frame(x = 1:3, label = c("a", "b", "c"))
  out <- capture_input_fingerprints(mask, c("c1", "c2", "c3"))
  expect_equal(nrow(out$files), 0)
  expect_equal(nrow(out$refs), 0)
})

test_that("capture_input_fingerprints warns on input_cols with non-existent paths", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in  = paths,
    rds_out = c("/nonexistent/a.rds", "/nonexistent/b.rds"),
    stringsAsFactors = FALSE
  )
  expect_warning(
    out <- capture_input_fingerprints(
      mask, c("c1", "c2"),
      input_cols = c("csv_in", "rds_out")
    ),
    "do not exist at capture time"
  )
  # The non-existent paths are still in `files`, with NA size/mtime
  expect_true(any(is.na(out$files$size)))
})


# === Integration via genproc() ================================================

test_that("genproc() default attaches an inputs snapshot", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in = paths,
    rds_out = c(tempfile("o_"), tempfile("o_")),
    stringsAsFactors = FALSE
  )
  f <- function(csv_in, rds_out) {
    saveRDS(read.csv(csv_in), rds_out); invisible(NULL)
  }
  r <- genproc(f, mask)

  expect_false(is.null(r$reproducibility$inputs))
  expect_equal(r$reproducibility$inputs$method, "stat")
  expect_equal(nrow(r$reproducibility$inputs$files), 2)
  # rds_out files don't exist at t0 -> excluded by heuristic
  expect_true(all(grepl("data_", r$reproducibility$inputs$files$path)))
})

test_that("genproc(track_inputs = FALSE) attaches NULL", {
  paths <- make_files(2)
  mask <- data.frame(csv_in = paths, stringsAsFactors = FALSE)
  f <- function(csv_in) read.csv(csv_in)
  r <- genproc(f, mask, track_inputs = FALSE)
  expect_null(r$reproducibility$inputs)
})

test_that("genproc(input_cols=...) bypasses heuristic and warns on absent files", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in  = paths,
    rds_out = c(tempfile("o_"), tempfile("o_")),
    stringsAsFactors = FALSE
  )
  f <- function(csv_in, rds_out) {
    saveRDS(read.csv(csv_in), rds_out); invisible(NULL)
  }
  expect_warning(
    r <- genproc(f, mask, input_cols = c("csv_in", "rds_out")),
    "do not exist"
  )
  # rds_out is now tracked (with NA size/mtime since the files don't
  # exist yet at t0).
  inp <- r$reproducibility$inputs
  expect_equal(nrow(inp$files), 4)
  expect_true(any(is.na(inp$files$size)))
})

test_that("genproc(skip_input_cols=...) excludes a heuristically-detected column", {
  paths <- make_files(2)
  mask <- data.frame(
    csv_in = paths,
    cfg    = paths,
    stringsAsFactors = FALSE
  )
  f <- function(csv_in, cfg) read.csv(csv_in)
  r <- genproc(f, mask, skip_input_cols = "cfg")
  inp <- r$reproducibility$inputs
  expect_true(all(inp$refs$column == "csv_in"))
})

test_that("genproc() rejects bad track_inputs", {
  mask <- data.frame(x = 1)
  expect_error(genproc(function(x) x, mask, track_inputs = NA),
               "TRUE/FALSE")
  expect_error(genproc(function(x) x, mask, track_inputs = "yes"),
               "TRUE/FALSE")
})
