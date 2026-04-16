# Tests for rename_function_params()


# === Input validation =========================================================

test_that("rejects non-function input", {
  expect_error(rename_function_params(42, c(a = "b")), "must be a function")
})

test_that("rejects non-named mapping", {
  fn <- function(x) x
  expect_error(rename_function_params(fn, c("a", "b")),
               "named character vector")
})

test_that("rejects empty names in mapping", {
  fn <- function(x) x
  bad_mapping <- "b"
  names(bad_mapping) <- ""
  expect_error(rename_function_params(fn, bad_mapping),
               "non-empty strings")
})
test_that("rejects empty values in mapping", {
  fn <- function(x) x
  expect_error(rename_function_params(fn, c(x = "")),
               "non-empty strings")
})

test_that("rejects mapping with names not in formals", {
  fn <- function(x, y) x + y
  expect_error(rename_function_params(fn, c(z = "a")),
               "not parameters")
})

test_that("rejects duplicate new names", {
  fn <- function(x, y) x + y
  expect_error(rename_function_params(fn, c(x = "a", y = "a")),
               "unique")
})

test_that("rejects new names colliding with untouched params", {
  fn <- function(x, y) x + y
  expect_error(rename_function_params(fn, c(x = "y")),
               "collide")
})


# === Basic renaming ===========================================================

test_that("renames a single parameter in formals and body", {
  fn <- function(param_1 = "hello") paste0(param_1, "!")
  fn2 <- rename_function_params(fn, c(param_1 = "greeting"))

  expect_equal(names(formals(fn2)), "greeting")
  expect_equal(formals(fn2)$greeting, "hello")
  expect_true(grepl("greeting", deparse(body(fn2))))
  expect_false(grepl("param_1", deparse(body(fn2))))
})

test_that("renames multiple parameters", {
  fn <- function(param_1, param_2) c(param_1, param_2)
  fn2 <- rename_function_params(fn, c(param_1 = "a", param_2 = "b"))

  expect_equal(names(formals(fn2)), c("a", "b"))
  body_str <- deparse(body(fn2))
  expect_true(grepl("\\ba\\b", body_str))
  expect_true(grepl("\\bb\\b", body_str))
})

test_that("partial rename leaves untouched params intact", {
  fn <- function(x, y, z) x + y + z
  fn2 <- rename_function_params(fn, c(x = "alpha"))

  expect_equal(names(formals(fn2)), c("alpha", "y", "z"))
})

test_that("default values are preserved after rename", {
  fn <- function(param_1 = 10, param_2 = "test") param_1 + nchar(param_2)
  fn2 <- rename_function_params(fn, c(param_1 = "n", param_2 = "label"))

  expect_equal(formals(fn2)$n, 10)
  expect_equal(formals(fn2)$label, "test")
})


# === Execution after rename ===================================================

test_that("renamed function executes correctly", {
  fn <- function(param_1 = 2, param_2 = 3) param_1 * param_2
  fn2 <- rename_function_params(fn, c(param_1 = "x", param_2 = "y"))

  # Using defaults
  expect_equal(fn2(), 6)
  # Using new names
  expect_equal(fn2(x = 5, y = 4), 20)
})

test_that("renamed function works in a pipeline with from_example_to_function", {
  e <- new.env(parent = baseenv())
  e$val <- 100

  fn <- from_example_to_function(
    expression(val + 1),
    env = e
  )
  fn2 <- rename_function_params(fn, c(param_1 = "value"))

  expect_equal(names(formals(fn2)), "value")
  expect_equal(fn2(), 101)
  expect_equal(fn2(value = 50), 51)
})


# === Edge cases ===============================================================

test_that("works with block body containing multiple references", {
  fn <- function(param_1 = "a") {
    x <- param_1
    paste(x, param_1)
  }
  fn2 <- rename_function_params(fn, c(param_1 = "input"))

  body_str <- paste(deparse(body(fn2)), collapse = " ")
  # param_1 should be fully replaced
  expect_false(grepl("param_1", body_str))
  # input should appear twice (assignment + paste)
  expect_equal(length(gregexpr("input", body_str)[[1]]), 2)
})

test_that("inner function formals are not renamed", {
  fn <- function(param_1) {
    inner <- function(param_1) param_1 + 1
    inner(param_1)
  }
  fn2 <- rename_function_params(fn, c(param_1 = "x"))

  # Outer formal should be renamed
  expect_equal(names(formals(fn2)), "x")
  # The inner function's formal should stay as param_1
  body_str <- paste(deparse(body(fn2)), collapse = " ")
  expect_true(grepl("function\\(param_1\\)", body_str))
})
