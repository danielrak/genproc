# Re-run only the cases impacted by an input diff

Filters the original mask of `r0` down to the cases that referenced
inputs reported as changed, removed, or added by
[`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md),
and re-runs
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
on that subset.

## Usage

``` r
rerun_affected(
  r0,
  diff,
  f,
  parallel = NULL,
  nonblocking = NULL,
  track_inputs = TRUE,
  input_cols = NULL,
  skip_input_cols = NULL
)
```

## Arguments

- r0:

  A `genproc_result` produced by
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).
  Its `$reproducibility$mask_snapshot` provides the original mask; it
  must contain `track_inputs = TRUE` (the default).

- diff:

  A `genproc_input_diff` produced by
  [`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md).

- f:

  A function. Typically the same function passed to the original
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  call. The result object does not store `f`, so it must be supplied
  here.

- parallel, nonblocking, track_inputs, input_cols, skip_input_cols:

  Forwarded to
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  for the re-run. By default, these inherit a sensible behaviour:
  `track_inputs = TRUE` (so the re-run is itself comparable), the other
  arguments default to `NULL` (sequential, blocking, automatic input
  tracking).

## Value

A new `genproc_result` covering only the affected cases. Its `case_id`s
are local to the subset (re-numbered starting at `case_0001`); the link
back to the original `r0` is via the matching rows of
`r0$reproducibility$mask_snapshot`. If `diff` reports no affected cases,
the function returns `NULL` with a message — there is nothing to re-run.

## Details

This is the actionable end of the reproducibility layer: when an
upstream file silently drifts, you do not need to re-run the whole mask.
`rerun_affected()` produces a smaller run that refreshes only the
impacted outputs.

## See also

[`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md),
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)

## Examples

``` r
# \donttest{
  # Set up a tiny workspace with one tracked input file.
  csv <- tempfile(fileext = ".csv")
  write.csv(iris, csv, row.names = FALSE)

  count_rows <- function(p) nrow(read.csv(p))

  r0 <- genproc(count_rows, data.frame(p = csv))

  # ... time passes, the upstream file is silently rewritten ...
  write.csv(head(iris), csv, row.names = FALSE)

  r1 <- genproc(count_rows, data.frame(p = csv))
  d <- diff_inputs(r0, r1)
  # d$cases_affected lists the case_ids whose inputs drifted.

  refreshed <- rerun_affected(r0, d, f = count_rows)
  refreshed$log
#>     case_id                                   p success error_message traceback
#> 1 case_0001 /tmp/RtmpK1P7mD/file1a4dfc8ed7c.csv    TRUE          <NA>      <NA>
#>   duration_secs
#> 1         0.001
# }
```
