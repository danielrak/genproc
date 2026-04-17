# Specify a parallel execution strategy for genproc()

Returns a configuration object to pass as the `parallel` argument of
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).
The object describes *how* to parallelize; the actual execution is
carried out by
[`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html)
on top of the backend selected by
[`future::plan()`](https://future.futureverse.org/reference/plan.html).

## Usage

``` r
parallel_spec(
  workers = NULL,
  strategy = NULL,
  chunk_size = NULL,
  seed = TRUE,
  packages = NULL,
  globals = TRUE
)
```

## Arguments

- workers:

  Integer \>= 1, or `NULL`. Number of workers to use. Ignored when
  `strategy = "sequential"`. If `NULL`, the current
  [`future::plan()`](https://future.futureverse.org/reference/plan.html)
  decides.

- strategy:

  Character, or `NULL`. One of `"sequential"`, `"multisession"`,
  `"multicore"`, `"cluster"`. If `NULL` (default), the current
  [`future::plan()`](https://future.futureverse.org/reference/plan.html)
  is used unchanged. If specified, genproc temporarily sets the
  corresponding plan for the run and restores the previous plan on exit.

- chunk_size:

  Integer \>= 1, or `NULL`. Number of iteration cases bundled per
  future. Larger values reduce scheduling overhead at the cost of
  load-balance granularity. `NULL` delegates to `future.apply`'s default
  heuristic.

- seed:

  Controls reproducible random-number generation across workers. Passed
  to
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html)'s
  `future.seed` argument. Default `TRUE` derives independent
  L'Ecuyer-CMRG streams from a random master seed. A single integer
  fixes the master seed. `FALSE` disables reproducible RNG and is not
  recommended unless the user function is known to be RNG-free.

- packages:

  Character vector, or `NULL`. Extra packages to attach on each worker
  before running the user function. genproc itself is attached
  automatically for every strategy other than `"sequential"`.

- globals:

  Logical or character. Forwarded to
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html)'s
  `future.globals`. Default `TRUE` enables automatic detection, which is
  correct in almost all cases. Set to a character vector only to
  override detection.

## Value

A list of class `"genproc_parallel_spec"` with the validated, normalized
fields.

## Choosing a strategy

- `"sequential"`: runs in the current process, no workers. Exercises the
  parallel code path without the overhead; useful for deterministic
  testing.

- `"multisession"`: portable (works on Windows), launches R subprocesses
  via parallelly. The default recommendation for most workloads.

- `"multicore"`: forks the current process (Unix/macOS only, **not
  available on Windows** and not reliable inside RStudio). Faster
  startup than multisession but loses portability.

- `"cluster"`: explicit cluster of workers, possibly on other machines.
  For large-scale batch execution.

For most users, leaving `strategy = NULL` and calling
[`future::plan()`](https://future.futureverse.org/reference/plan.html)
once at the top of the session is the cleanest setup.

## RNG reproducibility

With `seed = TRUE`, each case receives an independent L'Ecuyer-CMRG
stream derived from a random master seed. Same master seed -\> identical
results regardless of worker count or chunking. To pin the master seed,
pass an integer (`seed = 42L`).

## Examples

``` r
# Use whatever plan the caller has set
spec <- parallel_spec()

# One-off parallel call with 4 workers, reproducible RNG
spec <- parallel_spec(workers = 4, strategy = "multisession",
                      seed = 42L)

# Exercise the parallel code path deterministically in a test
spec <- parallel_spec(strategy = "sequential")
```
