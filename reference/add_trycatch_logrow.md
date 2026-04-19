# Wrap a function with error handling and a structured log row

Takes a function and returns a modified version that:

- always returns a one-row data.frame (the "log row")

- captures errors without stopping, recording the error message and the
  **real** traceback (call stack at the point of failure)

- records wall-clock execution time

## Usage

``` r
add_trycatch_logrow(f)
```

## Arguments

- f:

  A function to wrap.

## Value

A function with the same formals as `f`, whose return value is a one-row
data.frame with columns: all original arguments, `success` (logical),
`error_message` (character or `NA`), `traceback` (character or `NA`),
`duration_secs` (numeric).

## Details

### Why not plain tryCatch?

[`tryCatch()`](https://rdrr.io/r/base/conditions.html) unwinds the call
stack before entering the error handler. This means
[`sys.calls()`](https://rdrr.io/r/base/sys.parent.html) inside a
`tryCatch` error handler returns the handler's own stack, not the stack
that led to the error.

This function uses
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) (which
fires while the original stack is still intact) to capture the
traceback, then lets the error propagate to an outer
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) for control flow.

### Log row structure

The returned data.frame always has one row. Columns:

- One column per formal argument of `f`, with the value passed

- `success`: `TRUE` if the body executed without error

- `error_message`: the error's
  [`conditionMessage()`](https://rdrr.io/r/base/conditions.html), or
  `NA`

- `traceback`: the formatted call stack at the error, or `NA`

- `duration_secs`: wall-clock seconds elapsed

## Examples

``` r
safe_sqrt <- add_trycatch_logrow(function(x) sqrt(x))
safe_sqrt(4)    # success = TRUE, duration_secs > 0
#>   x success error_message traceback duration_secs
#> 1 4    TRUE          <NA>      <NA>             0
safe_sqrt("a")  # success = FALSE, error_message filled, traceback filled
#>   x success                                 error_message
#> 1 a   FALSE non-numeric argument to mathematical function
#>                                                                                                                                                                                                                                                                                                                                                                                                                                                                       traceback
#> 1 1. build_site(pkg, preview = FALSE, install = install, new_process = new_process, ...)\n2. build_site_local(pkg = pkg, examples = examples, run_dont_run = run_dont_run, seed = seed, lazy = lazy, override = o ...\n3. build_reference(pkg, lazy = lazy, examples = examples, run_dont_run = run_dont_run, seed = seed, override = override ...\n4. unwrap_purrr_error(purrr::map(topics, build_reference_topic, pkg = pkg, lazy = lazy, examples_env = examples_env, ru ...
#>   duration_secs
#> 1             0
```
