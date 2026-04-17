# Query the status of a genproc run without blocking

`status()` is a non-blocking S3 generic. On a `genproc_result`, it
returns `"running"` while a background future is unresolved, and
`"done"` once it has resolved (or if the object is already
synchronous-done). It does *not* materialize the result — use
[`await()`](https://danielrak.github.io/genproc/reference/await.md) for
that. If you want to know whether the wrapper future itself crashed, you
must call
[`await()`](https://danielrak.github.io/genproc/reference/await.md).

## Usage

``` r
status(x, ...)

# S3 method for class 'genproc_result'
status(x, ...)
```

## Arguments

- x:

  An object. Methods exist for `genproc_result`.

- ...:

  Unused, for future extensions.

## Value

A single character string.

## See also

[`await()`](https://danielrak.github.io/genproc/reference/await.md),
[`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
