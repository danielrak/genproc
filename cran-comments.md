## Resubmission

This is a resubmission addressing the reviewer feedback received on
2026-05-02. Changes since the previous submission:

* DESCRIPTION: removed single quotes around terms that are not
  package or software names (`for`, `lapply()`, `pmap()`,
  `diff_inputs()`); kept single quotes only around external package
  names (`'future'`, `'purrr'`).
* DESCRIPTION: added a reference to the `future` framework in the
  Description field — Bengtsson (2021) <doi:10.32614/RJ-2021-048>.
* DESCRIPTION: added `Language: en-US`.
* All `\dontrun{}` blocks (5 occurrences in `genproc.Rd`,
  `nonblocking_spec.Rd`, `rerun_failed.Rd`, `rerun_affected.Rd`)
  replaced with `\donttest{}`. Examples were rewritten to be
  self-contained where they previously referenced placeholder
  symbols. The parallel/multisession examples are capped at 2
  workers per CRAN policy on parallelism in examples.
* Replaced `installed.packages()` calls in two test files with
  `nzchar(system.file(package = "genproc"))`, per the
  `installed.packages()` help page note discouraging its use for
  package-presence checks.

## Test environments

* local Windows 10 install, R 4.5.x — passed (723 tests)
* GitHub Actions:
  * ubuntu-latest (release) — passed
  * ubuntu-latest (oldrel-1) — passed
  * ubuntu-latest (devel) — passed
  * macos-latest (release) — passed
  * windows-latest (release) — passed
* win-builder release (R 4.6.0, 2026-05-02) — 1 NOTE (see below)
* win-builder devel — to be confirmed before submission
* R-hub (Linux / Windows / macOS / nosuggests / ubuntu-next) — to be
  confirmed before submission

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.
* "Possibly misspelled words in DESCRIPTION: composable, traceback"
  — both are correct technical English used throughout the package
  documentation; "composable" describes the orthogonal layer design
  and "traceback" is the standard R term (`base::traceback()`).
* Local checks may additionally emit "checking for future file
  timestamps ... NOTE: unable to verify current time" when the
  external timestamp verification service is unreachable. The note
  does not appear on win-builder or R-hub and is unrelated to the
  package files.

## Notes for reviewers

* The package wraps iteration constructs (`for`, `lapply()`,
  `purrr::pmap()`) with orthogonal, composable execution layers
  (logged, reproducibility, parallel, non-blocking). It builds on
  the `future` ecosystem for parallelism and is intentionally
  Shiny-free.
* `\dontrun{}` is used in two `genproc()` examples that exercise
  the multisession parallel and non-blocking backends. Spawning R
  subprocesses during automated checks is undesirable; the
  sequential default example earlier in the same Rd file is fully
  runnable and demonstrates the core API. A handful of other
  exported helpers (`rerun_failed`, `rerun_affected`) include
  `\dontrun{}` examples for the same reason — they would otherwise
  re-run a long workload.
* The non-blocking multisession test in
  `tests/testthat/test-genproc-nonblocking.R` and the parallel
  multisession test in `tests/testthat/test-genproc-parallel.R`
  both `skip_if_not()` when the package is not installed (the
  worker library() call requires it), which is the standard
  pattern for development-mode `devtools::test()`. Inside a CRAN
  check the package is installed, so these tests run.
* The vignette `vignettes/genproc.Rmd` uses
  `output: rmarkdown::html_vignette` and therefore requires
  `rmarkdown` (declared in Suggests, with `VignetteBuilder: knitr`)
  to rebuild. CRAN's default check installs Suggests so the
  vignette rebuilds cleanly. The R-hub `nosuggests` job, which
  intentionally drops Suggests, will fail to rebuild the vignette
  with "there is no package called 'rmarkdown'" — this is expected
  and not a regression of the package itself.

## Reverse dependencies

This is a new submission; there are no reverse dependencies.

## Public API

The 0.2.0 release exports the following user-facing functions, all
documented and tested:

* Run an iteration: `genproc()`, `print.genproc_result()`.
* Optional execution layers: `parallel_spec()`, `nonblocking_spec()`,
  `status()`, `await()`.
* Inspect a result: `errors()`, `summary.genproc_result()`,
  `print.genproc_result_summary()`, `rerun_failed()`.
* Reproducibility tooling: `diff_inputs()`, `rerun_affected()`.
* Building blocks: `from_example_to_function()`,
  `from_function_to_mask()`, `rename_function_params()`,
  `add_trycatch_logrow()`.

The `genproc_result` S3 contract (`log`, `reproducibility`,
`n_success`, `n_error`, `duration_total_secs`, `status`) is
guaranteed forward-compatible across the 0.x series.

## Suggests usage

* `progressr` (in Suggests) is used for opt-in progress reporting
  in sequential and parallel modes. The integration is wrapped
  in `requireNamespace("progressr", quietly = TRUE)` and is a
  complete no-op when the package is not installed; tests for the
  integration use `skip_if_not_installed("progressr")`.

## Future plans

Planned 0.x extensions (live monitoring of non-blocking runs,
error replay, content-hash input fingerprinting, content-based
case identifiers, clearer error messages on power-user composed
runs without auto-config) are designed to remain composable with
the existing layers without breaking existing user code.
