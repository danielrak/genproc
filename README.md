
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
with orthogonal, composable execution layers: **Logged** and
**Reproducibility** are always active; **Parallel**, **Non-blocking**,
and **Monitoring** compose on top. The goal is to make the transition
from *“a script that works on one case”* to *“a system that runs
reliably on many cases”* an architectural step, not an improvised
rewrite.

The two always-active layers:

- **Logged** — each case produces a structured log row with the real
  traceback (captured via `withCallingHandlers()`) and per-case timing.
- **Reproducibility** — each run records the R version, loaded package
  versions, execution environment, the exact iteration mask, the spec of
  any optional layer used, and a stat-based fingerprint of every input
  file referenced by the mask, so that two runs can be compared and any
  silent input drift detected.

The three optional layers:

- **Parallel** execution via the `future` ecosystem
  (`future.apply::future_lapply()`).
- **Non-blocking** execution: `genproc()` returns immediately with a
  `genproc_result` of status `"running"` while the run continues in a
  background future. Poll with `status()`, block with `await()`.
- **Monitoring** via `progressr` — opt-in progress reporting that emits
  one progression signal per completed case in sequential and parallel
  modes.

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

Every run returns a `genproc_result` — a structured list with a stable
shape across runs:

``` r
result
#> genproc result
#>   Status   : done 
#>   Started  : 2026-05-02 21:50:03 CEST 
#>   Mode     : sequential 
#>   Cases    : 3 ( 3 ok, 0 error )
#>   Duration : 0.06 secs
```

The `log` data.frame holds one row per case, with `case_id`, the mask
parameter values (`src_dir`, `src_file`, `dst_dir`, `dst_file` here),
then `success`, `error_message`, `traceback`, and `duration_secs`. Below
we display a subset of those columns for readability — `error_message`
and `traceback` are `NA` on this happy path:

``` r
result$log[, c("case_id", "src_file", "dst_file",
               "success", "duration_secs")]
#>     case_id src_file dst_file success duration_secs
#> 1 case_0001    a.csv    a.rds    TRUE          0.03
#> 2 case_0002    b.csv    b.rds    TRUE          0.01
#> 3 case_0003    c.csv    c.rds    TRUE          0.00
```

If a case fails, the run continues — the error is captured, not thrown.
Below we point one row of the mask to a file that does not exist;
`b.csv` itself is left untouched on disk so subsequent sections of this
README can still reference it:

``` r
mask_with_missing <- mask
mask_with_missing$src_file[2] <- "does_not_exist.csv"

result2 <- genproc(convert, mask_with_missing)
#> Warning in file(file, "rt"): cannot open file
#> 'C:\Users\rheri\AppData\Local\Temp\RtmpeQ8Oil/src/does_not_exist.csv': No such
#> file or directory
errors(result2)[, c("case_id", "src_file", "error_message")]
#>     case_id           src_file              error_message
#> 2 case_0002 does_not_exist.csv cannot open the connection
result2$n_success
#> [1] 2
result2$n_error
#> [1] 1
```

The traceback column holds the real R call stack of the failing case
(filtered for the `tryCatch`/`withCallingHandlers` machinery), so
debugging a failed case reads like a normal R error.

## Inspect and act on a result

Three helpers digest a result without touching `result$log` directly:

``` r
errors(result2)        # data.frame of failed cases only
#>     case_id                                                src_dir
#> 2 case_0002 C:\\Users\\rheri\\AppData\\Local\\Temp\\RtmpeQ8Oil/src
#>             src_file                                                dst_dir
#> 2 does_not_exist.csv C:\\Users\\rheri\\AppData\\Local\\Temp\\RtmpeQ8Oil/dst
#>   dst_file success              error_message
#> 2    b.rds   FALSE cannot open the connection
#>                                                                                                                                                                                                                    traceback
#> 2 1. process_file(text, output)\n2. read.csv(file.path(src_dir, src_file))\n3. read.table(file = file, header = header, sep = sep, quote = quote, dec = dec, fill = fill, comment.char = comment.ch ...\n4. file(file, "rt")
#>   duration_secs
#> 2             0
summary(result2)       # printable digest: status, success rate,
#> genproc result summary
#>   Status     : done
#>   Cases      : 3 (2 ok, 1 error)
#>   Success    : 67%
#>   Total time : 0.00s
#>   Per case   : mean 0.000s, max 0.000s (slowest: case_0001)
#> 
#> Top errors:
#>     1x  cannot open the connection
                       # duration stats, top recurring errors
```

