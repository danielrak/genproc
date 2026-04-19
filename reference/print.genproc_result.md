# Print a genproc result

Displays a concise summary of the run: number of cases, success rate,
total duration, and status.

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
future (via
[`status()`](https://danielrak.github.io/genproc/reference/status.md))
rather than read from the stored field, which is frozen at the moment
the skeleton is created. This way, repeated `print(x)` calls reflect the
actual progress of the background run. Numeric fields stay `(pending)`
until
[`await()`](https://danielrak.github.io/genproc/reference/await.md) is
called to materialize the result.
