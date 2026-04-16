# Parameter registry for AST rewriting
#
# Tracks the mapping from detected values (strings, symbols) to generated
# parameter names (param_1, param_2, ...) and their default values.
#
# Uses an environment for reference semantics: the registry is shared across
# all recursive calls to rewrite_node() so that parameter deduplication is
# global to a single from_example_to_function() invocation.


#' Create a new parameter registry
#'
#' @return An environment with components `keys` (named list mapping
#'   detection keys to parameter names), `params` (named list mapping
#'   parameter names to default values), and `count` (integer, number of
#'   parameters registered so far).
#'
#' @examples
#' reg <- new_param_registry()
#' register_param(reg, "chr:hello", "hello")
#' register_param(reg, "chr:hello", "hello")  # returns same param name
#' registry_params(reg)
#'
#' @noRd
new_param_registry <- function() {
  reg <- new.env(parent = emptyenv())
  reg$keys <- list()
  reg$params <- list()
  reg$count <- 0L
  reg
}


#' Register a parameter or retrieve an existing one
#'
#' If a parameter with the given key already exists, returns its name
#' without creating a duplicate. Otherwise, generates a new name
#' (param_1, param_2, ...) and records the default value.
#'
#' @param registry A parameter registry (from [new_param_registry()]).
#' @param key Character(1). A unique key for deduplication. Convention:
#'   `"chr:<value>"` for string literals, `"sym:<name>"` for symbols.
#' @param default The default value for this parameter.
#' @return Character(1). The parameter name (e.g. `"param_1"`).
#'
#' @noRd
register_param <- function(registry, key, default) {
  existing <- registry$keys[[key]]
  if (!is.null(existing)) return(existing)

  registry$count <- registry$count + 1L
  pname <- paste0("param_", registry$count)
  registry$keys[[key]] <- pname
  registry$params[[pname]] <- default
  pname
}


#' Extract the final parameter list from a registry
#'
#' @param registry A parameter registry.
#' @return A named list of default values, suitable for [as.pairlist()].
#'   Empty list if no parameters were registered.
#'
#' @noRd
registry_params <- function(registry) {
  registry$params
}
