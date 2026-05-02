# Run a function over a mask with mandatory logging and reproducibility

This is the central function of the genproc package. It takes a function
and an iteration mask (data.frame), calls the function once per row of
the mask, and returns a structured result with:

- a log data.frame (one row per case, with
  success/error/traceback/timing)

- reproducibility information (R version, packages, environment,
  parallel spec)

- the exact mask used

- stable case IDs linking log rows to mask rows

## Usage

``` r
genproc(
  f,
  mask,
  f_mapping = NULL,
  parallel = NULL,
  nonblocking = NULL,
  track_inputs = TRUE,
  input_cols = NULL,
  skip_input_cols = NULL
)
```

## Arguments

- f:

  A function to apply to each row of the mask. Each formal of `f` should
  correspond to a column in `mask` (or have a default value). Can be
  produced by
  [`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md)
  or written by hand.

- mask:

  A data.frame where each row is an iteration case and each column is a
  parameter value. Can be produced by
  [`from_function_to_mask()`](https://danielrak.github.io/genproc/reference/from_function_to_mask.md)
  and expanded by the user.

- f_mapping:

  Optional named character vector to rename `f`'s parameters before
  execution. Passed to
  [`rename_function_params()`](https://danielrak.github.io/genproc/reference/rename_function_params.md).
  Names are current parameter names, values are new names matching
  `mask` columns.

- parallel:

  `NULL` (default, sequential execution) or a `genproc_parallel_spec`
  object produced by
  [`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md).
  When supplied, cases are dispatched to workers via
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html).

- nonblocking:

  `NULL` (default, synchronous call) or a `genproc_nonblocking_spec`
  object produced by
  [`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md).
  When supplied, `genproc()` returns immediately with a `genproc_result`
  of status `"running"`, and the run continues in a background future.
  Use
  [`status()`](https://danielrak.github.io/genproc/reference/status.md)
  to poll the state and
  [`await()`](https://danielrak.github.io/genproc/reference/await.md) to
  block until resolution. Can be combined with `parallel` — the
  non-blocking wrapper envelops the parallel dispatch.

- track_inputs:

  Logical. When `TRUE` (default), genproc detects columns of `mask` that
  reference input files and records their size + mtime in
  `result$reproducibility$inputs`. Use
  [`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md)
  to compare two runs and detect silent input drift. Set to `FALSE` to
  skip input tracking entirely.

- input_cols:

  `NULL` (default) or a character vector of mask column names. When
  supplied, the heuristic detection is bypassed and exactly these
  columns are tracked. Paths that do not exist at capture time are
  recorded with `NA` size/mtime and a warning is emitted. Mutually
  exclusive with `skip_input_cols`.

- skip_input_cols:

  `NULL` (default) or a character vector of mask column names to exclude
  from heuristic detection. Useful when a label column happens to match
  an existing file. Mutually exclusive with `input_cols`.

## Value

An object of class `genproc_result` (a named list) with components:

- log:

  A data.frame with one row per case. Contains all parameter values,
  plus `case_id`, `success`, `error_message`, `traceback`, and
  `duration_secs`.

- reproducibility:

  A list of environment information captured at run start (R version,
  packages, OS, locale, timezone, mask snapshot, parallel spec if any).
  See `capture_reproducibility()`.

- n_success:

  Integer, number of successful cases.

- n_error:

  Integer, number of failed cases.

- duration_total_secs:

  Numeric, total wall-clock time for the entire run.

- status:

  Character. `"done"` for synchronous runs. Future execution layers
  (non-blocking) may return `"running"` or `"error"` here.

The `genproc_result` class is designed for forward compatibility.
Existing fields (`log`, `reproducibility`, `n_success`, `n_error`,
`duration_total_secs`) are guaranteed stable. Future versions may add
new fields (e.g. `worker_id` in the log for parallel runs, or
`collect()`/`poll()` methods for non-blocking execution) but will never
remove or rename existing ones.

## Details

