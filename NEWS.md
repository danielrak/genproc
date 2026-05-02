# genproc 0.2.0

## New features

* `genproc()` now integrates with the `progressr` framework. When
  the calling code is wrapped in `progressr::with_progress(...)`,
  one progression signal is emitted per completed case (in
  sequential and parallel modes; signals from worker subprocesses
  are propagated by `future.apply`). The user picks any handler
  (text bar, RStudio gadget, beeps, custom) via
  `progressr::handlers()`. Without `with_progress()`, the
  integration is a complete no-op. `progressr` is in `Suggests`;
  the integration is skipped when it is not installed. Live
  monitoring of non-blocking runs is on the roadmap.
* New `errors(result)` returns the failed-case rows of the log
  with all original columns (case_id, mask params, error_message,
  traceback, duration_secs). Replaces the boilerplate
  `result$log[!result$log$success, ]` pattern.
* New `summary(result)` (S3 method on `genproc_result`) produces
  a compact human-readable digest: status, success rate,
  per-case duration stats (mean, max, slowest case_id), and the
  top recurring error messages by occurrence (configurable via
  `top_errors`). Useful on runs with many cases where the raw log
  is too noisy to eyeball.
* New `rerun_failed(r0, f)` helper. Sibling of
  `rerun_affected()`: filters the original mask down to the cases
  that failed and re-runs `genproc()` on that subset only. Useful
  after fixing the cause of a transient failure.
* New `rerun_affected(r0, diff, f)` helper. Closes the
  reproducibility loop: when [diff_inputs()] reports drift between
  two runs, `rerun_affected()` filters the original mask down to
  the cases that referenced the impacted files and re-runs
  `genproc()` on that subset only. The resulting `genproc_result`
  is a small refresh, not a full re-run.
* `diff_inputs()` now returns a new `$cases_affected` field: a
  data.frame with columns `case_id`, `path`, `column`,
  `change_type` listing every (case, input column) pair impacted
  by the diff. Available both programmatically and as input to
  `rerun_affected()`. The print method also shows a concise
  summary ("Cases affected: N") and a hint towards
  `rerun_affected()`.
* `print.genproc_input_diff` now distinguishes small size
  variations whose human-readable rounding is identical: when the
  formatted size is the same on both sides, the byte delta is
  shown explicitly (`size: 1.1 KB -> 1.1 KB (+6 B)`).

## UX improvements

* `result$reproducibility$parallel` now carries an
  `effective_strategy` field alongside the user-requested
  `strategy`. The two differ when the user passed `workers`
  without an explicit `strategy`, in which case `genproc()`
  auto-defaults to `"multisession"`; the snapshot now records
  both, preserving the audit trail of what was requested vs
  what was applied. The `Mode` line of `print(result)` now
  shows the effective strategy by default, so a sequential vs
  parallel multisession run is no longer ambiguous in the
  printed summary.

* `status()` now distinguishes `"done"` (the wrapper future
  resolved successfully) from `"error"` (the wrapper crashed),
  even before [await()] is called. Previously `status()` returned
  `"done"` as soon as the future was resolved, regardless of
  outcome — leading to the misleading
  `Status: done (not collected)` print on a job that had actually
  failed. The peek result is cached in a shared environment so
  that a subsequent `await()` does not re-materialize the future.
* `print(result)` is more informative: a `Started` line shows the
  run's timestamp, a `Mode` line summarises the execution
  configuration (`sequential`, `multisession parallel (4 workers)`,
  `non-blocking + multisession parallel (6 workers)`, etc.), and
  the method emits `errors(x)` / `summary(x)` hints when failures
  occurred. The non-blocking print also distinguishes
  `done (not collected)` from `error (not collected)`.

* When `parallel` was used but startup overhead clearly dominated
  the run, `print(result)` now emits a `Note` warning. Two
  metrics: parallel efficiency below 50% when `workers` is
  supplied (catches cases like `parallel_spec(workers = 4)` that
  yield no real speedup), or wall-clock above `cumulative * 1.2`
  in power-user mode (workers unknown). Both require wall > 0.5s
  to avoid noise. Addresses the common surprise of activating
  parallel on a small workload and observing a slowdown.

* Tracebacks captured by the logged layer are now substantially
  shorter and easier to read. Internal dispatcher frames
  (`execute_cases`, `do.call`, `FUN`), invocation context frames
  (`source`, `eval`, `withVisible`), and PSOCK worker frames
  (`workRSOCK`, `workLoop`, `workCommand`, `makeSOCKmaster`) are now
  dropped from the head of the stack, so the first surviving frame
  is always user code. User calls to `lapply()` or `do.call()` from
  within their own function are preserved (the head-position filter
  only consumes leading frames).

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
