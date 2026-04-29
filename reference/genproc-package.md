# genproc: robust, logged and reproducible iteration at organizational scale

The `genproc` package wraps classical iteration constructs (`for`,
[`base::lapply()`](https://rdrr.io/r/base/lapply.html),
[`purrr::pmap()`](https://purrr.tidyverse.org/reference/pmap.html), ...)
with orthogonal execution layers so that one-off scripts can be turned
into production-grade procedures without restructuring the user's code.

## Details

Two layers are always active and cannot be disabled:

- *Logged*: each case produces a structured log row with the real
  traceback (captured via
  [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)) and
  per-case timing.

- *Reproducibility*: each run records the R version, loaded package
  versions, execution environment, the exact mask used, and a stat-based
  fingerprint (size + modification time) of every input file referenced
  by the mask. Silent drift of an upstream file between two runs can
  then be detected via
  [`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md).

Two optional, composable layers can be enabled per call:

- *Parallel*: dispatch cases to workers via the
  [future](https://future.futureverse.org/reference/future.html)
  ecosystem and
  [`future.apply::future_lapply()`](https://future.apply.futureverse.org/reference/future_lapply.html).
  Configured through
  [`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md).

- *Non-blocking*: return a `genproc_result` skeleton immediately while
  the run continues in a background future. Poll with
  [`status()`](https://danielrak.github.io/genproc/reference/status.md),
  block with
  [`await()`](https://danielrak.github.io/genproc/reference/await.md).
  Configured through
  [`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md).

Further layers are on the roadmap: monitored progress, error replay,
content-hash input fingerprinting, content-based case identifiers. They
will be composable with the default layers and opt-in.

This package has no Shiny dependency and is designed to be consumable by
a future companion Shiny package.

## See also

Useful links:

- <https://danielrak.github.io/genproc/>

- <https://github.com/danielrak/genproc>

- Report bugs at <https://github.com/danielrak/genproc/issues>

## Author

**Maintainer**: Daniel Rakotomalala <rakdanielh@gmail.com>
