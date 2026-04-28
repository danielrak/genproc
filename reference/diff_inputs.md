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
```

## Arguments

- r0, r1:

  Two `genproc_result` objects. By convention, `r0` is the earlier run
  and `r1` the later one, but the function is symmetric with respect to
  `changed` / `unchanged`. The labels `removed` (present in `r0`, absent
  in `r1`) and `added` (the opposite) follow the asymmetric convention.

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

## Details

Files are matched by canonical absolute path. The `method` field must
agree between the two runs.

## Examples

``` r
if (FALSE) { # \dontrun{
  r0 <- genproc(my_fn, my_mask)
  # ... edit one of the input CSVs ...
  r1 <- genproc(my_fn, my_mask)
  diff_inputs(r0, r1)
} # }
```
