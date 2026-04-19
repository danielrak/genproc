# Print a genproc result

Displays a concise summary of the run: number of cases, success rate,
total duration, and status. Handles non-blocking skeletons (status
`"running"`) where counts and duration are not yet available.

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
