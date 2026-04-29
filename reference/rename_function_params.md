# Rename the parameters of a function

Takes a function and a name mapping, and returns a new function where
both the formals and all symbol references in the body have been renamed
according to the mapping. This is typically used after
[`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md)
to replace generated names like `param_1`, `param_2` with meaningful
names.

## Usage

``` r
rename_function_params(f, mapping)
```

## Arguments

- f:

  A function whose parameters should be renamed.

- mapping:

  A named character vector. Names are the **current** parameter names,
  values are the **new** names. Example:
  `c(param_1 = "input_path", param_2 = "output_path")`.

## Value

A function with renamed formals and body.

## Details

### Validation

The function checks that:

- All names in `mapping` actually exist as formals of `f`

- New names are unique (no duplicates)

- New names do not collide with parameters not being renamed

### Limitation

If the body contains a nested function definition whose formals shadow a
parameter being renamed, the shadowed references in that inner body will
still be renamed. This is unlikely in practice (parameters from
[`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md)
are named `param_N`) but is noted here for completeness.

## Examples

``` r
fn <- function(param_1 = "in.csv", param_2 = "out.csv") {
  df <- read.csv(param_1)
  write.csv(df, param_2)
}

fn2 <- rename_function_params(fn, c(
  param_1 = "input_path",
  param_2 = "output_path"
))

# Formals were renamed:
formals(fn2)
#> $input_path
#> [1] "in.csv"
#> 
#> $output_path
#> [1] "out.csv"
#> 

# And the body too — references to `param_1` and `param_2` are
# updated in place, the function source is not edited.
body(fn2)
#> {
#>     df <- read.csv(input_path)
#>     write.csv(df, output_path)
#> }
```
