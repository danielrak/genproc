#' Derive an iteration mask template from a function's signature
#'
#' Takes a function (typically produced by [from_example_to_function()])
#' and returns a one-row data.frame where each column corresponds to a
#' parameter, with the default value as the cell value. This "template
#' mask" is the starting point the user expands into a multi-row mask
#' that defines all iteration cases.
#'
#' @param f A function whose formals define the mask columns.
#'
#' @return A one-row data.frame with one column per parameter.
#'   Parameters with default values get those values; parameters
#'   without defaults get `NA`.
#'
#' @details
#' ## What is a mask?
#'
#' In genproc, a **mask** is a data.frame where each row is an iteration
#' case and each column is a parameter. The function [genproc()] will
#' call the user's function once per row, passing column values as
#' arguments.
#'
#' `from_function_to_mask()` produces a one-row template. The user then
#' builds the full mask by adding rows (e.g. via `rbind()`,
#' `dplyr::bind_rows()`, or by constructing a multi-row data.frame
#' directly).
#'
#' ## Current limitations (v0.1)
#'
#' Only scalar atomic defaults are supported (character, numeric,
#' integer, logical). Non-scalar defaults (vectors, lists, data.frames)
#' will be supported in a future version via list-columns. This
#' extension will preserve backwards compatibility: any mask that
#' works today will continue to work unchanged.
#'
#' ## Metadata (case_id, hashes, etc.)
#'
#' The mask returned here is a **pure data.frame of parameter values**.
#' Metadata such as `case_id`, input file hashes, or seeds are managed
#' separately by [genproc()] at execution time — they are not stored
#' as columns or attributes of the mask. This design ensures that
#' standard data.frame operations (`dplyr::filter()`, `[`, `rbind()`)
#' never accidentally strip metadata.
#'
#' When the mask is later generalized to a dedicated class
#' (`genproc_mask`), existing code passing a plain data.frame will
#' continue to work (backwards compatibility is a hard constraint).
#'
#' @examples
#' fn <- function(input_path = "data.csv", n_rows = 100) {
#'   head(read.csv(input_path), n_rows)
#' }
#' mask <- from_function_to_mask(fn)
#' mask
#' #   input_path n_rows
#' # 1   data.csv    100
#'
#' # Expand to multiple cases:
#' full_mask <- data.frame(
#'   input_path = c("a.csv", "b.csv", "c.csv"),
#'   n_rows = c(10, 50, 100)
#' )
#'
#' @export
from_function_to_mask <- function(f) {
  if (!is.function(f)) {
    stop("`f` must be a function.", call. = FALSE)
  }

  fmls <- formals(f)

  if (length(fmls) == 0) {
    stop("`f` has no parameters. A mask requires at least one parameter.",
         call. = FALSE)
  }

  # --- Classify each default value ---
  values <- vector("list", length(fmls))
  names(values) <- names(fmls)

  # Sentinel: a missing formal default in R is an object that errors
  # when accessed directly in some R versions. We detect it safely
  # with tryCatch around identical().
  .missing_sentinel <- alist(.x = )$.x

  for (nm in names(fmls)) {
    # Check for missing default without triggering "argument is missing".
    # tryCatch catches the error if fmls[[nm]] cannot be accessed.
    is_missing <- tryCatch(
      identical(fmls[[nm]], .missing_sentinel),
      error = function(e) TRUE
    )

    if (is_missing) {
      values[[nm]] <- NA
      next
    }

    val <- fmls[[nm]]

    # Named symbol (e.g. function(x = some_var) ...) — treat as missing
    # since the symbol may not be resolvable at mask-creation time
    if (is.symbol(val)) {
      values[[nm]] <- NA_character_
      next
    }

    # Atomic scalar: the expected case
    if (is.atomic(val) && length(val) == 1) {
      values[[nm]] <- val
      next
    }

    # NULL default
    if (is.null(val)) {
      values[[nm]] <- NA
      next
    }

    # Non-scalar or non-atomic: not yet supported
    stop(
      "Parameter `", nm, "` has a non-scalar default value. ",
      "In v0.1, only scalar atomic defaults (character, numeric, ",
      "integer, logical) are supported. Non-scalar defaults (vectors, ",
      "lists) will be supported in a future version via list-columns.",
      call. = FALSE
    )
  }

  # --- Build one-row data.frame ---
  # Use I() for any character values to prevent factor conversion,
  # then drop the AsIs class
  as.data.frame(values, stringsAsFactors = FALSE)
}
