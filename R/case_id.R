# Case ID generation
#
# Generates a stable, deterministic identifier for each row of a mask.
# The ID is used to link log rows to their source case, for replay,
# and for monitoring.
#
# v0.1: index-based IDs (case_0001, case_0002, ...).
# A future version will use content-based hashing (via digest or
# similar) so that IDs are stable across mask reordering and
# filtering. This will be introduced alongside input file hashing
# for the reproducibility layer.


#' Generate case IDs for each row of a mask
#'
#' Returns a character vector of length `nrow(mask)`, one ID per row.
#'
#' @param mask A data.frame (the iteration mask).
#' @return Character vector of case IDs.
#'
#' @details
#' Current implementation (v0.1) uses zero-padded sequential indices:
#' `case_0001`, `case_0002`, etc. This means IDs depend on row order
#' and will change if the mask is filtered or reordered between runs.
#'
#' A future version will generate content-based IDs (hash of row
#' values) so that the same data always produces the same ID
#' regardless of row position.
#'
#' @noRd
generate_case_ids <- function(mask) {
  n <- nrow(mask)
  if (n == 0) return(character(0))

  # Determine padding width based on total number of cases
  width <- max(4L, nchar(as.character(n)))
  fmt <- paste0("case_%0", width, "d")
  sprintf(fmt, seq_len(n))
}
