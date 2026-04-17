# genproc: deep dive

The `README` introduces the four layers on a minimal example. This
vignette walks through the pieces a user needs once they start depending
on `genproc` for real work: the shape of the result, how errors are
reported, how the optional layers compose, and what the current edges
are.

``` r
library(genproc)
```

## A small working example

The same synthetic file-conversion task as in the README — one row per
file, `convert()` is the per-case function.

``` r
src_dir <- file.path(tempdir(), "genproc-vignette-src")
dst_dir <- file.path(tempdir(), "genproc-vignette-dst")
dir.create(src_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(dst_dir, showWarnings = FALSE, recursive = TRUE)

write.csv(head(iris),       file.path(src_dir, "a.csv"), row.names = FALSE)
write.csv(head(mtcars),     file.path(src_dir, "b.csv"), row.names = FALSE)
write.csv(head(airquality), file.path(src_dir, "c.csv"), row.names = FALSE)

convert <- function(src_dir, src_file, dst_dir, dst_file) {
  df <- read.csv(file.path(src_dir, src_file))
  saveRDS(df, file.path(dst_dir, dst_file))
}

mask <- data.frame(
  src_dir  = src_dir,
  src_file = c("a.csv", "b.csv", "c.csv"),
  dst_dir  = dst_dir,
  dst_file = c("a.rds", "b.rds", "c.rds"),
  stringsAsFactors = FALSE
)

result <- genproc(convert, mask)
```

## Anatomy of `genproc_result`

`result` is an S3 list with a stable, documented set of fields:

``` r
class(result)
#> [1] "genproc_result"
names(result)
#> [1] "log"                 "reproducibility"     "n_success"          
#> [4] "n_error"             "duration_total_secs" "status"
```

- `log`: one row per case. Columns, in order: `case_id`, the mask
  parameter values (in the order they appear in the mask), then
  `success`, `error_message`, `traceback`, `duration_secs`.
- `reproducibility`: the environment snapshot captured at run start (see
  below).
