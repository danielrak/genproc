# genproc 0.0.0.9000 (development)

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

* `from_example_to_function()`: transform an example expression
  into a parameterized function (modular AST rewrite engine, no
  rlang dependency).
* `from_function_to_mask()`: derive a one-row template mask
  (`data.frame`) from a function's signature.
* `rename_function_params()`: rename parameters in formals and
  body.
* `add_trycatch_logrow()`: the low-level logging wrapper used by
  `genproc()`.
