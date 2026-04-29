# Query the status of a genproc run without blocking

`status()` is a non-blocking S3 generic. On a `genproc_result`, it
returns one of:

- `"running"` — the underlying future is not yet resolved.

- `"done"` — the future has resolved successfully (the result is ready
  to be collected via
  [`await()`](https://danielrak.github.io/genproc/reference/await.md)).

- `"error"` — the wrapper future itself crashed. Call
  [`await()`](https://danielrak.github.io/genproc/reference/await.md) to
  retrieve the error message.

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

A single character string: `"running"`, `"done"`, or `"error"`.

## Details

For a synchronous (non-`nonblocking`) result, `status()` simply returns
`result$status` (`"done"` or `"error"`).

`status()` peeks at the resolved future via
[`future::value()`](https://future.futureverse.org/reference/value.html)
inside a `tryCatch`. Because `value()` consumes the future, the peek
result is cached in a shared environment so that a subsequent
[`await()`](https://danielrak.github.io/genproc/reference/await.md) does
not re-materialize it.

## See also

[`await()`](https://danielrak.github.io/genproc/reference/await.md),
[`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
