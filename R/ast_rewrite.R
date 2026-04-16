# AST rewriting engine for from_example_to_function()
#
# This module rewrites an R expression (Abstract Syntax Tree) by replacing
# certain values with parameter references. The result is a parameterized
# version of the original expression, suitable for use as a function body.
#
# ---------------------------------------------------------------------------
# INVARIANTS (these hold for every rewrite and should guide debugging):
#
# 1. Locally bound symbols are NEVER parameterized.
#    A symbol is "locally bound" if it appears as:
#    - the LHS of an assignment  (<-, =, <<-, ->, ->>), or
#    - a formal argument of a function definition (function(x) ...).
#    Once bound, it stays bound for all subsequent statements in the same
#    block and in nested scopes.
#
# 2. Function names (the head of a call) are NEVER parameterized.
#    In  read.csv(path),  `read.csv` is untouched.
#
# 3. String literals are ALWAYS parameterized.
#    "hello" becomes param_N with default "hello".
#
# 4. Symbols referencing non-function values in the lookup environment
#    ARE parameterized.  Symbols referencing functions are left as-is
#    (they are assumed to be program structure, not data).
#
# 5. Symbols not found in the lookup environment are left as-is.
#
# 6. Parameters are deduplicated by key: the same string value or the
#    same symbol always maps to the same parameter name across the
#    entire expression.
#
# 7. Parameter names are generated sequentially: param_1, param_2, ...
#
# ---------------------------------------------------------------------------
# REWRITE CONTEXT
#
# Each rewrite function receives a `ctx` list with three components:
#   $bound    - character vector of locally bound symbol names (scoped)
#   $registry - parameter registry (environment, shared by reference)
#   $env      - the lookup environment for resolving symbol values
#
# Because ctx is a plain list, extending $bound for a sub-scope creates
# a shallow copy (R's copy-on-modify semantics). The $registry, being an
# environment, is shared across all recursive calls -- this is intentional.
# ---------------------------------------------------------------------------


# === Helper predicates ========================================================

#' Test whether a node is a missing argument placeholder
#'
#' In R's AST, a formal parameter without a default (e.g. `a` in
#' `function(a) ...`) is stored as an empty symbol (zero-character name).
#' This function detects them so we can skip rewriting these nodes.
#'
#' @param x An R object (AST node).
#' @return TRUE if x is a missing argument placeholder.
#'
#' @examples
#' # is_missing_arg_node(quote(expr = ))  # TRUE
#' # is_missing_arg_node(quote(x))        # FALSE
#'
#' @noRd
is_missing_arg_node <- function(x) {
  is.symbol(x) && !nzchar(as.character(x))
}


#' Test whether a call node is an assignment
#'
#' Detects all five R assignment operators: `<-`, `=`, `<<-`, `->`, `->>`.
#'
#' @param node An R object.
#' @return TRUE if node is a call to an assignment operator.
#'
#' @examples
#' # is_assignment_call(quote(x <- 1))   # TRUE
#' # is_assignment_call(quote(f(x)))      # FALSE
#' # is_assignment_call(quote(1 -> x))    # TRUE
#'
#' @noRd
is_assignment_call <- function(node) {
  if (!is.call(node)) return(FALSE)
  head <- node[[1]]
  if (!is.symbol(head)) return(FALSE)
  as.character(head) %in% c("<-", "=", "<<-", "->", "->>")
}


#' Extract the target symbol name from an assignment call
#'
#' Returns the name of the symbol being assigned to. For left-assignment
#' (`x <- 1`), the target is `node[[2]]`. For right-assignment (`1 -> x`),
#' the target is `node[[3]]`.
#'
#' Returns NULL if the target is not a bare symbol (e.g. `x$y <- 1`
#' or `x[1] <- 1`), since those do not introduce a new local binding.
#'
#' @param node An assignment call.
#' @return Character(1) (the symbol name) or NULL.
#'
#' @examples
#' # assignment_target(quote(x <- 1))    # "x"
#' # assignment_target(quote(1 -> x))    # "x"
#' # assignment_target(quote(x$y <- 1))  # NULL
#'
#' @noRd
assignment_target <- function(node) {
  if (!is_assignment_call(node)) return(NULL)
  op <- as.character(node[[1]])

  target <- if (op %in% c("->", "->>")) node[[3]] else node[[2]]

  if (is.symbol(target)) {
    nm <- as.character(target)
    if (nzchar(nm) && !is.na(nm)) return(nm)
  }
  NULL
}


# === Rewrite functions (one per AST node type) ================================

