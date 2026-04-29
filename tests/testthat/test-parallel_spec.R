# Tests for parallel_spec()


# === Defaults and return type =================================================

test_that("default call returns a genproc_parallel_spec object", {
  spec <- parallel_spec()
  expect_s3_class(spec, "genproc_parallel_spec")
  expect_true(is.list(spec))
})

test_that("all expected fields are present", {
  spec <- parallel_spec()
  expected <- c("workers", "strategy", "chunk_size",
                "seed", "packages", "globals")
  expect_true(all(expected %in% names(spec)))
})

test_that("defaults: workers, strategy, chunk_size, packages are NULL; seed TRUE; globals TRUE", {
  spec <- parallel_spec()
  expect_null(spec$workers)
  expect_null(spec$strategy)
  expect_null(spec$chunk_size)
  expect_null(spec$packages)
  expect_true(spec$seed)
  expect_true(spec$globals)
})


# === workers validation =======================================================

test_that("workers accepts positive integer", {
  expect_equal(parallel_spec(workers = 4)$workers, 4L)
  expect_equal(parallel_spec(workers = 1L)$workers, 1L)
})

test_that("workers coerces numeric whole values to integer", {
  expect_identical(parallel_spec(workers = 4)$workers, 4L)
})

test_that("workers rejects non-positive, non-integer, NA", {
  expect_error(parallel_spec(workers = 0),      "positive integer")
  expect_error(parallel_spec(workers = -1),     "positive integer")
  expect_error(parallel_spec(workers = 1.5),    "positive integer")
  expect_error(parallel_spec(workers = NA),     "positive integer")
  expect_error(parallel_spec(workers = "four"), "positive integer")
  expect_error(parallel_spec(workers = c(2, 4)), "positive integer")
})


# === strategy validation ======================================================

test_that("strategy accepts the four supported values", {
  for (s in c("sequential", "multisession", "multicore", "cluster")) {
    expect_equal(parallel_spec(strategy = s)$strategy, s)
  }
})

test_that("strategy rejects unknown values and non-character", {
  expect_error(parallel_spec(strategy = "foo"),    "one of")
  expect_error(parallel_spec(strategy = 42),       "one of")
  expect_error(parallel_spec(strategy = NA_character_), "one of")
  expect_error(parallel_spec(strategy = c("sequential", "multicore")),
               "one of")
})


# === chunk_size validation ====================================================

test_that("chunk_size accepts positive integer", {
  expect_equal(parallel_spec(chunk_size = 10)$chunk_size, 10L)
})

test_that("chunk_size rejects non-positive, non-integer, NA", {
  expect_error(parallel_spec(chunk_size = 0),   "positive integer")
  expect_error(parallel_spec(chunk_size = -1),  "positive integer")
  expect_error(parallel_spec(chunk_size = 1.5), "positive integer")
  expect_error(parallel_spec(chunk_size = NA),  "positive integer")
})


# === seed validation ==========================================================

test_that("seed accepts TRUE, FALSE, integer, and list", {
  expect_true(parallel_spec(seed = TRUE)$seed)
  expect_false(parallel_spec(seed = FALSE)$seed)
  expect_equal(parallel_spec(seed = 42)$seed, 42)
  expect_equal(parallel_spec(seed = 42L)$seed, 42L)
  expect_equal(parallel_spec(seed = list(1L, 2L, 3L))$seed,
               list(1L, 2L, 3L))
})

test_that("seed rejects NA, character, multi-element logical", {
  expect_error(parallel_spec(seed = NA),            "must be")
  expect_error(parallel_spec(seed = "true"),        "must be")
  expect_error(parallel_spec(seed = c(TRUE, FALSE)), "must be")
})


# === packages validation ======================================================

test_that("packages accepts non-empty character vector or NULL", {
  expect_null(parallel_spec(packages = NULL)$packages)
  expect_equal(parallel_spec(packages = "dplyr")$packages, "dplyr")
  expect_equal(parallel_spec(packages = c("dplyr", "tidyr"))$packages,
               c("dplyr", "tidyr"))
})

test_that("packages rejects NA or empty strings", {
  expect_error(parallel_spec(packages = NA_character_),  "character vector")
  expect_error(parallel_spec(packages = c("dplyr", "")), "character vector")
  expect_error(parallel_spec(packages = 42),             "character vector")
})


# === globals validation =======================================================

test_that("globals accepts logical and character", {
  expect_true(parallel_spec(globals = TRUE)$globals)
  expect_false(parallel_spec(globals = FALSE)$globals)
  expect_equal(parallel_spec(globals = c("x", "y"))$globals, c("x", "y"))
})

test_that("globals rejects numeric or list", {
  expect_error(parallel_spec(globals = 42),       "logical or a character")
  expect_error(parallel_spec(globals = list(1)),  "logical or a character")
})


# === resolve_effective_strategy() (internal, F17) ============================

test_that("resolve_effective_strategy returns NULL when parallel is NULL", {
  resolve <- utils::getFromNamespace("resolve_effective_strategy",
                                     "genproc")
  expect_null(resolve(NULL))
})

test_that("resolve_effective_strategy returns the user's strategy when set", {
  resolve <- utils::getFromNamespace("resolve_effective_strategy",
                                     "genproc")
  spec <- parallel_spec(strategy = "sequential")
  expect_equal(resolve(spec), "sequential")

  spec <- parallel_spec(strategy = "multisession", workers = 4L)
  expect_equal(resolve(spec), "multisession")
})

test_that("resolve_effective_strategy auto-defaults to multisession when workers given without strategy", {
  resolve <- utils::getFromNamespace("resolve_effective_strategy",
                                     "genproc")
  spec <- parallel_spec(workers = 4L)
  expect_equal(resolve(spec), "multisession")
})

test_that("resolve_effective_strategy returns NULL in power-user mode (no workers, no strategy)", {
  resolve <- utils::getFromNamespace("resolve_effective_strategy",
                                     "genproc")
  spec <- parallel_spec()
  expect_null(resolve(spec))
})
