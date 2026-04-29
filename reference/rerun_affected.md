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
if (FALSE) { # \dontrun{
  r0 <- genproc(my_fn, my_mask)
  # ... time passes, some upstream files change ...
  r1 <- genproc(my_fn, my_mask)

  d <- diff_inputs(r0, r1)
  # d$cases_affected lists the case_ids whose inputs drifted.

  refreshed <- rerun_affected(r0, d, f = my_fn)
  refreshed$log
} # }
```
