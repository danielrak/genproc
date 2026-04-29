#' Transform an example expression into a parameterized function
#'
#' Takes a concrete R expression (e.g. a data processing script that
#' works on one specific case) and returns a function where every
#' external value (strings, variables from the environment that are not
#' functions) has been replaced by a named parameter with the original
#' value as default.
#'
#' This is the first step in the genproc workflow: the user writes a
#' working example, and `from_example_to_function()` extracts a
#' reusable, parameterized version of it.
#'
#' @param expr An expression of length 1, typically created with
#'   [expression()] or [quote()] wrapped in [as.expression()].
#' @param env The environment in which to look up symbols. Symbols found
#'   in this environment that are **not** functions will be turned into
#'   parameters. Defaults to the caller's environment.
#'
#' @return A function whose body is the rewritten expression and whose
#'   formals are the detected parameters with their default values.
#'   The function's environment is set to `env`.
#'
#' @details
#' ## What gets parameterized
#'
#' - **String literals**: every string in the expression becomes a
#'   parameter (e.g. `"output.csv"` -> `param_1` with default
#'   `"output.csv"`).
#' - **Non-function symbols**: if a symbol exists in `env` and its value
#'   is not a function, it becomes a parameter.
#'
#' ## What is left unchanged
#'
#' - **Locally bound symbols**: variables created by assignments inside
#'   the expression (e.g. `result <- ...`) are never parameterized.
#' - **Function names**: the head of a call (e.g. `read.csv` in
#'   `read.csv(path)`) is never parameterized.
#' - **Functions in the environment**: symbols whose value is a function
#'   are assumed to be part of the program structure, not data.
#' - **Numeric, logical, NULL, and other non-character atomic values**.
#'
#' ## Deduplication
#'
#' The same value produces the same parameter. If `"output.csv"` appears
#' twice, both occurrences map to the same `param_N`.
#'
#' @examples
#' # --- Basic usage ---
#' # `input_path` exists in this environment; "output.csv" is a
#' # string literal. Both become parameters of the resulting function,
#' # with their original values as defaults.
#' input_path <- "/data/input.csv"
#'
#' expr <- expression({
#'   df <- read.csv(input_path)
#'   write.csv(df, "output.csv")
#' })
#'
#' fn <- from_example_to_function(expr)
#' formals(fn)
#'
#' # --- Local bindings are protected ---
#' # `x` is assigned inside the block, so it is NOT parameterized
#' # even though x = 42 exists in the calling environment.
#' x <- 42
#' expr2 <- expression({
#'   x <- 1
#'   y <- x + 1
#' })
#' fn2 <- from_example_to_function(expr2)
#' formals(fn2)
#'
#' @export
from_example_to_function <- function(expr, env = parent.frame()) {
  # --- Input validation ---
  if (!(is.expression(expr) && length(expr) == 1)) {
    stop("`expr` must be an expression of length 1.", call. = FALSE)
  }

  # --- Initialize rewrite context ---
  registry <- new_param_registry()
  ctx <- list(
    bound    = character(),
    registry = registry,
    env      = env
  )

  # --- Rewrite the AST ---
  new_body <- rewrite_node(expr[[1]], ctx)

  # --- Assemble the output function ---
  params <- registry_params(registry)
  f <- function() {}
  if (length(params) > 0) {
    formals(f) <- as.pairlist(params)
  }
  body(f) <- new_body
  environment(f) <- env
  f
}
