# Tests for clean_traceback()
#
# Direct unit tests on the private helper. The function is called via
# getFromNamespace because it is intentionally not exported.

clean_tb <- utils::getFromNamespace("clean_traceback", "genproc")


# === Empty / degenerate input ================================================

test_that("returns NA on empty calls", {
  expect_identical(clean_tb(list()), NA_character_)
})

test_that("returns NA when only machinery / signals remain after filtering", {
  calls <- list(
    quote(tryCatch(...)),
    quote(withCallingHandlers(...)),
    quote(.handleSimpleError(h, msg))
  )
  expect_identical(clean_tb(calls), NA_character_)
})


# === tryCatch / withCallingHandlers block drop (existing behavior) ===========

test_that("drops the tryCatch/withCallingHandlers block", {
  calls <- list(
    quote(my_user_fn(x)),
    quote(tryCatch(expr, error = handler)),
    quote(tryCatchList(expr, classes, parentenv, handlers)),
    quote(tryCatchOne(expr, names, parentenv, handlers)),
    quote(withCallingHandlers(expr, error = h)),
    quote(stop("boom"))
  )
  out <- clean_tb(calls)
  expect_false(grepl("tryCatch", out))
  expect_false(grepl("withCallingHandlers", out))
  expect_true(grepl("my_user_fn", out))
  expect_true(grepl("stop", out))
})


# === Signal-frame drop (existing behavior) ===================================

test_that("drops simpleError / .handleSimpleError frames", {
  calls <- list(
    quote(my_user_fn(x)),
    quote(simpleError("bad")),
    quote(.handleSimpleError(h, msg, call)),
    quote(stop("bad"))
  )
  out <- clean_tb(calls)
  expect_false(grepl("simpleError", out))
  expect_false(grepl("\\.handleSimpleError", out))
  expect_true(grepl("my_user_fn", out))
  expect_true(grepl("stop", out))
})


# === Anonymous-fn drop (existing behavior) ===================================

test_that("drops anonymous-function-call frames (genproc handler)", {
  # An anonymous-fn call has a call object as head, not a symbol.
  anon_call <- as.call(list(
    call("function", as.pairlist(alist(.__e__ = )), quote({ NULL })),
    quote(err)
  ))
  calls <- list(
    quote(my_user_fn(x)),
    anon_call,
    quote(stop("bad"))
  )
  out <- clean_tb(calls)
  expect_true(grepl("my_user_fn", out))
  expect_true(grepl("stop", out))
  # The anonymous fn frame deparses to "(function(.__e__) {...})(err)";
  # we want to make sure it is gone.
  expect_false(grepl("__e__", out))
})


# === Leading dispatcher drop (NEW — F3 phase 1) ==============================

test_that("drops leading genproc dispatcher frames (sequential path)", {
  # Stack reproducing what a sequential genproc() error produces
  # when called interactively from the console:
  # genproc -> execute_cases -> lapply -> FUN -> do.call -> user_fn -> stop
  calls <- list(
    quote(genproc(my_user_fn, mask)),
    quote(execute_cases(f_logged, args_list, parallel)),
    quote(lapply(args_list, function(args) do.call(f_logged, args))),
    quote(FUN(X[[i]], ...)),
    quote(do.call(f_logged, args)),
    quote(my_user_fn(input)),
    quote(stop("bad"))
  )
  out <- clean_tb(calls)
  # All dispatcher frames must disappear from the head.
  expect_false(grepl("genproc\\(", out))
  expect_false(grepl("execute_cases", out))
  expect_false(grepl("^[0-9]+\\.\\s+lapply\\(args_list", out))
  expect_false(grepl("^[0-9]+\\.\\s+FUN", out))
  expect_false(grepl("^[0-9]+\\.\\s+do\\.call", out))
  # User code must remain.
  expect_true(grepl("my_user_fn", out))
  expect_true(grepl("stop", out))
  # First surviving line should be the user fn.
  first_line <- strsplit(out, "\n", fixed = TRUE)[[1L]][1L]
  expect_true(grepl("my_user_fn", first_line))
})

