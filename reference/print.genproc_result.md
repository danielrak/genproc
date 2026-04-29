# Print a genproc result

Displays a structured summary of the run: status, timestamp, execution
mode, case counts, total duration, and an actionable hint when relevant.

## Usage

``` r
# S3 method for class 'genproc_result'
print(x, ...)
```

## Arguments

- x:

  A `genproc_result` object.

- ...:

  Ignored (present for S3 method consistency).

## Value

`x`, invisibly.

## Details

For non-blocking results, the status is queried *live* from the attached
future via
[`status()`](https://danielrak.github.io/genproc/reference/status.md)
rather than read from the stored field. Repeated `print(x)` calls
therefore reflect the actual progress of the background run.
[`status()`](https://danielrak.github.io/genproc/reference/status.md)
distinguishes `"done"` (the future resolved successfully) from `"error"`
(the wrapper future itself crashed). Numeric fields stay `(pending)`
until
[`await()`](https://danielrak.github.io/genproc/reference/await.md) is
called to materialize the result.

When the parallel layer was used and startup overhead clearly dominated
the run, the print method emits a `Note` hinting at the issue — a
pattern that often surprises users on small workloads. Two metrics
depending on whether `workers` is known: parallel efficiency
(`(cumulative / workers) / wall`) below 50% when `workers` is supplied,
or `wall > cumulative * 1.2` in power-user mode (workers unknown). Both
require `wall > 0.5s` to avoid noise on very short runs.
