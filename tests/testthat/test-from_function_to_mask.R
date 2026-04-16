# Tests for from_function_to_mask()


# === Input validation =========================================================

test_that("rejects non-function input", {
  expect_error(from_function_to_mask(42), "must be a function")
})

test_that("rejects function with no parameters", {
  expect_error(from_function_to_mask(function() 42),
               "at least one parameter")
})


# === Basic mask generation ====================================================

test_that("produces a one-row data.frame", {
  fn <- function(a = 1, b = "x") NULL
  mask <- from_function_to_mask(fn)

  expect_s3_class(mask, "data.frame")
  expect_equal(nrow(mask), 1)
})

test_that("columns match parameter names", {
  fn <- function(input_path = "a.csv", n_rows = 10) NULL
  mask <- from_function_to_mask(fn)

  expect_equal(names(mask), c("input_path", "n_rows"))
})

test_that("character default is preserved", {
  fn <- function(path = "/data/input.csv") NULL
  mask <- from_function_to_mask(fn)

  expect_equal(mask$path, "/data/input.csv")
  expect_true(is.character(mask$path))
})

test_that("numeric default is preserved", {
  fn <- function(threshold = 0.05) NULL
  mask <- from_function_to_mask(fn)

  expect_equal(mask$threshold, 0.05)
  expect_true(is.numeric(mask$threshold))
})

test_that("integer default is preserved", {
  fn <- function(n = 10L) NULL
  mask <- from_function_to_mask(fn)

  expect_equal(mask$n, 10L)
  expect_true(is.integer(mask$n))
})

test_that("logical default is preserved", {
  fn <- function(verbose = TRUE) NULL
  mask <- from_function_to_mask(fn)

  expect_equal(mask$verbose, TRUE)
  expect_true(is.logical(mask$verbose))
})


# === Missing defaults =========================================================

test_that("parameter without default becomes NA", {
  fn <- function(x) x + 1
  mask <- from_function_to_mask(fn)

  expect_equal(nrow(mask), 1)
  expect_true(is.na(mask$x))
})

test_that("mix of defaults and missing defaults works", {
  fn <- function(a, b = "hello", c) NULL
  mask <- from_function_to_mask(fn)

  expect_true(is.na(mask$a))
  expect_equal(mask$b, "hello")
  expect_true(is.na(mask$c))
})

test_that("NULL default becomes NA", {
  fn <- function(x = NULL) NULL
  mask <- from_function_to_mask(fn)

  expect_true(is.na(mask$x))
})


# === Non-scalar defaults (v0.1 limitation) ====================================

test_that("non-scalar vector default is rejected with informative message", {
  fn <- function(x = c(1, 2, 3)) NULL
  expect_error(from_function_to_mask(fn),
               "non-scalar")
})

test_that("list default is rejected", {
  fn <- function(x = list(a = 1)) NULL
  expect_error(from_function_to_mask(fn), "non-scalar")
})


# === Integration with from_example_to_function ================================

test_that("pipeline: expression -> function -> mask", {
  e <- new.env(parent = baseenv())
  e$input_path <- "/data/raw.csv"
  e$threshold <- 0.05

  fn <- from_example_to_function(
    expression({
      df <- read.csv(input_path)
      df$sig <- df$p < threshold
      write.csv(df, "output.csv")
    }),
    env = e
  )

  mask <- from_function_to_mask(fn)

  expect_s3_class(mask, "data.frame")
  expect_equal(nrow(mask), 1)
  expect_equal(ncol(mask), 3)
  expect_equal(mask$param_1, "/data/raw.csv")
  expect_equal(mask$param_2, 0.05)
  expect_equal(mask$param_3, "output.csv")
})

test_that("pipeline with rename: expression -> function -> rename -> mask", {
  e <- new.env(parent = baseenv())
  e$path <- "/data/in.csv"

  fn <- from_example_to_function(expression(read.csv(path)), env = e)
  fn <- rename_function_params(fn, c(param_1 = "input_path"))
  mask <- from_function_to_mask(fn)

  expect_equal(names(mask), "input_path")
  expect_equal(mask$input_path, "/data/in.csv")
})


# === Pure data.frame guarantee ================================================

test_that("mask has no custom class beyond data.frame", {
  fn <- function(a = 1, b = "x") NULL
  mask <- from_function_to_mask(fn)

  expect_equal(class(mask), "data.frame")
})

test_that("mask survives dplyr operations without losing structure", {
  skip_if_not_installed("dplyr")
  library(dplyr)

  fn <- function(a = 1, b = 2, c = 3) NULL
  mask <- from_function_to_mask(fn)

  # Expand to multiple rows, filter
  full_mask <- bind_rows(mask, mask, mask)
  full_mask$a <- c(10, 20, 30)
  filtered <- filter(full_mask, a > 15)

  expect_s3_class(filtered, "data.frame")
  expect_equal(nrow(filtered), 2)
  expect_equal(names(filtered), c("a", "b", "c"))
})