- `n_success`, `n_error`: summary counts.
- `duration_total_secs`: total wall-clock time.
- `status`: `"done"` for a synchronous run, `"running"` or `"error"` for
  a non-blocking run before
  [`await()`](https://danielrak.github.io/genproc/reference/await.md).

These fields are guaranteed stable across minor versions; new fields may
be added (e.g. `worker_id` for parallel runs), but existing ones will
never be removed or renamed.

### The log

Column order is designed for a human scanning a run:

``` r
result$log
#>     case_id                              src_dir src_file
#> 1 case_0001 /tmp/Rtmpvo2zyz/genproc-vignette-src    a.csv
#> 2 case_0002 /tmp/Rtmpvo2zyz/genproc-vignette-src    b.csv
#> 3 case_0003 /tmp/Rtmpvo2zyz/genproc-vignette-src    c.csv
#>                                dst_dir dst_file success error_message traceback
#> 1 /tmp/Rtmpvo2zyz/genproc-vignette-dst    a.rds    TRUE          <NA>      <NA>
#> 2 /tmp/Rtmpvo2zyz/genproc-vignette-dst    b.rds    TRUE          <NA>      <NA>
#> 3 /tmp/Rtmpvo2zyz/genproc-vignette-dst    c.rds    TRUE          <NA>      <NA>
#>   duration_secs
#> 1         0.001
#> 2         0.001
#> 3         0.001
```

`case_id` is stable and index-based (`case_0001`, `case_0002`, …) for
now. A content-based variant is on the roadmap, for use cases where rows
of the mask can be reordered between runs.

### The reproducibility snapshot

``` r
str(result$reproducibility, max.level = 1)
#> List of 10
#>  $ timestamp    : POSIXct[1:1], format: "2026-04-17 19:47:11"
#>  $ r_version    : chr "R version 4.5.3 (2026-03-11)"
#>  $ platform     : chr "x86_64-pc-linux-gnu"
#>  $ os           : chr "Linux 6.17.0-1010-azure"
#>  $ locale       : chr "LC_CTYPE=C.UTF-8;LC_NUMERIC=C;LC_TIME=C.UTF-8;LC_COLLATE=C.UTF-8;LC_MONETARY=C.UTF-8;LC_MESSAGES=C.UTF-8;LC_PAP"| __truncated__
#>  $ timezone     : chr "UTC"
#>  $ packages     : Named chr [1:33] "0.0.0.9000" "0.6.39" "1.4.3" "2.6.1" ...
#>   ..- attr(*, "names")= chr [1:33] "genproc" "digest" "desc" "R6" ...
#>  $ mask_snapshot:'data.frame':   3 obs. of  4 variables:
#>  $ parallel     : NULL
#>  $ nonblocking  : NULL
```

- `timestamp`: `POSIXct`, start time of the run.
- `r_version`, `platform`, `os`, `locale`, `timezone`: system info.
- `packages`: named character vector of package -\> version, for every
  package attached or loaded via namespace at run start.
- `mask_snapshot`: the exact mask used (not a copy of a reference — the
  value).
- `parallel`: `NULL` for a sequential run, or a plain list mirroring the
  [`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md)
  used. Dropped class to make the snapshot portable to serialization
  formats.
- `nonblocking`: same pattern, for
  [`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md).

The snapshot lives inside the result. You can compare two results by
comparing their `$reproducibility` slots directly.

## How errors are reported

A case that throws does **not** stop the run. Here we delete a source
file between two runs:

``` r
file.remove(file.path(src_dir, "b.csv"))
#> [1] TRUE
result_broken <- genproc(convert, mask)
#> Warning in file(file, "rt"): cannot open file
#> '/tmp/Rtmpvo2zyz/genproc-vignette-src/b.csv': No such file or directory

result_broken$n_success
#> [1] 2
result_broken$n_error
#> [1] 1
```

The failing row carries the error message and a filtered traceback:

``` r
bad <- result_broken$log[!result_broken$log$success, ]
bad$error_message
#> [1] "cannot open the connection"
cat(bad$traceback[1], "\n")
#> 1. read.csv(file.path(src_dir, src_file))
#> 2. read.table(file = file, header = header, sep = sep, quote = quote, dec = dec, fill = fill, comment.char = comment.ch ...
#> 3. file(file, "rt")
```

The traceback is captured via
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) at the
moment the error is thrown — it is the real R call stack, not a string
pulled out of
[`conditionMessage()`](https://rdrr.io/r/base/conditions.html). The
internal [`tryCatch()`](https://rdrr.io/r/base/conditions.html) and
[`withCallingHandlers()`](https://rdrr.io/r/base/conditions.html) frames
are filtered out so the trace reads like a normal R error.

Restore the file for subsequent sections:

``` r
write.csv(head(mtcars), file.path(src_dir, "b.csv"), row.names = FALSE)
```

## Parameter renaming with `f_mapping`

If the function you already have uses parameter names that don’t match
your mask’s column names, `f_mapping` renames them in place without
touching the source:

``` r
# `f` uses generic names; the mask uses domain names.
f <- function(input_dir, input_file, output_dir, output_file) {
  df <- read.csv(file.path(input_dir, input_file))
  saveRDS(df, file.path(output_dir, output_file))
}

genproc(
  f = f,
  mask = mask,
  f_mapping = c(
    "input_dir"   = "src_dir",
    "input_file"  = "src_file",
    "output_dir"  = "dst_dir",
    "output_file" = "dst_file"
  )
)
```

## Parallel execution in depth

[`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md)
records intent only; the actual workers are started lazily by `future`
when the plan is resolved.

### Power-user pattern: manage the plan yourself

Across many
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
calls in the same session, installing the plan once amortizes worker
startup:

``` r
future::plan(future::multisession, workers = 6)

result_1 <- genproc(convert, mask, parallel = parallel_spec())
result_2 <- genproc(convert, mask, parallel = parallel_spec())
# reuses the same workers
```

### One-off pattern: let genproc install the plan

When `workers` is passed without `strategy`,
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
auto-defaults to `multisession` for that single call and restores the
previous plan on exit. This avoids the silent trap of `workers = N`
being ignored because the current plan is `sequential`:

``` r
genproc(convert, mask, parallel = parallel_spec(workers = 4))
```

### Amortization threshold

`multisession` costs roughly 1–3 seconds per worker at first use. Below
~10 seconds of real work, a parallel run can be slower than a sequential
one. Don’t read a single short benchmark as evidence of a bug: run at
workload size.

### RNG reproducibility

`parallel_spec(seed = TRUE)` (the default) draws independent
L’Ecuyer-CMRG streams from a random master seed. Identical master seed —
identical per-case RNG state regardless of worker count or chunking. To
pin the master, pass an integer: `parallel_spec(seed = 42L)`.

## Non-blocking execution in depth

``` r
job <- genproc(convert, mask, nonblocking = nonblocking_spec())
status(job)         # "running" or "done"
job <- await(job)   # blocks until resolution
job$log
```

### What’s in the skeleton

Before
[`await()`](https://danielrak.github.io/genproc/reference/await.md):

- `log`, `n_success`, `n_error`, `duration_total_secs` are `NULL`.
- `reproducibility` is already populated — the snapshot is captured
  synchronously, before the future is submitted, so it reflects t0.
- `status` is `"running"`.
- The future itself is stored in `attr(x, "future")`.

After
[`await()`](https://danielrak.github.io/genproc/reference/await.md):

- All fields populated as in a synchronous run.
- `attr(x, "future")` is removed.
- `status` is `"done"` — or `"error"` if the wrapper future itself
  crashed (a rare case: per-case errors are caught by the logging layer
  and don’t propagate to the wrapper).

### Idempotence

[`await()`](https://danielrak.github.io/genproc/reference/await.md) is
idempotent. Calling it on an object that has already been materialized
(or was synchronous to begin with) returns it unchanged. This makes it
safe to pepper in user code without tracking whether a particular result
has already been collected.

### Default strategy: why `"multisession"`

Unlike
[`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md),
[`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
defaults to `strategy = "multisession"`, not `NULL`. Rationale: a
function named “non-blocking” must not silently block because the
current
[`future::plan()`](https://future.futureverse.org/reference/plan.html)
is `sequential` (the default in a fresh R session). Power-users who
manage their plan can pass `strategy = NULL` explicitly to defer.

## Composition: parallel × non-blocking

The two optional layers are orthogonal:

``` r
job <- genproc(
  convert, mask,
  parallel    = parallel_spec(workers = 6),
  nonblocking = nonblocking_spec()
)
# get control back immediately
# ... do other work ...
job <- await(job)
```

The non-blocking layer launches one outer future. Inside it, the
parallel layer dispatches cases via `future.apply`. Note: with both set
to `multisession`, `future.apply` detects it is already inside a future
and degrades the inner layer to `sequential` by default, to avoid worker
explosion. For true nested parallelism, install
`future::plan(list(...))` explicitly and pass `strategy = NULL` on both
specs.

## Current edges and roadmap

Not yet in the package, but explicitly planned:

- **Input file hashing**: the `reproducibility` layer records the mask,
  but does not yet hash file inputs referenced in the mask. When a file
  changes without its path changing, that drift is currently invisible —
  this will be flagged.
- **Content-based `case_id`**: today case IDs are index-based. A
  content-based variant will make replay stable even if mask rows are
  reordered.
- **Error replay**: `replay(result, case_id)` to rerun one failed case
  in isolation.
- **Monitored progress**: opt-in progress reporting that survives
  non-blocking and parallel modes.
- **`cancel()` for non-blocking**: backend-dependent, deferred.

The architecture is designed so that adding these layers does not
require changes to existing user code — new layers are composed as extra
arguments to
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md),
and extra fields on `genproc_result` accumulate without removing
existing ones.
