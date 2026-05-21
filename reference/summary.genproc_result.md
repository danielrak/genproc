# Summarise a genproc result

Produces a compact digest of the run: status, success rate, duration
stats, and the top recurring error messages. Useful on runs with a lot
of cases where the raw log is too noisy to eyeball.

## Usage

``` r
# S3 method for class 'genproc_result'
summary(object, top_errors = 10L, ...)
```

## Arguments

- object:

  A `genproc_result` produced by
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).

- top_errors:

  Integer. Maximum number of distinct error messages to include in the
  summary, ranked by occurrence. Default 10.

- ...:

  Unused, for future extensions.

## Value

An object of class `genproc_result_summary` (a list) with components:

- materialized:

  Logical. `FALSE` if the run is non-blocking and has not been collected
  via
  [`await()`](https://danielrak.github.io/genproc/reference/await.md).
  In that case the other fields are `NA`.

- status:

  Character, mirrors `result$status`.

- n_cases:

  Integer.

- n_success, n_error:

  Integers.

- success_rate:

  Numeric in 0..1.

- duration_total_secs:

  Numeric, wall-clock total.

- duration_stats:

  List with `total`, `mean`, `max`, and `slowest_case_id`. `NULL` if no
  per-case durations.

- top_errors:

  data.frame with columns `error_message` and `count`, sorted by count
  descending. Trimmed to `top_errors` rows.

## See also

[`errors()`](https://danielrak.github.io/genproc/reference/errors.md),
[`rerun_failed()`](https://danielrak.github.io/genproc/reference/rerun_failed.md)

## Examples

``` r
result <- genproc(
  f = function(x) {
    if (x %% 2 == 0) stop("even")
    if (x %% 3 == 0) stop("multiple of three")
    x
  },
  mask = data.frame(x = 1:12)
)
summary(result)
#> genproc result summary
#>   Status     : done
#>   Cases      : 12 (4 ok, 8 error)
#>   Success    : 33%
#>   Total time : 0.02s
#>   Per case   : mean 0.000s, max 0.001s (slowest: case_0003)
#> 
#> Top errors:
#>     6x  even
#>     2x  multiple of three
```
