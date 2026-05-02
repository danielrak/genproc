# Compare input file fingerprints between two genproc runs

Takes two
[genproc_result](https://danielrak.github.io/genproc/reference/genproc.md)
objects produced by
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
(the same function over the same mask, run at two different times) and
reports which referenced input files have changed since the first run.

## Usage

``` r
diff_inputs(r0, r1)

# S3 method for class 'genproc_input_diff'
print(x, ...)
```

## Arguments

- r0, r1:

  Two `genproc_result` objects. By convention, `r0` is the earlier run
  and `r1` the later one, but the function is symmetric with respect to
  `changed` / `unchanged`. The labels `removed` (present in `r0`, absent
  in `r1`) and `added` (the opposite) follow the asymmetric convention.

- x:

  A `genproc_input_diff` object.

- ...:

  Ignored (present for S3 method consistency).

## Value

An object of class `genproc_input_diff` (a named list) with components:

- method:

  Character, e.g. `"stat"`.

- changed:

  A data.frame with columns `path`, `size_before`, `size_after`,
  `mtime_before`, `mtime_after`. One row per file whose size or mtime
  differs.

- unchanged:

  Character vector of paths whose size and mtime are identical in both
  runs.

- removed:

  Character vector of paths present in `r0`'s snapshot but absent in
  `r1`'s.

- added:

  Character vector of paths present in `r1`'s snapshot but absent in
  `r0`'s.

- cases_affected:

  A data.frame with columns `case_id`, `path`, `column`, `change_type`
  (one of `"changed"`, `"removed"`, `"added"`). One row per (case, input
  column) impacted by the diff. Pass to
  [`rerun_affected()`](https://danielrak.github.io/genproc/reference/rerun_affected.md)
  to re-run only the impacted cases.

## Details

Files are matched by canonical absolute path. The `method` field must
agree between the two runs.

## Examples

``` r
# Two runs of the same procedure, with one input file rewritten
# in between. `diff_inputs()` reports the drift.
src <- file.path(tempdir(), "diff-inputs-demo")
dir.create(src, showWarnings = FALSE, recursive = TRUE)
write.csv(head(iris), file.path(src, "a.csv"), row.names = FALSE)

mask <- data.frame(
  path = file.path(src, "a.csv"),
  stringsAsFactors = FALSE
)
read_one <- function(path) nrow(read.csv(path))

r0 <- genproc(read_one, mask)

# Rewrite the file with strictly more rows: size changes.
write.csv(iris, file.path(src, "a.csv"), row.names = FALSE)

r1 <- genproc(read_one, mask)
diff_inputs(r0, r1)
#> genproc input diff (method: stat)
#>   Changed:   1
#>   Unchanged: 0
#>   Removed:   0
#>   Added:     0
#>   Cases affected: 1
#> 
#> Changed files:
#>   /tmp/RtmpsPB9k2/diff-inputs-demo/a.csv
#>       size:  214 B -> 3.9 KB
#>       mtime: 2026-05-02 20:17:40 -> 2026-05-02 20:17:40
#> 
#> Cases affected (use rerun_affected() to re-run):
#>   case_0001
```