Two more close the loop by re-running a targeted subset:

``` r
rerun_failed(result2, convert)            # only failed cases
rerun_affected(result0, diff, convert)    # only cases referenced
                                          # by changed inputs (see
                                          # next section)
```

## The reproducibility snapshot

`result$reproducibility` is a plain list recording the R version, OS,
timezone, loaded package versions, the exact mask used, the specs of any
optional layer, and a fingerprint of every input file referenced by the
mask. This snapshot lives inside the result — no side file to keep in
sync:

``` r
str(result$reproducibility, max.level = 1)
#> List of 11
#>  $ timestamp    : POSIXct[1:1], format: "2026-05-02 21:50:03"
#>  $ r_version    : chr "R version 4.5.1 (2025-06-13 ucrt)"
#>  $ platform     : chr "x86_64-w64-mingw32"
#>  $ os           : chr "Windows 10 x64"
#>  $ locale       : chr "LC_COLLATE=French_France.utf8;LC_CTYPE=French_France.utf8;LC_MONETARY=French_France.utf8;LC_NUMERIC=C;LC_TIME=F"| __truncated__
#>  $ timezone     : chr "Europe/Paris"
#>  $ packages     : Named chr [1:22] "0.2.0" "4.5.1" "1.2.0" "3.6.5" ...
#>   ..- attr(*, "names")= chr [1:22] "genproc" "compiler" "fastmap" "cli" ...
#>  $ mask_snapshot:'data.frame':   3 obs. of  4 variables:
#>  $ parallel     : NULL
#>  $ nonblocking  : NULL
#>  $ inputs       :List of 3
```

A taste of what is captured (first few package versions):

``` r
head(result$reproducibility$packages, 5)
#>  genproc compiler  fastmap      cli    tools 
#>  "0.2.0"  "4.5.1"  "1.2.0"  "3.6.5"  "4.5.1"
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
run0$reproducibility$inputs$files
#>                                                     path size
#> 1 C:/Users/rheri/AppData/Local/Temp/RtmpeQ8Oil/src/a.csv  221
#> 2 C:/Users/rheri/AppData/Local/Temp/RtmpeQ8Oil/src/b.csv  303
#> 3 C:/Users/rheri/AppData/Local/Temp/RtmpeQ8Oil/src/c.csv  161
#>                 mtime
#> 1 2026-05-02 21:50:03
#> 2 2026-05-02 21:50:03
#> 3 2026-05-02 21:50:03
```

`diff_inputs()` compares two runs and tells you which referenced files
have changed since the first one:

``` r
# Rewrite a.csv with strictly more content (size changes)
write.csv(iris, file.path(src_dir, "a.csv"), row.names = FALSE)

run1 <- genproc(do_one, mask_paths)
diff_inputs(run0, run1)
#> genproc input diff (method: stat)
#>   Changed:   1
#>   Unchanged: 2
#>   Removed:   0
#>   Added:     0
#>   Cases affected: 1
#> 
#> Changed files:
#>   C:/Users/rheri/AppData/Local/Temp/RtmpeQ8Oil/src/a.csv
#>       size:  221 B -> 4.1 KB
#>       mtime: 2026-05-02 21:50:03 -> 2026-05-02 21:50:03
#> 
#> Cases affected (use rerun_affected() to re-run):
#>   case_0001
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

## Progress monitoring

Wrap a run in `progressr::with_progress()` to opt in to per-case
progress reporting:

``` r
library(progressr)

with_progress({
  result <- genproc(convert, mask)
})
```

Pick a renderer once per session with `progressr::handlers()` (default
`"txtprogressbar"`, alternatives include `"progress"` and `"cli"`).
Without `with_progress()`, or without `progressr` installed, the
integration is a complete no-op. Live monitoring of non-blocking runs is
on the roadmap.

## Status

Lifecycle: **experimental**. The five execution layers (logged,
reproducibility, parallel, non-blocking, monitoring) and the
`genproc_result` contract are committed to forward compatibility across
the 0.x series — existing fields are guaranteed not to be removed or
renamed. New fields and new optional layers may be added.

The 0.2.0 release is the first public submission and is not yet on CRAN.
Install from GitHub for now (see above).

## Learn more

See `vignette("genproc")` for a deep dive: anatomy of the log and
reproducibility snapshot, per-case error handling, composition patterns,
and roadmap.

## License

MIT. See
[LICENSE.md](https://github.com/danielrak/genproc/blob/master/LICENSE.md).
