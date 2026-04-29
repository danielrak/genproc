# Changelog

## genproc 0.1.0

First public release. The package consolidates the four execution layers
(logged, reproducibility, parallel, non-blocking) and the building
blocks
([`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md),
[`from_function_to_mask()`](https://danielrak.github.io/genproc/reference/from_function_to_mask.md),
[`rename_function_params()`](https://danielrak.github.io/genproc/reference/rename_function_params.md),
[`add_trycatch_logrow()`](https://danielrak.github.io/genproc/reference/add_trycatch_logrow.md))
under a stable API contract. The `genproc_result` S3 class fields are
guaranteed forward-compatible across the 0.x series.

### Execution layers

- New
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  runs a function over an iteration mask, with two mandatory layers
  always active:
  - **Logged** — structured log with real traceback (captured via
    [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html))
    and per-case timing.
  - **Reproducibility** — environment snapshot at run start (R version,
    platform, loaded package versions, mask, and specs of any optional
    layer used).
- New
  [`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md)
  and the `parallel` argument of
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md):
  optional parallel dispatch over
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html).
  Auto-defaults to `"multisession"` when `workers` is passed without an
  explicit `strategy`, restoring the previous plan on exit.
- New
  [`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
  and the `nonblocking` argument of
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md):
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  returns immediately with a `genproc_result` of status `"running"`
  while the run continues in a background future. Use
  [`status()`](https://danielrak.github.io/genproc/reference/status.md)
  to poll,
  [`await()`](https://danielrak.github.io/genproc/reference/await.md) to
  block until resolution. Composable with `parallel`.
- The reproducibility layer now records a stat-based fingerprint (size +
  mtime) of every input file referenced in the mask. Stored in
  `result$reproducibility$inputs` as `(method, files, refs)`. Heuristic
  detection by default; explicit override via
  `genproc(..., input_cols = ...)` or `skip_input_cols = ...`. Disable
  with `track_inputs = FALSE`.
- New `diff_inputs(r0, r1)` compares the input fingerprints of two runs
  and reports changed / unchanged / added / removed files, with a
  human-readable print method.

### Result object

- New S3 class `genproc_result` with stable fields: `log`,
  `reproducibility`, `n_success`, `n_error`, `duration_total_secs`,
  `status`.
- Per-case errors do not stop the run; they are captured in the `log`
  and surfaced in `n_error`.
- `case_id`s are index-based (`case_0001`, …) for now; a content-based
  variant is planned.

### Building blocks

- [`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md):
  transform an example expression into a parameterized function (modular
  AST rewrite engine, no rlang dependency).
- [`from_function_to_mask()`](https://danielrak.github.io/genproc/reference/from_function_to_mask.md):
  derive a one-row template mask (`data.frame`) from a function’s
  signature.
- [`rename_function_params()`](https://danielrak.github.io/genproc/reference/rename_function_params.md):
  rename parameters in formals and body.
- [`add_trycatch_logrow()`](https://danielrak.github.io/genproc/reference/add_trycatch_logrow.md):
  the low-level logging wrapper used by
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).
