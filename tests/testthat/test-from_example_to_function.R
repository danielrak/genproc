# Tests for from_example_to_function() and the AST rewrite engine
#
# Each test covers one specific transformation rule. Test names are
# written to serve as documentation of the expected behavior.


# === Input validation =========================================================

test_that("rejects non-expression input", {
  expect_error(from_example_to_function(quote(x + 1)),
               "expression of length 1")
})

test_that("rejects expression of length > 1", {
  expect_error(from_example_to_function(expression(1, 2)),
               "expression of length 1")
})


# === String literals ==========================================================

test_that("string literals become parameters", {
  fn <- from_example_to_function(expression(print("hello")))

  expect_true(is.function(fn))
  expect_equal(formals(fn)$param_1, "hello")
  # The body should reference param_1, not the literal
  expect_true(grepl("param_1", deparse(body(fn))))
})

test_that("identical strings share the same parameter", {
  fn <- from_example_to_function(
    expression(c("hello", "hello"))
  )

  # Only one parameter should exist
 expect_length(formals(fn), 1)
})

test_that("different strings get different parameters", {
  fn <- from_example_to_function(
    expression(c("hello", "world"))
  )

  expect_length(formals(fn), 2)
  expect_equal(formals(fn)$param_1, "hello")
  expect_equal(formals(fn)$param_2, "world")
})


# === Symbol parameterization ==================================================

test_that("non-function symbols from env become parameters", {
  e <- new.env(parent = emptyenv())
  e$my_path <- "/data/input.csv"

  fn <- from_example_to_function(
    expression(read.csv(my_path)),
    env = e
  )

  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, "/data/input.csv")
})

test_that("function symbols from env are NOT parameterized", {
  e <- new.env(parent = baseenv())
  e$my_func <- function(x) x + 1
  e$my_val <- 10

  fn <- from_example_to_function(
    expression(my_func(my_val)),
    env = e
  )

  # Only my_val should be parameterized, not my_func
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 10)
  # my_func should still appear as-is in the body
  expect_true(grepl("my_func", deparse(body(fn))))
})

test_that("symbols not found in env are left as-is", {
  e <- new.env(parent = emptyenv())

  fn <- from_example_to_function(
    expression(unknown_var + 1),
    env = e
  )

  # No parameters should be created
  expect_length(formals(fn), 0)
  expect_true(grepl("unknown_var", deparse(body(fn))))
})


# === Local bindings ===========================================================

test_that("locally assigned symbols are NOT parameterized", {
  e <- new.env(parent = baseenv())
  e$x <- 42

  fn <- from_example_to_function(
    expression({
      x <- 1
      y <- x + 1
    }),
    env = e
  )

  # x is assigned inside the block, so even though x = 42 exists in env,
  # it should NOT be parameterized
  expect_length(formals(fn), 0)
})

test_that("symbol is parameterized BEFORE its local assignment", {
  e <- new.env(parent = baseenv())
  e$x <- 42

  fn <- from_example_to_function(
    expression({
      y <- x + 1
      x <- 99
    }),
    env = e
  )

  # In the first statement, x is not yet locally bound -> parameterized.
  # In the second, x is the LHS -> not parameterized (it's a target).
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 42)
})

test_that("right-assignment also creates local binding", {
  e <- new.env(parent = baseenv())
  e$x <- 42

  fn <- from_example_to_function(
    expression({
      1 -> x
      y <- x + 1
    }),
    env = e
  )

  # After `1 -> x`, x is locally bound
  expect_length(formals(fn), 0)
})


# === Function definitions ====================================================

test_that("function formals are protected from parameterization", {
  e <- new.env(parent = baseenv())
  e$offset <- 10

  fn <- from_example_to_function(
    expression(function(x) x + offset),
    env = e
  )

  # offset should be parameterized, x should not
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 10)
})

test_that("lambda syntax formals are protected", {
  e <- new.env(parent = baseenv())
  e$offset <- 10

  fn <- from_example_to_function(
    expression(\(x) x + offset),
    env = e
  )

  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 10)
})


# === Assignments ==============================================================

test_that("only RHS of left-assignment is rewritten", {
  e <- new.env(parent = baseenv())
  e$val <- 100

  fn <- from_example_to_function(
    expression(result <- val + 1),
    env = e
  )

  # val is parameterized (RHS), result is a target (LHS)
  expect_length(formals(fn), 1)
  body_str <- deparse(body(fn))
  expect_true(grepl("result", body_str))
  expect_true(grepl("param_1", body_str))
})

test_that("only value side of right-assignment is rewritten", {
  e <- new.env(parent = baseenv())
  e$val <- 100

  fn <- from_example_to_function(
    expression(val -> result),
    env = e
  )

  expect_length(formals(fn), 1)
})


# === Generic calls ============================================================

test_that("call head is never parameterized", {
  e <- new.env(parent = baseenv())
  e$path <- "/data/in.csv"

  fn <- from_example_to_function(
    expression(read.csv(path, header = TRUE)),
    env = e
  )

  body_str <- deparse(body(fn))
  # read.csv should appear literally, not parameterized
  expect_true(grepl("read.csv", body_str))
  # path should be parameterized
  expect_length(formals(fn), 1)
})

test_that("TRUE/FALSE/NULL/numeric are not parameterized", {
  e <- new.env(parent = emptyenv())

  fn <- from_example_to_function(
    expression(list(TRUE, FALSE, NULL, 42, 3.14)),
    env = e
  )

  expect_length(formals(fn), 0)
})


# === Nested / complex cases ===================================================

test_that("nested blocks track bindings correctly", {
  e <- new.env(parent = baseenv())
  e$x <- 10
  e$y <- 20

  fn <- from_example_to_function(
    expression({
      x <- 1
      {
        z <- x + y
      }
    }),
    env = e
  )

  # x is locally bound after first assignment -> not parameterized
  # y is external -> parameterized
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 20)
})

test_that("realistic data pipeline example", {
  e <- new.env(parent = baseenv())
  e$input_path <- "/data/raw/survey_2024.csv"
  e$threshold <- 0.05

  fn <- from_example_to_function(
    expression({
      df <- read.csv(input_path)
      df$significant <- df$pvalue < threshold
      write.csv(df, "output.csv")
    }),
    env = e
  )

  fmls <- formals(fn)
  # input_path, threshold, "output.csv" = 3 parameters
  expect_length(fmls, 3)
  expect_equal(fmls$param_1, "/data/raw/survey_2024.csv")
  expect_equal(fmls$param_2, 0.05)
  expect_equal(fmls$param_3, "output.csv")
})

test_that("same symbol used twice creates only one parameter", {
  e <- new.env(parent = baseenv())
  e$x <- 42

  fn <- from_example_to_function(
    expression(c(x, x)),
    env = e
  )

  expect_length(formals(fn), 1)
})


# === Edge cases ===============================================================

test_that("empty block is handled", {
  fn <- from_example_to_function(expression({}))
  expect_true(is.function(fn))
  expect_length(formals(fn), 0)
})

test_that("expression with only a numeric literal", {
  fn <- from_example_to_function(expression(42))
  expect_true(is.function(fn))
  expect_length(formals(fn), 0)
  expect_equal(body(fn), 42)
})

test_that("expression with only a string literal", {
  fn <- from_example_to_function(expression("hello"))
  expect_true(is.function(fn))
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, "hello")
})
