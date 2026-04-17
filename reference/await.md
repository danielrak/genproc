# Block until a non-blocking genproc run has resolved

`await()` blocks until the background future of a non-blocking
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
run has resolved, then returns a `genproc_result` with `log`,
`n_success`, `n_error`, `duration_total_secs`, and `status` populated.
If the wrapper future itself crashed (a rare case — user errors inside
individual cases are caught by the logging layer and are *not* wrapper
crashes), the returned object has `status = "error"` and a populated
`error_message`.

## Usage

``` r
await(x, ...)

# S3 method for class 'genproc_result'
await(x, ...)
```

## Arguments

- x:

  An object. Methods exist for `genproc_result`.

- ...:

  Unused, for future extensions.

## Value

A `genproc_result` with `status != "running"`.

## Details

`await()` is idempotent: calling it on a result that has already been
materialized (or was synchronous to begin with) returns it unchanged.

## See also

[`status()`](https://danielrak.github.io/genproc/reference/status.md),
[`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
