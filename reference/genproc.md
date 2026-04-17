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
genproc(f, mask, f_mapping = NULL, parallel = NULL, nonblocking = NULL)
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
# Sequential (default)
result <- genproc(
  f = function(x, y) x + y,
  mask = data.frame(x = c(1, 2, 3), y = c(10, 20, 30))
)
result$log
#>     case_id x  y success error_message traceback duration_secs
#> 1 case_0001 1 10    TRUE          <NA>      <NA>             0
#> 2 case_0002 2 20    TRUE          <NA>      <NA>             0
#> 3 case_0003 3 30    TRUE          <NA>      <NA>             0

# Parallel — uses whatever future::plan() is currently set
if (FALSE) { # \dontrun{
  future::plan(future::multisession, workers = 4)
  result <- genproc(
    f = slow_function,
    mask = big_mask,
    parallel = parallel_spec(seed = 42L)
  )
} # }

# One-off parallel call, temporary plan, restored on exit
if (FALSE) { # \dontrun{
  result <- genproc(
    f = my_fn,
    mask = my_mask,
    parallel = parallel_spec(strategy = "multisession", workers = 4)
  )
} # }

# Non-blocking: return immediately, keep the console, collect later
if (FALSE) { # \dontrun{
  job <- genproc(
    f = slow_fn,
    mask = big_mask,
    nonblocking = nonblocking_spec()
  )
  status(job)              # "running" or "done"
  job <- await(job)        # blocks until resolution
  job$log
} # }

# Parallel + non-blocking composed
if (FALSE) { # \dontrun{
  job <- genproc(
    f = slow_fn,
    mask = big_mask,
    parallel    = parallel_spec(workers = 6),
    nonblocking = nonblocking_spec()
  )
  # do other work here
  job <- await(job)
} # }
```
