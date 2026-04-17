# Derive an iteration mask template from a function's signature

Takes a function (typically produced by
[`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md))
and returns a one-row data.frame where each column corresponds to a
parameter, with the default value as the cell value. This "template
mask" is the starting point the user expands into a multi-row mask that
defines all iteration cases.

## Usage

``` r
from_function_to_mask(f)
```

## Arguments

- f:

  A function whose formals define the mask columns.

## Value

A one-row data.frame with one column per parameter. Parameters with
default values get those values; parameters without defaults get `NA`.

## Details

### What is a mask?

In genproc, a **mask** is a data.frame where each row is an iteration
case and each column is a parameter. The function
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
will call the user's function once per row, passing column values as
arguments.

`from_function_to_mask()` produces a one-row template. The user then
builds the full mask by adding rows (e.g. via
[`rbind()`](https://rdrr.io/r/base/cbind.html),
[`dplyr::bind_rows()`](https://dplyr.tidyverse.org/reference/bind_rows.html),
or by constructing a multi-row data.frame directly).

### Current limitations (v0.1)

Only scalar atomic defaults are supported (character, numeric, integer,
logical). Non-scalar defaults (vectors, lists, data.frames) will be
supported in a future version via list-columns. This extension will
preserve backwards compatibility: any mask that works today will
continue to work unchanged.

### Metadata (case_id, hashes, etc.)

The mask returned here is a **pure data.frame of parameter values**.
Metadata such as `case_id`, input file hashes, or seeds are managed
separately by
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
at execution time — they are not stored as columns or attributes of the
mask. This design ensures that standard data.frame operations
([`dplyr::filter()`](https://dplyr.tidyverse.org/reference/filter.html),
`[`, [`rbind()`](https://rdrr.io/r/base/cbind.html)) never accidentally
strip metadata.

When the mask is later generalized to a dedicated class
(`genproc_mask`), existing code passing a plain data.frame will continue
to work (backwards compatibility is a hard constraint).

## Examples

``` r
fn <- function(input_path = "data.csv", n_rows = 100) {
  head(read.csv(input_path), n_rows)
}
mask <- from_function_to_mask(fn)
mask
#>   input_path n_rows
#> 1   data.csv    100
#   input_path n_rows
# 1   data.csv    100

# Expand to multiple cases:
full_mask <- data.frame(
  input_path = c("a.csv", "b.csv", "c.csv"),
  n_rows = c(10, 50, 100)
)
```
