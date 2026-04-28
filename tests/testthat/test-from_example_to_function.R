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


# === Coverage gaps for assignment variants ====================================

test_that("`=` operator inside a block also creates local binding", {
  e <- new.env(parent = baseenv())
  e$x <- 42

  fn <- from_example_to_function(
    expression({
      x = 1
      y <- x + 1
    }),
    env = e
  )

  # `=` is an assignment operator just like `<-` -> x is locally bound,
  # must not be parameterized.
  expect_length(formals(fn), 0)
})

test_that("`<<-` operator also creates local binding", {
  e <- new.env(parent = baseenv())
  e$x <- 42

  fn <- from_example_to_function(
    expression({
      x <<- 1
      y <- x + 1
    }),
    env = e
  )

  expect_length(formals(fn), 0)
})

test_that("assignment target that is not a bare symbol does not bind", {
  e <- new.env(parent = baseenv())
  e$x <- list(y = 0)

  # `x$y <- 1` is an assignment but the target is `x$y`, not a bare
  # symbol — assignment_target() returns NULL for it, so no new local
  # binding for `x` is recorded. We verify this indirectly: `x` is
  # referenced in a later statement and should still be parameterized.
  fn <- from_example_to_function(
    expression({
      x$y <- 1
      print(x)
    }),
    env = e
  )

  # `x` in `print(x)` is still external (no binding from x$y <-) so it
  # is parameterized. `print` is a function in baseenv -> not parameterized.
  fmls <- formals(fn)
  expect_length(fmls, 1)
  expect_equal(fmls$param_1, list(y = 0))
})


# === Coverage gaps for calls and function defs ================================

test_that("missing argument placeholder in a call is preserved", {
  # f(a, , b) parses with an empty symbol in position 3. The rewriter
  # must not crash on it (rewrite_call skips it via is_missing_arg_node).
  e <- new.env(parent = baseenv())
  e$path <- "/data/in.csv"

  expect_no_error(
    fn <- from_example_to_function(
      expression(matrix(path, , 2)),
      env = e
    )
  )

  expect_length(formals(fn), 1)
  expect_true(grepl("matrix", deparse(body(fn))))
})

test_that("function definition with `...` does not parameterize the dots", {
  e <- new.env(parent = baseenv())
  e$offset <- 10

  fn <- from_example_to_function(
    expression(function(x, ...) x + offset),
    env = e
  )

  # `...` is filtered out of the bound names; only `x` is bound.
  # `offset` is the only external value -> one parameter.
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 10)
})

test_that("nested function definitions preserve scoping per level", {
  e <- new.env(parent = baseenv())
  e$outer <- 100

  fn <- from_example_to_function(
    expression(function(a) function(b) a + b + outer),
    env = e
  )

  # `a` is bound in the outer body, `b` in the inner. `outer` is
  # the only external value -> exactly one parameter.
  expect_length(formals(fn), 1)
  expect_equal(formals(fn)$param_1, 100)
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


# === Integration tests (ported from genprocShiny) =============================
# These require purrr, dplyr, magrittr and are skipped if not installed.

test_that("pipe + lambda expression produces correct parameters", {
  skip_if_not_installed("purrr")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("magrittr")

  # Attach pipe and functions into lookup environment
  e <- new.env(parent = globalenv())

  fn <- from_example_to_function(
    expression({
      get("cars") %>% select(1) %>% (\(x) pull(x, names(x)[[1]])) %>%
        paste0(collapse = " test ") %>%
        (\(p) {
          x <- "test2"
          list(is.numeric(x), p)
        })
    }),
    env = e
  )

  fmls <- formals(fn)

  # "cars", " test ", "test2" = 3 string parameters
  expect_length(fmls, 3)
  expect_equal(fmls$param_1, "cars")
  expect_equal(fmls$param_2, " test ")
  expect_equal(fmls$param_3, "test2")

  # p and x are locally bound -> must NOT appear as parameters
  expect_false("p" %in% names(fmls))
  expect_false("x" %in% names(fmls))

  # Body should still contain the pipe operator
  body_str <- paste(deparse(body(fn)), collapse = " ")
  expect_true(grepl("%>%", body_str))
})

test_that("generated function executes correctly with swapped parameters", {
  skip_if_not_installed("purrr")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("magrittr")

  # Packages must be attached so map/mutate_all/`%>%` are on the search path
  # when the generated function executes
  library(purrr)
  library(dplyr)
  library(magrittr)

  e <- new.env(parent = globalenv())

  fn <- from_example_to_function(
    expression({
      map(c("cars", "mtcars"), get) %>%
        map(mutate_all, as.character)
    }),
    env = e
  )

  # Structure check: 2 parameters (the two dataset name strings)
  fmls <- formals(fn)
  expect_length(fmls, 2)
  expect_equal(fmls$param_1, "cars")
  expect_equal(fmls$param_2, "mtcars")

  # Execution with default parameters
  result_default <- fn()
  expect_true(is.list(result_default))
  expect_length(result_default, 2)
  expect_s3_class(result_default[[1]], "data.frame")
  expect_s3_class(result_default[[2]], "data.frame")
  expect_equal(nrow(result_default[[1]]), nrow(cars))
  expect_equal(nrow(result_default[[2]]), nrow(mtcars))

  # Execution with swapped parameters
  result_swapped <- fn(param_1 = "airquality", param_2 = "anscombe")
  expect_true(is.list(result_swapped))
  expect_length(result_swapped, 2)
  expect_s3_class(result_swapped[[1]], "data.frame")
  expect_s3_class(result_swapped[[2]], "data.frame")
  expect_equal(nrow(result_swapped[[1]]), nrow(airquality))
  expect_equal(nrow(result_swapped[[2]]), nrow(anscombe))
  # All columns should be character (mutate_all(as.character))
  expect_true(all(sapply(result_swapped[[1]], is.character)))
  expect_true(all(sapply(result_swapped[[2]], is.character)))
})
