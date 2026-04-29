# Subset a genproc result to its failed cases

Returns the rows of `result$log` corresponding to cases where
`success == FALSE`. The columns are exactly those of `result$log`
(case_id, mask parameters, success, error_message, traceback,
duration_secs).

## Usage

``` r
errors(x, ...)

# S3 method for class 'genproc_result'
errors(x, ...)
```

## Arguments

- x:

  A `genproc_result` produced by
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).

- ...:

  Unused, for future extensions.

## Value

A data.frame with one row per failed case. Empty data.frame (with the
same columns) if there are no failures. Returns `NULL` (with a message)
if the run is non-blocking and has not been materialized yet.

## See also

[`rerun_failed()`](https://danielrak.github.io/genproc/reference/rerun_failed.md),
[`summary.genproc_result()`](https://danielrak.github.io/genproc/reference/summary.genproc_result.md)

## Examples

``` r
result <- genproc(
  f = function(x) if (x %% 2 == 0) x / 0 else x,
  mask = data.frame(x = 1:6)
)
errors(result)[, c("case_id", "x", "error_message")]
#> [1] case_id       x             error_message
#> <0 rows> (or 0-length row.names)
```
