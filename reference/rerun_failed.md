# Re-run only the cases that failed

Filters the original mask of `r0` down to the cases for which
`success == FALSE` and re-runs
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
on that subset. Useful when a transient external problem caused some
cases to fail and the user has fixed the cause: rather than re-running
the whole mask, only the failed cases are refreshed.

## Usage

``` r
rerun_failed(
  r0,
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
  Its `$reproducibility$mask_snapshot` provides the original mask.

- f:

  A function. Typically the same function passed to the original
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  call. The result object does not store `f`, so it must be supplied
  here. If the previous failures were caused by a bug in `f`, pass the
  corrected version.

- parallel, nonblocking, track_inputs, input_cols, skip_input_cols:

  Forwarded to
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  for the re-run.

## Value

A new `genproc_result` covering only the failed cases. Its `case_id`s
are local to the subset (re-numbered starting at `case_0001`); the link
back to the original `r0` is via the matching rows of
`r0$reproducibility$mask_snapshot`. If `r0` has zero failed cases, the
function returns `NULL` with a message — there is nothing to re-run.

## See also

[`rerun_affected()`](https://danielrak.github.io/genproc/reference/rerun_affected.md),
[`errors()`](https://danielrak.github.io/genproc/reference/errors.md),
[`summary.genproc_result()`](https://danielrak.github.io/genproc/reference/summary.genproc_result.md)

## Examples

``` r
r0 <- genproc(
  f = function(x) if (x %% 2 == 0) stop("even") else x,
  mask = data.frame(x = 1:6)
)
# 3 cases failed (the even ones). After fixing f, retry only those:
if (FALSE) { # \dontrun{
  r1 <- rerun_failed(r0, f = function(x) abs(x))
  r1$log
} # }
```
