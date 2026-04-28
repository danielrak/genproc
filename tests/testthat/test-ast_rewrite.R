# Direct unit tests for the AST helper predicates in R/ast_rewrite.R.
#
# `from_example_to_function()` already covers the integrated behavior;
# these tests pin down the helpers in isolation so that a regression in
# one of them produces a localized failure, not a mysterious downstream
# one. They use getFromNamespace() because the helpers are not exported.

is_missing_arg_node <- utils::getFromNamespace("is_missing_arg_node",
                                               "genproc")
is_assignment_call  <- utils::getFromNamespace("is_assignment_call",
                                               "genproc")
assignment_target   <- utils::getFromNamespace("assignment_target",
                                               "genproc")


# === is_missing_arg_node ======================================================

test_that("is_missing_arg_node detects R's empty argument placeholder", {
  # The empty symbol (zero-character name) is what R uses for `f(a, , b)`'s
  # middle argument. quote(expr = ) yields one.
  expect_true(is_missing_arg_node(quote(expr = )))
})

test_that("is_missing_arg_node rejects normal symbols", {
  expect_false(is_missing_arg_node(quote(x)))
  expect_false(is_missing_arg_node(quote(my_var)))
})

test_that("is_missing_arg_node rejects non-symbol nodes", {
  expect_false(is_missing_arg_node(quote(f(a))))   # call
  expect_false(is_missing_arg_node(1L))            # integer
  expect_false(is_missing_arg_node("x"))           # character
  expect_false(is_missing_arg_node(NULL))          # NULL
})


# === is_assignment_call =======================================================

test_that("is_assignment_call accepts the five R assignment operators", {
  expect_true(is_assignment_call(quote(x <- 1)))
  # `x = 1` standalone in quote() is parsed as a named argument, not an
  # assignment. Extract from a block to obtain the actual assignment AST:
  expect_true(is_assignment_call(quote({x = 1})[[2]]))
  expect_true(is_assignment_call(quote(x <<- 1)))
  expect_true(is_assignment_call(quote(1 -> x)))
  expect_true(is_assignment_call(quote(1 ->> x)))
})

test_that("is_assignment_call rejects non-calls", {
  expect_false(is_assignment_call(quote(x)))       # symbol
  expect_false(is_assignment_call(1L))             # literal
  expect_false(is_assignment_call(NULL))
})

test_that("is_assignment_call rejects non-assignment calls", {
  expect_false(is_assignment_call(quote(f(x))))
  expect_false(is_assignment_call(quote(x + y)))
  expect_false(is_assignment_call(quote(if (x) 1 else 2)))
})


# === assignment_target ========================================================

test_that("assignment_target returns LHS symbol name for left-assignment", {
  expect_equal(assignment_target(quote(x <- 1)),         "x")
  expect_equal(assignment_target(quote({x = 1})[[2]]),   "x")
  expect_equal(assignment_target(quote(x <<- 1)),        "x")
})

test_that("assignment_target returns RHS symbol name for right-assignment", {
  expect_equal(assignment_target(quote(1 -> x)),  "x")
  expect_equal(assignment_target(quote(1 ->> x)), "x")
})

test_that("assignment_target returns NULL when target is not a bare symbol", {
  # x$y <- 1 ; the target is `x$y` (a call, not a symbol). No new
  # binding is introduced by this assignment, so the helper says NULL.
  expect_null(assignment_target(quote(x$y <- 1)))
  expect_null(assignment_target(quote(x[1] <- 1)))
  expect_null(assignment_target(quote(attr(x, "n") <- 5)))
})

test_that("assignment_target returns NULL on non-assignment input", {
  expect_null(assignment_target(quote(f(x))))
  expect_null(assignment_target(quote(x)))
  expect_null(assignment_target(1L))
})
