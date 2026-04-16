# Reproducibility capture
#
# Records the execution environment at run time so that a run can be
# audited or compared later. This is one of the two mandatory layers
# in genproc (the other being logging).
#
# Captured information:
#   - R version
#   - Platform / OS
#   - Locale and timezone
#   - Loaded packages with their versions
#   - Timestamp of the run
#   - Snapshot of the exact mask used
#   - Parallel execution spec (if any)
#
# Not yet captured (planned):
#   - Hashes of input files referenced in the mask (requires knowing
#     which columns are file paths)
#   - Seed state for non-parallel runs (parallel runs already expose
#     the master seed through the parallel spec)


#' Capture reproducibility information for a genproc run
#'
#' Collects a snapshot of the R environment at the moment the run
#' starts. This snapshot is stored in the result object returned by
#' [genproc()] and can be compared across runs.
#'
#' @param mask The mask data.frame used for this run (stored as-is).
#' @param parallel `NULL` or a `genproc_parallel_spec` object. When
#'   supplied, its fields (strategy, workers, seed, chunk_size,
#'   packages) are recorded in the snapshot so that a parallel run
#'   can be compared to a sequential one and any parameter drift is
#'   auditable.
#' @return A list with components:
#'   \describe{
#'     \item{timestamp}{POSIXct, start time of the run.}
#'     \item{r_version}{Character, e.g. `"R version 4.3.1 (2023-06-16)"`.}
#'     \item{platform}{Character, e.g. `"x86_64-w64-mingw32/x64"`.}
#'     \item{os}{Character, OS name and version.}
#'     \item{locale}{Character, current locale string.}
#'     \item{timezone}{Character, current timezone.}
#'     \item{packages}{Named character vector: package name -> version.}
#'     \item{mask_snapshot}{The exact mask data.frame used.}
#'     \item{parallel}{`NULL` for a sequential run, or a list with the
#'       parallel spec's fields for a parallel run.}
#'   }
#'
#' @noRd
capture_reproducibility <- function(mask, parallel = NULL) {
  # System information
  si <- Sys.info()

  # Loaded packages (attached + loaded via namespace)
  sess <- utils::sessionInfo()

  attached_pkgs <- sess$otherPkgs
  loaded_pkgs <- sess$loadedOnly

  all_pkgs <- c(attached_pkgs, loaded_pkgs)
  if (length(all_pkgs) > 0) {
    pkg_versions <- vapply(all_pkgs, function(p) {
      as.character(p$Version)
    }, character(1))
  } else {
    pkg_versions <- character(0)
  }

  # Also include base R packages
  base_pkgs <- sess$basePkgs
  base_versions <- vapply(base_pkgs, function(p) {
    as.character(utils::packageVersion(p))
  }, character(1))

  all_versions <- c(pkg_versions, base_versions)

  # Normalize parallel spec -> plain list (or NULL).
  # We drop the class so the snapshot is portable to e.g. JSON/YAML
  # export in the future without pulling in the class definition.
  parallel_snapshot <- if (is.null(parallel)) {
    NULL
  } else {
    list(
      strategy   = parallel$strategy,
      workers    = parallel$workers,
      chunk_size = parallel$chunk_size,
      seed       = parallel$seed,
      packages   = parallel$packages
    )
  }

  list(
    timestamp     = Sys.time(),
    r_version     = R.version.string,
    platform      = R.version$platform,
    os            = paste(si[["sysname"]], si[["release"]]),
    locale        = Sys.getlocale(),
    timezone      = Sys.timezone(),
    packages      = all_versions,
    mask_snapshot = mask,
    parallel      = parallel_snapshot
  )
}
