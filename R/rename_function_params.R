#' Rename the parameters of a function
#'
#' Takes a function and a name mapping, and returns a new function where
#' both the formals and all symbol references in the body have been
#' renamed according to the mapping. This is typically used after
#' [from_example_to_function()] to replace generated names like
#' `param_1`, `param_2` with meaningful names.
#'
#' @param f A function whose parameters should be renamed.
#' @param mapping A named character vector. Names are the **current**
#'   parameter names, values are the **new** names.
#'   Example: `c(param_1 = "input_path", param_2 = "output_path")`.
#'
#' @return A function with renamed formals and body.
#'
#' @details
#' ## Validation
#'
#' The function checks that:
#' - All names in `mapping` actually exist as formals of `f`
#' - New names are unique (no duplicates)
#' - New names do not collide with parameters not being renamed
#'
#' ## Limitation
#'
#' If the body contains a nested function definition whose formals
#' shadow a parameter being renamed, the shadowed references in that
#' inner body will still be renamed. This is unlikely in practice
#' (parameters from [from_example_to_function()] are named `param_N`)
#' but is noted here for completeness.
#'
#' @examples
#' fn <- function(param_1 = "in.csv", param_2 = "out.csv") {
#'   df <- read.csv(param_1)
#'   write.csv(df, param_2)
#' }
#'
#' fn2 <- rename_function_params(fn, c(
#'   param_1 = "input_path",
#'   param_2 = "output_path"
#' ))
#'
#' # Formals were renamed:
#' formals(fn2)
#'
#' # And the body too — references to `param_1` and `param_2` are
#' # updated in place, the function source is not edited.
#' body(fn2)
#'
#' @export
rename_function_params <- function(f, mapping) {
  if (!is.function(f)) {
    stop("`f` must be a function.", call. = FALSE)
  }
  if (!is.character(mapping) || is.null(names(mapping))) {
    stop("`mapping` must be a named character vector.", call. = FALSE)
  }
  if (any(!nzchar(names(mapping))) || any(!nzchar(mapping))) {
    stop("All names and values in `mapping` must be non-empty strings.",
         call. = FALSE)
  }

  old_names <- names(mapping)
  new_names <- unname(mapping)

  # --- Validate against formals ---
  fmls <- formals(f)
  fml_names <- names(fmls)

  missing_old <- setdiff(old_names, fml_names)
  if (length(missing_old) > 0) {
    stop("These names are not parameters of `f`: ",
         paste(missing_old, collapse = ", "), call. = FALSE)
  }

  if (any(duplicated(new_names))) {
    stop("New parameter names must be unique.", call. = FALSE)
  }

  untouched <- setdiff(fml_names, old_names)
  collisions <- intersect(new_names, untouched)
  if (length(collisions) > 0) {
    stop("New names collide with existing parameters not being renamed: ",
         paste(collisions, collapse = ", "), call. = FALSE)
  }

  # --- Rename formals ---
  names(fmls) <- vapply(fml_names, function(nm) {
    if (nm %in% old_names) mapping[[nm]] else nm
  }, character(1))
  formals(f) <- fmls

  # --- Recursive body rewrite ---
  rewrite_body <- function(node) {
    # Symbol: rename if it matches a mapped name
    if (is.symbol(node)) {
      nm <- as.character(node)
      if (nm %in% old_names) {
        return(as.name(mapping[[nm]]))
      }
      return(node)
    }

    # Pairlist (formals of inner functions): rewrite defaults, keep names
    if (is.pairlist(node)) {
      out <- as.pairlist(lapply(as.list(node), rewrite_body))
      names(out) <- names(node)
      return(out)
    }

    # Call
    if (is.call(node)) {
      parts <- as.list(node)

      # Inner function definition: protect its formals from renaming,
      # but still rewrite its body (outer params may be referenced)
      head <- parts[[1]]
      if (is.symbol(head) && as.character(head) %in% c("function", "\\")) {
        new_parts <- parts
        # parts[[2]] = formals — do NOT rewrite
        if (length(parts) >= 3) {
          new_parts[[3]] <- rewrite_body(parts[[3]])
        }
        return(as.call(new_parts))
      }

      # Generic call: rewrite all parts (including head, which handles
      # cases like `param_1(x)` if a param were used as a function name)
      return(as.call(lapply(parts, rewrite_body)))
    }

    # Anything else (string, numeric, NULL, ...): unchanged
    node
  }

  body(f) <- rewrite_body(body(f))
  f
}
