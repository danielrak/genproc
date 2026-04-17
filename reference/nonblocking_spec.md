# Specify a non-blocking execution strategy for genproc()

Returns a configuration object to pass as the `nonblocking` argument of
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).
When supplied,
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
returns immediately with a `genproc_result` of status `"running"` while
the actual work continues in a background future. Use
[`status()`](https://danielrak.github.io/genproc/reference/status.md) to
poll the state and
[`await()`](https://danielrak.github.io/genproc/reference/await.md) to
block until completion.

## Usage

``` r
nonblocking_spec(strategy = "multisession", packages = NULL, globals = TRUE)
```

## Arguments

- strategy:

  Character, or `NULL`. One of `"sequential"`, `"multisession"`,
  `"multicore"`, `"cluster"`. Default `"multisession"`. Unlike
  [`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md),
  the default is not `NULL`: a function named "non-blocking" must not
  silently block because the current
  [`future::plan()`](https://future.futureverse.org/reference/plan.html)
  is sequential. Pass `strategy = NULL` explicitly to defer to the
  caller's plan. `"sequential"` is accepted mainly for deterministic
  testing — it exercises the code path but does *not* actually free the
  console.

- packages:

  Character vector, or `NULL`. Extra packages to attach on the
  background worker before running. genproc itself is attached
  automatically for every strategy other than `"sequential"`.

- globals:

  Logical or character. Forwarded to
  [`future::future()`](https://future.futureverse.org/reference/future.html)'s
  `globals` argument. Default `TRUE` enables automatic detection.

## Value

A list of class `"genproc_nonblocking_spec"` with the validated,
normalized fields.

## Composition with parallel_spec()

`nonblocking_spec()` and
[`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md)
are orthogonal and can be combined. The non-blocking layer launches
*one* outer future; inside it, the parallel layer dispatches cases via
future.apply. With both strategies set to `"multisession"`, future
resolves the inner layer as `"sequential"` by default (see
[`future::plan()`](https://future.futureverse.org/reference/plan.html)
nesting rules) unless the caller installs an explicit nested plan via
`future::plan(list(...))`.

## See also

[`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md),
[`status()`](https://danielrak.github.io/genproc/reference/status.md),
[`await()`](https://danielrak.github.io/genproc/reference/await.md)

## Examples

``` r
# Launch in the background, keep the console
if (FALSE) { # \dontrun{
  spec <- nonblocking_spec()
  job <- genproc(f = slow_fn, mask = mask, nonblocking = spec)
  status(job)           # "running"
  job <- await(job)     # blocks until done
  job$log
} # }

# Deterministic test: exercise the code path without real async
spec <- nonblocking_spec(strategy = "sequential")
```
