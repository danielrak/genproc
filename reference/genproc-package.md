# genproc: robust, logged and reproducible iteration at organizational scale

The `genproc` package wraps classical iteration constructs (`for`,
[`base::lapply()`](https://rdrr.io/r/base/lapply.html),
[`purrr::pmap()`](https://purrr.tidyverse.org/reference/pmap.html), ...)
with orthogonal execution layers so that one-off scripts can be turned
into production-grade procedures without restructuring the user's code.

## Details

Two layers are always active (they cannot be disabled):

- *Logged*: each case produces a structured log row with the real
  traceback (captured through
  [`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)) and
  timing.

- *Reproducibility*: each run records the R version, loaded package
  versions, execution environment, the exact mask used, and hashes of
  the file inputs referenced by the mask, so that silent
  non-reproducibility between runs can be flagged to the user.

Further layers are planned (parallel, non-blocking, monitored, error
replay). They will be composable with the default layers and opt-in.

This package has no Shiny dependency and is intended to be reusable from
a future companion Shiny package.

## See also

Useful links:

- <https://github.com/danielrak/genproc>

- Report bugs at <https://github.com/danielrak/genproc/issues>

## Author

**Maintainer**: Daniel Rakotomalala <rakdanielh@gmail.com>