test_that("drops leading PSOCK worker frames (parallel path)", {
  # Stack reproducing what a parallel multisession run produces.
  calls <- list(
    quote(workRSOCK()),
    quote(workLoop(makeSOCKmaster(master, port, t1, t2, useXDR, setup_strategy))),
    quote(workCommand(master)),
    quote(my_user_fn(input)),
    quote(stop("bad"))
  )
  out <- clean_tb(calls)
  expect_false(grepl("workRSOCK", out))
  expect_false(grepl("workLoop", out))
  expect_false(grepl("workCommand", out))
  expect_true(grepl("my_user_fn", out))
  expect_true(grepl("stop", out))
})

test_that("drops invocation-context frames (source/eval/withVisible)", {
  # Stack when genproc() is run inside a sourced script.
  calls <- list(
    quote(source("script.R", echo = TRUE)),
    quote(withVisible(eval(ei, envir))),
    quote(eval(ei, envir)),
    quote(execute_cases(f_logged, args_list, parallel)),
    quote(do.call(f_logged, args)),
    quote(my_user_fn(input)),
    quote(stop("bad"))
  )
  out <- clean_tb(calls)
  expect_false(grepl("source\\(", out))
  expect_false(grepl("withVisible", out))
  expect_false(grepl("^[0-9]+\\.\\s+eval\\(", out))
  expect_false(grepl("execute_cases", out))
  expect_true(grepl("my_user_fn", out))
})

test_that("does NOT drop user `lapply` or `do.call` calls (mid-stack)", {
  # User legitimately uses lapply / do.call inside their function.
  # Those frames are NOT at the head of the stack — they come AFTER
  # the user fn itself — so the head-position filter (which stops at
  # the first frame whose head is not in the dispatcher list) leaves
  # them in place.
  calls <- list(
    # genproc machinery — leading
    quote(genproc(my_user_fn, mask)),
    quote(execute_cases(f_logged, args_list, parallel)),
    quote(lapply(args_list, function(args) do.call(f_logged, args))),
    quote(do.call(f_logged, args)),
    # user code starts here
    quote(my_user_fn(x)),
    # user does their own iteration on items
    quote(lapply(items, my_inner_fn)),
    quote(my_inner_fn(item)),
    # user does their own do.call too
    quote(do.call(handle_one, list(item))),
    quote(handle_one(item)),
    quote(stop("inner failure"))
  )
  out <- clean_tb(calls)
  # Leading machinery dropped.
  expect_false(grepl("execute_cases", out))
  expect_false(grepl("genproc\\(", out))
  # User code preserved — including their lapply / do.call.
  expect_true(grepl("my_user_fn", out))
  expect_true(grepl("lapply\\(items", out))
  expect_true(grepl("my_inner_fn", out))
  expect_true(grepl("do\\.call\\(handle_one", out))
  expect_true(grepl("handle_one", out))
})


# === Truncation =============================================================

test_that("truncates very long lines", {
  long_arg <- paste(rep("x", 200L), collapse = "")
  calls <- list(
    str2lang(sprintf('my_fn("%s")', long_arg)),
    quote(stop("boom"))
  )
  out <- clean_tb(calls, max_width = 60L)
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_true(all(nchar(lines) <= 60L + 4L))  # "+ 4" for the leading "N. " prefix
})


# === Frame numbering ========================================================

test_that("frames are numbered sequentially after filtering", {
  calls <- list(
    quote(execute_cases(f_logged, args_list, parallel)),
    quote(do.call(f_logged, args)),
    quote(level_1()),
    quote(level_2()),
    quote(stop("bad"))
  )
  out <- clean_tb(calls)
  lines <- strsplit(out, "\n", fixed = TRUE)[[1L]]
  expect_match(lines[1L], "^1\\.\\s")
  expect_match(lines[2L], "^2\\.\\s")
  expect_match(lines[3L], "^3\\.\\s")
})
