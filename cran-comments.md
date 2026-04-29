## Test environments

* local Windows 10 install, R 4.5.x — passed
* GitHub Actions:
  * ubuntu-latest (release) — passed
  * ubuntu-latest (oldrel-1) — passed
  * ubuntu-latest (devel) — passed
  * macos-latest (release) — passed
  * windows-latest (release) — passed
* win-builder (devel and release) — to be confirmed before submission
* R-hub (Linux / Windows / macOS) — to be confirmed before submission

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Notes for reviewers

* The package wraps iteration constructs (`for`, `lapply()`,
  `purrr::pmap()`) with orthogonal, composable execution layers
  (logged, reproducibility, parallel, non-blocking). It builds on
  the `future` ecosystem for parallelism and is intentionally
  Shiny-free.
* `\dontrun{}` is used in four `genproc()` examples that exercise
  the multisession parallel and non-blocking backends. Spawning R
  subprocesses during automated checks is undesirable; the
  sequential default example earlier in the same Rd file is fully
  runnable and demonstrates the core API.
* The non-blocking multisession test in
  `tests/testthat/test-genproc-nonblocking.R` and the parallel
  multisession test in `tests/testthat/test-genproc-parallel.R`
  both `skip_if_not()` when the package is not installed (the
  worker library() call requires it), which is the standard
  pattern for development-mode `devtools::test()`. Inside a CRAN
  check the package *is* installed, so these tests run.

## Reverse dependencies

This is a new submission; there are no reverse dependencies.

## Future plans

The 0.1.0 release locks the public API of the four current layers
and the `genproc_result` contract. Planned 0.x extensions
(monitored progress, error replay, content-hash input
fingerprinting, content-based case identifiers) are designed to
remain composable with the existing layers without breaking
existing user code.
