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
#> 1 case_0001 /tmp/RtmpkpZKZ7/genproc-vignette-src    a.csv
#> 2 case_0002 /tmp/RtmpkpZKZ7/genproc-vignette-src    b.csv
#> 3 case_0003 /tmp/RtmpkpZKZ7/genproc-vignette-src    c.csv
#>                                dst_dir dst_file success error_message traceback
#> 1 /tmp/RtmpkpZKZ7/genproc-vignette-dst    a.rds    TRUE          <NA>      <NA>
#> 2 /tmp/RtmpkpZKZ7/genproc-vignette-dst    b.rds    TRUE          <NA>      <NA>
#> 3 /tmp/RtmpkpZKZ7/genproc-vignette-dst    c.rds    TRUE          <NA>      <NA>
#>   duration_secs
#> 1         0.001
#> 2         0.002
#> 3         0.001
```

`case_id` is stable and index-based (`case_0001`, `case_0002`, …) for
now. A content-based variant is on the roadmap, for use cases where rows
of the mask can be reordered between runs.

### The reproducibility snapshot

``` r

str(result$reproducibility, max.level = 1)
#> List of 11
#>  $ timestamp    : POSIXct[1:1], format: "2026-05-02 20:17:44"
#>  $ r_version    : chr "R version 4.6.0 (2026-04-24)"
#>  $ platform     : chr "x86_64-pc-linux-gnu"
#>  $ os           : chr "Linux 6.17.0-1010-azure"
#>  $ locale       : chr "LC_CTYPE=C.UTF-8;LC_NUMERIC=C;LC_TIME=C.UTF-8;LC_COLLATE=C.UTF-8;LC_MONETARY=C.UTF-8;LC_MESSAGES=C;LC_PAPER=C.U"| __truncated__
#>  $ timezone     : chr "UTC"
#>  $ packages     : Named chr [1:33] "0.2.0" "0.6.39" "1.4.3" "2.6.1" ...
#>   ..- attr(*, "names")= chr [1:33] "genproc" "digest" "desc" "R6" ...
#>  $ mask_snapshot:'data.frame':   3 obs. of  4 variables:
#>  $ parallel     : NULL
#>  $ nonblocking  : NULL
#>  $ inputs       :List of 3
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
  formats. The list also carries `effective_strategy`: the strategy
  actually applied by
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md),
  which differs from `strategy` when the user passed `workers` without
  an explicit `strategy` and
  [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  auto-defaulted to `"multisession"`. Both fields are recorded so the
  snapshot is self-explanatory: `strategy` is what the user asked for,
  `effective_strategy` is what was applied.
- `nonblocking`: same pattern, for
  [`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md).
- `inputs`: a fingerprint of every file the mask refers to, or `NULL` if
  input tracking was disabled (`track_inputs = FALSE`). See the next
  section.

The snapshot lives inside the result. You can compare two results by
comparing their `$reproducibility` slots directly.

### Input fingerprinting

`reproducibility$inputs` is the layer that protects against silent drift
of upstream files. It is captured at t0 of the run, alongside the rest
of the snapshot.

``` r

str(result$reproducibility$inputs, max.level = 1)
#> List of 3
#>  $ method: chr "stat"
#>  $ files :'data.frame':  0 obs. of  3 variables:
#>  $ refs  :'data.frame':  0 obs. of  3 variables:
```

- `method`: currently `"stat"`. Reserved for future extensions
  (e.g. `"md5"` for content hashing).
- `files`: a deduplicated table of every file referenced by the mask,
  with its size in bytes and last-modified time. One row per unique
  path: a config file shared across 100 cases produces a single row.
- `refs`: the (`case_id`, `column`, `path`) triples saying who
  referenced what. Joins back to `files` by `path`.

#### Heuristic detection

By default, every character column of the mask whose non-NA values are
existing files (and contain a path separator) is treated as an input
column. The `mask` used in this vignette has its paths split across
`src_dir` and `src_file`, so the heuristic finds nothing useful —
`src_dir` is a directory (excluded), `src_file` values are bare names
(no separator). For a mask that holds absolute paths directly:

``` r

mask_paths <- data.frame(
  csv_in = file.path(src_dir, c("a.csv", "b.csv", "c.csv")),
  stringsAsFactors = FALSE
)
do_one <- function(csv_in) nrow(read.csv(csv_in))

run0 <- genproc(do_one, mask_paths)
run0$reproducibility$inputs$files
#>                                         path size               mtime
#> 1 /tmp/RtmpkpZKZ7/genproc-vignette-src/a.csv  214 2026-05-02 20:17:44
#> 2 /tmp/RtmpkpZKZ7/genproc-vignette-src/b.csv  296 2026-05-02 20:17:44
#> 3 /tmp/RtmpkpZKZ7/genproc-vignette-src/c.csv  154 2026-05-02 20:17:44
```

#### Shared inputs are deduplicated

Many cases referencing the **same** upstream file produce a single row
in `files` but one row per case in `refs`. This keeps the snapshot
economical for masks where every case shares a configuration, schema, or
lookup table.

``` r

config_path <- file.path(src_dir, "config.yml")
writeLines("threshold: 10", config_path)

mask_with_config <- data.frame(
  csv_in = file.path(src_dir, c("a.csv", "b.csv", "c.csv")),
  config = config_path,                       # same value across rows
  stringsAsFactors = FALSE
)
do_one_cfg <- function(csv_in, config) nrow(read.csv(csv_in))

run_shared <- genproc(do_one_cfg, mask_with_config)

# 4 rows: 3 unique csv_in + 1 config
nrow(run_shared$reproducibility$inputs$files)
#> [1] 4

# 6 rows: 3 cases x 2 input columns
nrow(run_shared$reproducibility$inputs$refs)
#> [1] 6
```

#### Overrides

- `genproc(..., input_cols = c("col1", "col2"))` bypasses the heuristic
  and tracks exactly the named columns. Paths that don’t exist at
  capture time are recorded with `NA` size/mtime and a warning is
  emitted.
- `genproc(..., skip_input_cols = c("col"))` keeps the heuristic but
  excludes a column (useful when a label column happens to match an
  existing file in cwd).
- `genproc(..., track_inputs = FALSE)` disables tracking entirely.
  `result$reproducibility$inputs` is `NULL`.

`input_cols` and `skip_input_cols` are mutually exclusive. Mixing them
raises an error — the two flags express contradictory intentions and the
call should clarify.

#### Comparing runs with `diff_inputs()`

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
#>   /tmp/RtmpkpZKZ7/genproc-vignette-src/a.csv
#>       size:  214 B -> 3.9 KB
#>       mtime: 2026-05-02 20:17:44 -> 2026-05-02 20:17:44
#> 
#> Cases affected (use rerun_affected() to re-run):
#>   case_0001
```

[`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md)
returns an S3 object (`genproc_input_diff`) with a print method for
human reading and named list components for programmatic access
(`$changed`, `$unchanged`, `$removed`, `$added`). Files are matched by
canonical absolute path; cross-machine comparison would need a separate
matcher and is out of scope for this version.

[`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md)
refuses to compare snapshots produced with different `method`s
(forward-compatible with a future hash mode).

## How errors are reported

A case that throws does **not** stop the run. Here we delete a source
file between two runs:

``` r

file.remove(file.path(src_dir, "b.csv"))
#> [1] TRUE
result_broken <- genproc(convert, mask)
#> Warning in file(file, "rt"): cannot open file
#> '/tmp/RtmpkpZKZ7/genproc-vignette-src/b.csv': No such file or directory

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

## Building blocks: extracting `f` and the mask from a working example

The vignette so far assumed both `f` and `mask` were already written by
hand. In practice you often start from a *working script for one
specific case* and want to derive the parameterized function and the
mask template automatically. Three exported helpers do this, in order.

### 1. `from_example_to_function()` — example expression to function

Take an example expression that works on one case. Every external value
(string literals, environment symbols that are not functions) becomes a
parameter of the resulting function, with its current value stored as
the default. Locally bound symbols (assignment targets, function
formals) are protected.

``` r

# An example that works for ONE specific case
input_path  <- file.path(src_dir, "a.csv")
output_path <- file.path(dst_dir, "a-from-example.rds")

example <- expression({
  df <- read.csv(input_path)
  saveRDS(df, output_path)
})

fn <- from_example_to_function(example)
formals(fn)
#> $param_1
#> [1] "/tmp/RtmpkpZKZ7/genproc-vignette-src/a.csv"
#> 
#> $param_2
#> [1] "/tmp/RtmpkpZKZ7/genproc-vignette-dst/a-from-example.rds"
```

### 2. `from_function_to_mask()` — function signature to mask template

Once you have the function, derive a one-row template `data.frame` that
mirrors its signature. You can then
[`rbind()`](https://rdrr.io/r/base/cbind.html) extra rows to build a
full mask.

``` r

mask_template <- from_function_to_mask(fn)
mask_template
#>                                      param_1
#> 1 /tmp/RtmpkpZKZ7/genproc-vignette-src/a.csv
#>                                                   param_2
#> 1 /tmp/RtmpkpZKZ7/genproc-vignette-dst/a-from-example.rds
```

### 3. `rename_function_params()` — give the parameters domain names

The auto-generated names (`param_1`, `param_2`, …) are stable but not
informative. Rename them in place — `formals` and body are updated
together, the function source is not edited.

``` r

fn_named <- rename_function_params(
  fn, c(param_1 = "input_path", param_2 = "output_path")
)
formals(fn_named)
#> $input_path
#> [1] "/tmp/RtmpkpZKZ7/genproc-vignette-src/a.csv"
#> 
#> $output_path
#> [1] "/tmp/RtmpkpZKZ7/genproc-vignette-dst/a-from-example.rds"
```

Putting it together: a renamed function plus a manually-built mask that
follows the same column names.

``` r

mask_built <- data.frame(
  input_path  = file.path(src_dir, c("a.csv", "b.csv", "c.csv")),
  output_path = file.path(dst_dir, c("a2.rds", "b2.rds", "c2.rds")),
  stringsAsFactors = FALSE
)
genproc(fn_named, mask_built)$n_success
#> [1] 3
```

The `f_mapping` argument shown in the next section is the inline
equivalent of step 3 — convenient when you don’t need a renamed function
for any other purpose than this single
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
call.

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

### Plan lifetime

When
[`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
installs a plan, the previous plan is **not** restored on
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
exit — it is restored by
[`await()`](https://danielrak.github.io/genproc/reference/await.md) once
the future has been collected. Restoring earlier would call
[`future::plan()`](https://future.futureverse.org/reference/plan.html)
while the wrapper future is still running, which shuts down the
multisession workers and surfaces a “Future was canceled” error at
collection time. The trade-off is that if you never call
[`await()`](https://danielrak.github.io/genproc/reference/await.md), the
installed plan stays active for the rest of the session. Power-users who
pass `strategy = NULL` and manage the plan themselves are not affected.

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

### Default `mc.cores` in the wrapper subprocess

On Windows and in some RStudio configurations, the wrapper subprocess
inherits `getOption("mc.cores")` set to `1` (the legacy default for
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html),
which is a no-op on Windows). Without intervention, `parallelly` would
refuse to spawn the inner workers because `workers / 1` exceeds the
localhost hard limit, and the composed call would fail with a confusing
`"only 1 CPU cores available for this R process (per 'mc.cores')"`
error.

[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
handles this transparently. In the composed case
(`parallel != NULL && nonblocking != NULL`), it makes two adjustments
inside the wrapper subprocess:

1.  Sets `R_PARALLELLY_AVAILABLECORES_METHODS = "system"` so that
    `parallelly` ignores `mc.cores` and uses the true detected core
    count for its hard-limit check.
2.  Raises `options(mc.cores)` from 1 to the system core count, so that
    `parallelly`’s soft-limit warning (“only 1 CPU cores available… 200%
    load”) does not fire with a misleading message after the hard limit
    has been lifted.

Both adjustments only apply if the user has not set their own values,
and only inside the wrapper subprocess. The calling session is never
modified.

## Progress monitoring

[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
integrates with the
[progressr](https://cran.r-project.org/package=progressr) framework.
Wrap the call in `progressr::with_progress(...)` to opt in:

``` r

library(progressr)

with_progress(
  result <- genproc(my_fn, mask, parallel = parallel_spec(workers = 4))
)
```

Behind the scenes,
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
emits one progression condition per completed case. `progressr` lets the
user pick any handler: the default text bar in the console, an RStudio
gadget, audible beeps, custom log lines, or any handler the user wires
up via
[`progressr::handlers()`](https://progressr.futureverse.org/reference/handlers.html).

Without
[`with_progress()`](https://progressr.futureverse.org/reference/with_progress.html),
the integration is a complete no-op — zero overhead, zero visible
change. `progressr` is a soft dependency declared in `Suggests`; the
integration is skipped if the package is not installed.

In parallel mode, signals from worker subprocesses are propagated back
to the parent session via `future.apply`. Live monitoring of
non-blocking runs is not yet supported (signals would arrive in a burst
at [`await()`](https://danielrak.github.io/genproc/reference/await.md)
time rather than live during the run); this is on the roadmap.

## Current edges and roadmap

Not yet in the package, but explicitly planned:

- **Content-hash input fingerprinting**: the current `inputs` layer uses
  a stat-based fingerprint (size + mtime), which detects every
  legitimate file modification but can be fooled by an adversary who
  preserves both. A `method = "md5"` (or `"xxhash64"`) opt-in is
  reserved in the API and will land later.
- **Content-based `case_id`**: today case IDs are index-based. A
  content-based variant will make replay stable even if mask rows are
  reordered.
- **Error replay**: `replay(result, case_id)` to rerun one failed case
  in isolation.
- **Live monitoring of non-blocking runs**: today the `progressr`
  integration covers the sequential and parallel paths only; the
  non-blocking path needs a different design (collect progress in the
  background, query on demand) and is planned.
- **`cancel()` for non-blocking**: backend-dependent, deferred.

The architecture is designed so that adding these layers does not
require changes to existing user code — new layers are composed as extra
arguments to
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md),
and extra fields on `genproc_result` accumulate without removing
existing ones.
