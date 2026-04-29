# genproc 0.2.0 (development version)

## UX improvements

* Composing `parallel = parallel_spec(...)` and
  `nonblocking = nonblocking_spec(...)` now works out of the box on
  Windows and in RStudio configurations where the wrapper subprocess
  inherits `getOption("mc.cores")` set to 1. Previously, the
  composed call failed with a `parallelly` "only 1 CPU cores
  available" error, and (less visibly) emitted a misleading
  soft-limit warning. `genproc()` now applies two surgical
  adjustments inside the wrapper subprocess in the composed case
  (only when the user has not set their own values): it sets
  `R_PARALLELLY_AVAILABLECORES_METHODS = "system"` to lift the hard
  limit, and raises `options(mc.cores)` to silence the soft-limit
  warning. The calling session is never modified.


# genproc 0.1.0

First public release. The package consolidates the four execution
layers (logged, reproducibility, parallel, non-blocking) and the
building blocks (`from_example_to_function()`,
`from_function_to_mask()`, `rename_function_params()`,
`add_trycatch_logrow()`) under a stable API contract. The
`genproc_result` S3 class fields are guaranteed forward-compatible
across the 0.x series.

## Execution layers

* New `genproc()` runs a function over an iteration mask, with two
  mandatory layers always active:
  * **Logged** — structured log with real traceback (captured via
    `withCallingHandlers()`) and per-case timing.
  * **Reproducibility** — environment snapshot at run start
    (R version, platform, loaded package versions, mask, and
    specs of any optional layer used).
* New `parallel_spec()` and the `parallel` argument of `genproc()`:
  optional parallel dispatch over `future.apply::future_lapply()`.
  Auto-defaults to `"multisession"` when `workers` is passed
  without an explicit `strategy`, restoring the previous plan on
  exit.
* New `nonblocking_spec()` and the `nonblocking` argument of
  `genproc()`: `genproc()` returns immediately with a
  `genproc_result` of status `"running"` while the run continues
  in a background future. Use `status()` to poll, `await()` to
  block until resolution. Composable with `parallel`.
* The reproducibility layer now records a stat-based fingerprint
  (size + mtime) of every input file referenced in the mask.
  Stored in `result$reproducibility$inputs` as
  `(method, files, refs)`. Heuristic detection by default; explicit
  override via `genproc(..., input_cols = ...)` or
  `skip_input_cols = ...`. Disable with `track_inputs = FALSE`.
* New `diff_inputs(r0, r1)` compares the input fingerprints of two
  runs and reports changed / unchanged / added / removed files,
  with a human-readable print method.

## Result object

* New S3 class `genproc_result` with stable fields: `log`,
  `reproducibility`, `n_success`, `n_error`,
  `duration_total_secs`, `status`.
* Per-case errors do not stop the run; they are captured in the
  `log` and surfaced in `n_error`.
* `case_id`s are index-based (`case_0001`, ...) for now; a
  content-based variant is planned.

## Building blocks

* `from_example_to_function()`: turn an example expression that
  works for one case into a parameterized function. String literals
  and free symbols become parameters with the original value as
  default. Built on a dependency-free AST rewriter.
* `from_function_to_mask()`: derive a one-row template `data.frame`
  from a function's signature, ready to be expanded into a full
  iteration mask.
* `rename_function_params()`: rename parameters in formals and body
  in one pass, without editing the function source.
* `add_trycatch_logrow()`: the standalone logging wrapper used by
  `genproc()`, exposed for users who want the logged layer outside
  the full pipeline.
