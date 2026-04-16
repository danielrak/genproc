# Tests for the parallel execution branch of genproc().
#
# Most tests use parallel_spec(strategy = "sequential") so that the
# parallel code path is exercised deterministically in the current R
# process (no worker startup, no timing-dependence, no RNG noise
# beyond the L'Ecuyer-CMRG stream).
#
# A single end-to-end test uses a real multisession plan with two
# workers, skipped on CRAN.


# === Argument validation ======================================================

test_that("parallel must be NULL or a genproc_parallel_spec", {
  expect_error(
    genproc(function(x) x, data.frame(x = 1), parallel = TRUE),
    "genproc_parallel_spec"
  )
  expect_error(
    genproc(function(x) x, data.frame(x = 1), parallel = list()),
    "genproc_parallel_spec"
  )
  expect_error(
    genproc(function(x) x, data.frame(x = 1), parallel = "multisession"),
    "genproc_parallel_spec"
  )
})


# === Parity with sequential (strategy = "sequential") =========================

test_that("sequential-strategy parallel run produces identical log to default", {
  mask <- data.frame(x = c(1, 2, 3, 4))
  seq_result <- genproc(function(x) x * 10, mask)
  par_result <- genproc(function(x) x * 10, mask,
                        parallel = parallel_spec(strategy = "sequential"))

  # Compare log contents ignoring duration (which differs by wall time)
  cmp_cols <- setdiff(names(seq_result$log), "duration_secs")
  expect_equal(par_result$log[, cmp_cols],
               seq_result$log[, cmp_cols])

  expect_equal(par_result$n_success, seq_result$n_success)
  expect_equal(par_result$n_error, seq_result$n_error)
})

test_that("sequential-strategy parallel run preserves case_id order", {
  mask <- data.frame(x = 1:5)
  result <- genproc(function(x) x, mask,
                    parallel = parallel_spec(strategy = "sequential"))

  expect_equal(result$log$case_id,
               c("case_0001", "case_0002", "case_0003",
                 "case_0004", "case_0005"))
  expect_equal(result$log$x, 1:5)
})


# === Error handling in parallel ===============================================

test_that("errors in individual cases do not stop a parallel run", {
  fn <- function(x) {
    if (x == 2) stop("case 2 failed")
    x * 10
  }
  result <- genproc(fn, data.frame(x = c(1, 2, 3)),
                    parallel = parallel_spec(strategy = "sequential"))

  expect_equal(nrow(result$log), 3)
  expect_equal(result$n_success, 2)
  expect_equal(result$n_error, 1)
  expect_equal(result$log$error_message[2], "case 2 failed")
})

test_that("traceback is captured on error in parallel mode", {
  fn <- function(x) {
    inner <- function() stop("deep")
    inner()
  }
  result <- genproc(fn, data.frame(x = 1),
                    parallel = parallel_spec(strategy = "sequential"))

  expect_false(is.na(result$log$traceback[1]))
  expect_true(grepl("inner", result$log$traceback[1]))
})


# === Reproducibility snapshot records the parallel spec =======================

test_that("sequential run: reproducibility$parallel is NULL", {
  result <- genproc(function(x) x, data.frame(x = 1))
  expect_null(result$reproducibility$parallel)
})

test_that("parallel run: reproducibility$parallel records the spec", {
  spec <- parallel_spec(workers = 2,
                        strategy = "sequential",
                        chunk_size = 1L,
                        seed = 42L,
                        packages = "dplyr")
  result <- genproc(function(x) x, data.frame(x = c(1, 2)),
                    parallel = spec)

  p <- result$reproducibility$parallel
  expect_false(is.null(p))
  expect_equal(p$strategy,   "sequential")
  expect_equal(p$workers,    2L)
  expect_equal(p$chunk_size, 1L)
  expect_equal(p$seed,       42L)
  expect_equal(p$packages,   "dplyr")
})


# === Result structure is unchanged ============================================

test_that("parallel run returns a genproc_result with expected components", {
  result <- genproc(function(x) x, data.frame(x = 1:3),
                    parallel = parallel_spec(strategy = "sequential"))

  expect_s3_class(result, "genproc_result")
  expected <- c("log", "reproducibility", "n_success",
                "n_error", "duration_total_secs", "status")
  expect_true(all(expected %in% names(result)))
  expect_equal(result$status, "done")
})


# === Plan restoration =========================================================

test_that("temporary plan set by strategy is restored on exit", {
  skip_if_not_installed("future")

  old <- future::plan(future::sequential)
  on.exit(future::plan(old), add = TRUE)

  genproc(function(x) x, data.frame(x = 1:2),
          parallel = parallel_spec(strategy = "sequential"))

  # The plan active after genproc() returns should still be sequential
  # (i.e. the one we installed before the call).
  expect_true(inherits(future::plan(), "sequential"))
})


# === Real multi-worker execution (skipped on CRAN) ============================

test_that("actual multisession run: parity with sequential, 2 workers", {
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

  mask <- data.frame(x = 1:6)
  fn <- function(x) {
    if (x %% 3 == 0) stop("divisible by 3")
    x * 2
  }

  seq_result <- genproc(fn, mask)
  par_result <- genproc(
    fn, mask,
    parallel = parallel_spec(strategy = "multisession", workers = 2,
                             seed = 1L)
  )

  # Results identical up to duration (which differs by wall time)
  cmp_cols <- setdiff(names(seq_result$log),
                      c("duration_secs", "traceback"))
  expect_equal(par_result$log[, cmp_cols],
               seq_result$log[, cmp_cols])
  expect_equal(par_result$n_success, seq_result$n_success)
  expect_equal(par_result$n_error, seq_result$n_error)

  # case_id order preserved
  expect_equal(par_result$log$case_id, seq_result$log$case_id)

  # Traceback of failing cases is non-NA and mentions user-level frames
  fail_idx <- which(!par_result$log$success)
  expect_true(all(!is.na(par_result$log$traceback[fail_idx])))
})