The *logged* and *reproducibility* layers are always active and cannot
be disabled. The *parallel* layer is optional: pass a
[`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md)
to `parallel` to enable it.

### Execution model

Cases are executed **sequentially** in row order by default. Supply
`parallel = parallel_spec(...)` to dispatch them in parallel via the
future ecosystem. The logging and reproducibility layers remain active
in both modes; the parallel layer is strictly additive.

Parallel execution preserves the mask row order in the resulting `log`
data.frame, regardless of the order in which workers return.

Parallel execution requires genproc to be installed (not only loaded via
`devtools::load_all()`) on each worker, because the logging layer
serializes closures whose environments reference genproc internals. The
only exception is `parallel_spec(strategy = "sequential")`, which runs
in the current process and needs nothing extra — this is the recommended
mode for deterministic testing.

### Error handling

Errors in individual cases do **not** stop the run. Each case is wrapped
with
[`add_trycatch_logrow()`](https://danielrak.github.io/genproc/reference/add_trycatch_logrow.md),
which captures the error message and the real traceback (via
`withCallingHandlers`). The run continues with the next case. This holds
identically in sequential and parallel mode.

### Progress monitoring

`genproc()` emits one `progressr` signal per completed case in
sequential and parallel modes. The signals are no-op unless the calling
code is wrapped in `progressr::with_progress(...)`, in which case the
user sees a progress bar (or any other handler chosen via
[`progressr::handlers()`](https://progressr.futureverse.org/reference/handlers.html)):

    library(progressr)
    with_progress(
      result <- genproc(my_fn, mask, parallel = parallel_spec(workers = 4))
    )

Without
[`with_progress()`](https://progressr.futureverse.org/reference/with_progress.html),
there is zero overhead and zero visible change: the integration is a
hook, not a default behaviour. `progressr` is declared in `Suggests`;
the integration is conditional on its installation. The non-blocking
path does not yet emit signals — live monitoring of background runs is
on the roadmap.

### Composing parallel and non-blocking

When both `parallel` and `nonblocking` are supplied, the non-blocking
wrapper envelops the parallel dispatch (one outer future submits the
run, inner workers process the cases). On platforms where the wrapper
subprocess R inherits a restrictive default for `getOption("mc.cores")`
(typically 1 on Windows and in some RStudio configurations),
`parallelly` would otherwise refuse to spawn the inner workers.
`genproc()` works around this with two surgical adjustments inside the
wrapper subprocess, applied *only* in the composed case and *only* when
the user has not set their own values:

1.  Set `R_PARALLELLY_AVAILABLECORES_METHODS = "system"` so that
    `availableCores()` ignores the legacy `mc.cores` option and reports
    the true detected core count (lifts the hard-limit refusal).

2.  Raise `options(mc.cores)` from 1 to the system core count, so that
    `parallelly`'s soft-limit warning no longer fires with a misleading
    "only 1 CPU cores available" message.

The calling session is never modified by either adjustment.

### Case IDs

Each row of the mask receives a `case_id` (currently index-based:
`case_0001`, `case_0002`, ...). This ID appears in the log and can be
used for replay, monitoring, and cross-referencing.

### Parameter matching

The mask does not need to contain a column for every parameter of `f`.
Parameters not present in the mask will use their default values.
However, parameters without defaults that are also missing from the mask
will cause an error before execution starts.

Extra columns in the mask (not matching any parameter) are silently
ignored.

## Examples

``` r
# Sequential run (the default). Returns immediately when done.
result <- genproc(
  f = function(x, y) x + y,
  mask = data.frame(x = c(1, 2, 3), y = c(10, 20, 30))
)
result$log
#>     case_id x  y success error_message traceback duration_secs
#> 1 case_0001 1 10    TRUE          <NA>      <NA>             0
#> 2 case_0002 2 20    TRUE          <NA>      <NA>             0
#> 3 case_0003 3 30    TRUE          <NA>      <NA>             0

# One-off parallel call: genproc installs a temporary multisession
# plan and restores the previous one on exit.
if (FALSE) { # \dontrun{
  result <- genproc(
    f = slow_function,
    mask = big_mask,
    parallel = parallel_spec(workers = 4)
  )
} # }

# Non-blocking + parallel composed: launch in the background,
# keep the console, collect later with await().
if (FALSE) { # \dontrun{
  job <- genproc(
    f = slow_function,
    mask = big_mask,
    parallel    = parallel_spec(workers = 6),
    nonblocking = nonblocking_spec()
  )
  status(job)         # "running" until the future resolves
  job <- await(job)   # blocks; idempotent on already-resolved jobs
  job$log
} # }
```
