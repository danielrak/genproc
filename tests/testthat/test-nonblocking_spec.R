# Tests for nonblocking_spec()


# === Defaults and return type =================================================

test_that("default call returns a genproc_nonblocking_spec object", {
  spec <- nonblocking_spec()
  expect_s3_class(spec, "genproc_nonblocking_spec")
  expect_true(is.list(spec))
})

test_that("all expected fields are present", {
  spec <- nonblocking_spec()
  expected <- c("strategy", "packages", "globals")
  expect_true(all(expected %in% names(spec)))
})

test_that("defaults: strategy = 'multisession', packages NULL, globals TRUE", {
  spec <- nonblocking_spec()
  expect_equal(spec$strategy, "multisession")
  expect_null(spec$packages)
  expect_true(spec$globals)
})


# === strategy validation ======================================================

test_that("strategy accepts the four supported values", {
  for (s in c("sequential", "multisession", "multicore", "cluster")) {
    expect_equal(nonblocking_spec(strategy = s)$strategy, s)
  }
})

test_that("strategy accepts NULL (defer to current plan)", {
  spec <- nonblocking_spec(strategy = NULL)
  expect_null(spec$strategy)
})

test_that("strategy rejects unknown values and non-character", {
  expect_error(nonblocking_spec(strategy = "foo"),    "one of")
  expect_error(nonblocking_spec(strategy = 42),       "one of")
  expect_error(nonblocking_spec(strategy = NA_character_), "one of")
  expect_error(nonblocking_spec(strategy = c("sequential", "multicore")),
               "one of")
})


# === packages validation ======================================================

test_that("packages accepts non-empty character vector or NULL", {
  expect_null(nonblocking_spec(packages = NULL)$packages)
  expect_equal(nonblocking_spec(packages = "dplyr")$packages, "dplyr")
  expect_equal(nonblocking_spec(packages = c("dplyr", "tidyr"))$packages,
               c("dplyr", "tidyr"))
})

test_that("packages rejects NA or empty strings", {
  expect_error(nonblocking_spec(packages = NA_character_),
               "character vector")
  expect_error(nonblocking_spec(packages = c("dplyr", "")),
               "character vector")
  expect_error(nonblocking_spec(packages = 42), "character vector")
})


# === globals validation =======================================================

test_that("globals accepts logical and character", {
  expect_true(nonblocking_spec(globals = TRUE)$globals)
  expect_false(nonblocking_spec(globals = FALSE)$globals)
  expect_equal(nonblocking_spec(globals = c("x", "y"))$globals,
               c("x", "y"))
})

test_that("globals rejects numeric or list", {
  expect_error(nonblocking_spec(globals = 42),
               "logical or a character")
  expect_error(nonblocking_spec(globals = list(1)),
               "logical or a character")
})
