
<!-- README.md is generated from README.Rmd. Please edit that file -->

# genproc

<!-- badges: start -->

[![R-CMD-check](https://github.com/danielrak/genproc/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/danielrak/genproc/actions/workflows/R-CMD-check.yaml)
[![Codecov test
coverage](https://codecov.io/gh/danielrak/genproc/graph/badge.svg)](https://app.codecov.io/gh/danielrak/genproc)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
<!-- badges: end -->

`genproc` turns one-off iterative R procedures (`for`, `lapply()`,
`purrr::pmap()`, …) into production-grade workflows by wrapping them
with orthogonal, composable execution layers. The goal is to make the
transition from *“a script that works on one case”* to *“a system that
runs reliably on many cases”* an architectural step, not an improvised
rewrite.

Two layers are always active and cannot be disabled:

- **Logged** — each case produces a structured log row with the real
  traceback (captured via `withCallingHandlers()`) and per-case timing.
- **Reproducibility** — each run records the R version, loaded package
  versions, execution environment, the exact iteration mask, and the
  spec of any optional layer used, so that two runs can be compared and
  any parameter drift is auditable.

Two optional layers can be composed with the defaults, at the caller’s
choice:

- **Parallel** execution via the `future` ecosystem
  (`future.apply::future_lapply()`).
- **Non-blocking** execution: `genproc()` returns immediately with a
  `genproc_result` of status `"running"` while the run continues in a
  background future. Poll with `status()`, block with `await()`.

`genproc` has **zero Shiny dependency**. A companion package
(`genprocShiny`) will later build a UI on top of these functions.

## Installation

``` r
# install.packages("remotes")
remotes::install_github("danielrak/genproc")
```

## A minimal example

A toy file-conversion task: read a few CSVs from one directory, save
them as RDS into another. One case per file.

``` r
library(genproc)

# Synthetic workspace
src_dir <- file.path(tempdir(), "src")
dst_dir <- file.path(tempdir(), "dst")
dir.create(src_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(dst_dir, showWarnings = FALSE, recursive = TRUE)

write.csv(head(iris),       file.path(src_dir, "a.csv"), row.names = FALSE)
write.csv(head(mtcars),     file.path(src_dir, "b.csv"), row.names = FALSE)
write.csv(head(airquality), file.path(src_dir, "c.csv"), row.names = FALSE)

# Per-case function
convert <- function(src_dir, src_file, dst_dir, dst_file) {
  df <- read.csv(file.path(src_dir, src_file))
  saveRDS(df, file.path(dst_dir, dst_file))
}

# Iteration mask: one row per conversion
mask <- data.frame(
  src_dir  = src_dir,
  src_file = c("a.csv", "b.csv", "c.csv"),
  dst_dir  = dst_dir,
  dst_file = c("a.rds", "b.rds", "c.rds"),
  stringsAsFactors = FALSE
)

result <- genproc(convert, mask)
```

Every run returns a `genproc_result`. The log contains one row per case,
with stable `case_id`, the parameter values, `success`, `error_message`,
`traceback`, and `duration_secs`:

``` r
result$log[, c("case_id", "src_file", "dst_file",
               "success", "duration_secs")]
#>     case_id src_file dst_file success duration_secs
#> 1 case_0001    a.csv    a.rds    TRUE             0
#> 2 case_0002    b.csv    b.rds    TRUE             0
#> 3 case_0003    c.csv    c.rds    TRUE             0
```

If a case fails, the run continues — the error is captured, not thrown.
Here we delete one source file on purpose before a second run:

``` r
file.remove(file.path(src_dir, "b.csv"))
#> [1] TRUE

result2 <- genproc(convert, mask)
#> Warning in file(file, "rt"): impossible d'ouvrir le fichier
#> 'C:\Users\rheri\AppData\Local\Temp\RtmpegrrE4/src/b.csv' : No such file or
#> directory
result2$log[result2$log$success == FALSE,
            c("case_id", "src_file", "error_message")]
#>     case_id src_file                    error_message
#> 2 case_0002    b.csv impossible d'ouvrir la connexion
result2$n_success
#> [1] 2
result2$n_error
#> [1] 1
```

The traceback column holds the real R call stack of the failing case
(filtered for the `tryCatch`/`withCallingHandlers` machinery), so
debugging a failed case reads like a normal R error.

## The reproducibility snapshot

`result$reproducibility` is a plain list recording the R version, OS,
timezone, loaded package versions, the exact mask used, the specs of any
optional layer, and a fingerprint of every input file referenced by the
mask. This snapshot lives inside the result — no side file to keep in
sync:

``` r
str(result$reproducibility, max.level = 1)
#> List of 11
#>  $ timestamp    : POSIXct[1:1], format: "2026-04-28 19:37:59"
#>  $ r_version    : chr "R version 4.5.1 (2025-06-13 ucrt)"
#>  $ platform     : chr "x86_64-w64-mingw32"
#>  $ os           : chr "Windows 10 x64"
#>  $ locale       : chr "LC_COLLATE=French_France.utf8;LC_CTYPE=French_France.utf8;LC_MONETARY=French_France.utf8;LC_NUMERIC=C;LC_TIME=F"| __truncated__
#>  $ timezone     : chr "Europe/Paris"
#>  $ packages     : Named chr [1:22] "0.0.0.9000" "4.5.1" "1.2.0" "3.6.5" ...
#>   ..- attr(*, "names")= chr [1:22] "genproc" "compiler" "fastmap" "cli" ...
#>  $ mask_snapshot:'data.frame':   3 obs. of  4 variables:
#>  $ parallel     : NULL
#>  $ nonblocking  : NULL
#>  $ inputs       :List of 3
```

## Detecting silent input drift

`result$reproducibility$inputs` records the size and mtime of every
input file the mask refers to. The intent is to flag the most common
reproducibility failure: re-running the same code on the same paths
after an upstream file has been silently rewritten.

genproc detects input columns automatically: any character column of the
mask whose values are existing files is treated as such. Pass
`track_inputs = FALSE` to skip the capture, or override the heuristic
with `input_cols = c(...)` (force) or `skip_input_cols = c(...)`
(exclude).

``` r
mask_paths <- data.frame(
  csv_in = file.path(src_dir, c("a.csv", "b.csv", "c.csv")),
  stringsAsFactors = FALSE
)
do_one <- function(csv_in) nrow(read.csv(csv_in))

run0 <- genproc(do_one, mask_paths)
#> Warning in file(file, "rt"): impossible d'ouvrir le fichier
#> 'C:\Users\rheri\AppData\Local\Temp\RtmpegrrE4/src/b.csv' : No such file or
#> directory
run0$reproducibility$inputs$files
#> [1] path  size  mtime
#> <0 lignes> (ou 'row.names' de longueur nulle)
```

`diff_inputs()` compares two runs and tells you which referenced files
have changed since the first one:

``` r
# Rewrite a.csv with strictly more content (size changes)
write.csv(iris, file.path(src_dir, "a.csv"), row.names = FALSE)

run1 <- genproc(do_one, mask_paths)
#> Warning in file(file, "rt"): impossible d'ouvrir le fichier
#> 'C:\Users\rheri\AppData\Local\Temp\RtmpegrrE4/src/b.csv' : No such file or
#> directory
diff_inputs(run0, run1)
#> genproc input diff (method: stat)
#>   Changed:   0
#>   Unchanged: 0
#>   Removed:   0
#>   Added:     0
```

The default method is `"stat"` (size + mtime). It detects every
legitimate modification at near-zero cost; a content-hash variant is on
the roadmap for stronger guarantees on adversarial workloads.

## Parallel execution

Dispatch cases across workers by passing a `parallel_spec()`:

``` r
# Four workers, a temporary multisession plan, restored on exit
result <- genproc(
  convert, mask,
  parallel = parallel_spec(workers = 4)
)
```

The two mandatory layers remain active in parallel mode. Case order is
preserved in the log regardless of the order in which workers return.
Under the hood, `parallel_spec()` builds a configuration object consumed
by `future.apply::future_lapply()`.

If you manage `future::plan()` yourself (recommended across several
calls to amortize worker startup), pass `parallel_spec()` without a
strategy and your current plan is used unchanged.

## Non-blocking execution

Return immediately, keep the console, collect later:

``` r
job <- genproc(
  convert, mask,
  nonblocking = nonblocking_spec()
)

status(job)        # "running" or "done"
job <- await(job)  # blocks until resolution
job$log
```

`nonblocking_spec()` can be composed with `parallel_spec()` — the
non-blocking wrapper envelops the parallel dispatch:

``` r
job <- genproc(
  convert, mask,
  parallel    = parallel_spec(workers = 4),
  nonblocking = nonblocking_spec()
)
```

## Status

Early development. The public API is not stable yet. The package is not
on CRAN.

## Learn more

See `vignette("genproc")` for a deep dive: anatomy of the log and
reproducibility snapshot, per-case error handling, composition patterns,
and roadmap.

## License

MIT. See [LICENSE.md](LICENSE.md).