#' Rewrite a string literal into a parameter reference
#'
#' Every string literal in the expression becomes a function parameter whose
#' default value is the original string.
#'
#' @param node Character(1). A string literal from the AST.
#' @param ctx  Rewrite context (only `$registry` is used).
#' @return A symbol (name) referencing the registered parameter.
#'
#' @examples
#' # Input:  "output.csv"
#' # Output: symbol `param_1` (with default "output.csv" in registry)
#'
#' @noRd
rewrite_string <- function(node, ctx) {
  key <- paste0("chr:", node)
  pname <- register_param(ctx$registry, key, node)
  as.name(pname)
}


#' Rewrite a symbol, parameterizing it if it references external data
#'
#' Decision tree:
#' - Symbol is locally bound (in ctx$bound)  -> return unchanged
#' - Symbol exists in ctx$env as a function   -> return unchanged
#' - Symbol exists in ctx$env as non-function -> parameterize
#' - Symbol not found in ctx$env              -> return unchanged
#'
#' @param node A symbol (name object).
#' @param ctx  Rewrite context (`$bound`, `$registry`, `$env`).
#' @return A symbol: either the original or a new parameter reference.
#'
#' @examples
#' # Given: my_path <- "/data/input.csv" in env
#' # Input:  symbol `my_path` (not in bound)
#' # Output: symbol `param_1` (default "/data/input.csv" registered)
#'
#' # Given: symbol `x` in bound (local assignment earlier)
#' # Input:  symbol `x`
#' # Output: symbol `x` (unchanged)
#'
#' @noRd
rewrite_symbol <- function(node, ctx) {
  s <- as.character(node)
  if (!nzchar(s) || is.na(s)) return(node)

  # Locally bound: never parameterize (invariant 1)
  if (s %in% ctx$bound) return(node)

  # Look up in environment
  if (exists(s, envir = ctx$env, inherits = TRUE)) {
    val <- get(s, envir = ctx$env, inherits = TRUE)
    if (!is.function(val)) {
      key <- paste0("sym:", s)
      pname <- register_param(ctx$registry, key, val)
      return(as.name(pname))
    }
  }

  # Function or not found: leave as-is (invariants 4-5)
  node
}


#' Rewrite a `{ ... }` block, tracking sequential bindings
#'
#' Statements in a block are walked in order. Each assignment extends the
#' set of locally bound symbols for all subsequent statements. This
#' correctly handles patterns like:
#'
#'   { result <- read.csv(path); nrow(result) }
#'
#' where `result` must not be parameterized in `nrow(result)`.
#'
#' @param node A call with head `{`.
#' @param ctx  Rewrite context.
#' @return The rewritten block call.
#'
#' @examples
#' # Input:  { result <- read.csv(path); nrow(result) }
#' #         (path = "/data/in.csv" in env)
#' # Output: { result <- read.csv(param_1); nrow(result) }
#'
#' @noRd
rewrite_block <- function(node, ctx) {
  args <- as.list(node)
  # args[[1]] is the `{` symbol

  cur_bound <- ctx$bound

  if (length(args) >= 2) {
    for (i in seq.int(2, length(args))) {
      # Build context with current bindings
      stmt_ctx <- ctx
      stmt_ctx$bound <- cur_bound

      # Rewrite statement
      args[[i]] <- rewrite_node(args[[i]], stmt_ctx)

      # If the original statement introduces a binding, extend for next stmts
      new_name <- assignment_target(node[[i]])
      if (!is.null(new_name)) {
        cur_bound <- unique(c(cur_bound, new_name))
      }
    }
  }

  as.call(args)
}


#' Rewrite a function definition, protecting formal arguments
#'
#' In `function(a, b) { a + b }`, formals `a` and `b` are locally bound
#' in the body. Handles both `function(...)` and `\(...)` syntax.
#' The formals list itself is NOT rewritten (its default values are part
#' of the nested function's own interface, not the outer expression's data).
#'
#' @param node A call with head `function` or `\\`.
#' @param ctx  Rewrite context.
#' @return The rewritten function definition call.
#'
#' @examples
#' # Input:  function(x) x + offset   (offset = 10 in env)
#' # Output: function(x) x + param_1  (x is protected as a formal)
#'
#' @noRd
rewrite_function_def <- function(node, ctx) {
  head <- node[[1]]
  formals_node <- node[[2]]
  body_node <- node[[3]]

  # Extract formal parameter names (excluding `...`)
  nms <- names(formals_node)
  if (is.null(nms)) nms <- character()
  nms <- nms[nzchar(nms) & !is.na(nms) & nms != "..."]

  # Extend bound set for the body
  body_ctx <- ctx
  body_ctx$bound <- unique(c(ctx$bound, nms))
  new_body <- rewrite_node(body_node, body_ctx)

  as.call(list(head, formals_node, new_body))
}


#' Rewrite an assignment (LHS untouched, RHS rewritten)
#'
#' The LHS of an assignment is a target, not a value — it is never
#' parameterized (invariant 1). Only the RHS is rewritten.
#'
#' Handles all five operators: `<-`, `=`, `<<-` (left-assignment)
#' and `->`, `->>` (right-assignment, where the value is node[[2]]
#' and the target is node[[3]]).
#'
#' @param node An assignment call.
#' @param ctx  Rewrite context.
#' @return The rewritten assignment call.
#'
#' @examples
#' # Input:  result <- read.csv(path)
#' # Output: result <- read.csv(param_1)
#'
#' # Input:  "output.csv" -> out_file
#' # Output: param_1 -> out_file
#'
#' @noRd
rewrite_assignment <- function(node, ctx) {
  op <- as.character(node[[1]])

  if (op %in% c("->", "->>")) {
    # Right-assignment: value is node[[2]], target is node[[3]]
    value <- rewrite_node(node[[2]], ctx)
    as.call(list(as.name(op), value, node[[3]]))
  } else {
    # Left-assignment: target is node[[2]], value is node[[3]]
    value <- rewrite_node(node[[3]], ctx)
    as.call(list(as.name(op), node[[2]], value))
  }
}


#' Rewrite arguments of a generic function call
#'
#' The function name (call head) is never rewritten (invariant 2).
#' Each argument is rewritten independently. Missing arguments (empty
#' formals in e.g. `f(a, , b)`) are skipped.
#'
#' @param node A call.
#' @param ctx  Rewrite context.
#' @return The rewritten call.
#'
#' @examples
#' # Input:  read.csv(path, header = TRUE)   (path in env)
#' # Output: read.csv(param_1, header = TRUE)
#'
#' @noRd
rewrite_call <- function(node, ctx) {
  args <- as.list(node)
  # args[[1]] is the function head — invariant 2: do not rewrite

  if (length(args) >= 2) {
    for (i in seq.int(2, length(args))) {
      arg <- args[[i]]
      # NULL elements and missing argument placeholders are left as-is
      if (!is.null(arg) && !is_missing_arg_node(arg)) {
        args[[i]] <- rewrite_node(arg, ctx)
      }
    }
  }

  as.call(args)
}


#' Rewrite each element of an expression vector
#'
#' @param node An expression object.
#' @param ctx  Rewrite context.
#' @return The rewritten expression.
#'
#' @noRd
rewrite_expression <- function(node, ctx) {
  out <- lapply(as.list(node), rewrite_node, ctx = ctx)
  as.expression(out)
}


# === Dispatcher ===============================================================

#' Route an AST node to the appropriate rewrite handler
#'
#' This is the central router. Every `rewrite_*` function above calls
#' back into [rewrite_node()] for recursive descent.
#'
#' Dispatch order:
#' 1. character(1)              -> [rewrite_string()]
#' 2. symbol                    -> [rewrite_symbol()]
#' 3. expression                -> [rewrite_expression()]
#' 4. call with head `{`        -> [rewrite_block()]
#' 5. call with head `function` -> [rewrite_function_def()]
#' 6. assignment call           -> [rewrite_assignment()]
#' 7. other call                -> [rewrite_call()]
#' 8. anything else             -> pass through unchanged
#'
#' @param node Any R object (AST node).
#' @param ctx  Rewrite context: `list(bound, registry, env)`.
#' @return The rewritten node.
#'
#' @noRd
rewrite_node <- function(node, ctx) {
  # 1. String literal
  if (is.character(node) && length(node) == 1) {
    return(rewrite_string(node, ctx))
  }

  # 2. Symbol
  if (is.symbol(node)) {
    return(rewrite_symbol(node, ctx))
  }

  # 3. Expression vector
  if (is.expression(node)) {
    return(rewrite_expression(node, ctx))
  }

  # 4-7. Calls
  if (is.call(node)) {
    head <- node[[1]]
    head_name <- if (is.symbol(head)) as.character(head) else NULL

    if (identical(head_name, "{")) {
      return(rewrite_block(node, ctx))
    }

    if (!is.null(head_name) && head_name %in% c("function", "\\")) {
      return(rewrite_function_def(node, ctx))
    }

    if (is_assignment_call(node)) {
      return(rewrite_assignment(node, ctx))
    }

    return(rewrite_call(node, ctx))
  }

  # 8. Anything else (numeric, logical, NULL, ...): unchanged
  node
}
