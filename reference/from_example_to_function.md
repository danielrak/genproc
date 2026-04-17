# Transform an example expression into a parameterized function

Takes a concrete R expression (e.g. a data processing script that works
on one specific case) and returns a function where every external value
(strings, variables from the environment that are not functions) has
been replaced by a named parameter with the original value as default.

## Usage

``` r
from_example_to_function(expr, env = parent.frame())
```

## Arguments

- expr:

  An expression of length 1, typically created with
  [`expression()`](https://rdrr.io/r/base/expression.html) or
  [`quote()`](https://rdrr.io/r/base/substitute.html) wrapped in
  [`as.expression()`](https://rdrr.io/r/base/expression.html).

- env:

  The environment in which to look up symbols. Symbols found in this
  environment that are **not** functions will be turned into parameters.
  Defaults to the caller's environment.

## Value

A function whose body is the rewritten expression and whose formals are
the detected parameters with their default values. The function's
environment is set to `env`.

## Details

This is the first step in the genproc workflow: the user writes a
working example, and `from_example_to_function()` extracts a reusable,
parameterized version of it.

### What gets parameterized

- **String literals**: every string in the expression becomes a
  parameter (e.g. `"output.csv"` -\> `param_1` with default
  `"output.csv"`).

- **Non-function symbols**: if a symbol exists in `env` and its value is
  not a function, it becomes a parameter.

### What is left unchanged

- **Locally bound symbols**: variables created by assignments inside the
  expression (e.g. `result <- ...`) are never parameterized.

- **Function names**: the head of a call (e.g. `read.csv` in
  `read.csv(path)`) is never parameterized.

- **Functions in the environment**: symbols whose value is a function
  are assumed to be part of the program structure, not data.

- **Numeric, logical, NULL, and other non-character atomic values**.

### Deduplication

The same value produces the same parameter. If `"output.csv"` appears
twice, both occurrences map to the same `param_N`.

## Examples

``` r
# --- Basic usage ---
input_path <- "/data/input.csv"

expr <- expression({
  df <- read.csv(input_path)
  write.csv(df, "output.csv")
})

fn <- from_example_to_function(expr)
fn
#> function (param_1 = "/data/input.csv", param_2 = "output.csv") 
#> {
#>     df <- read.csv(param_1)
#>     write.csv(df, param_2)
#> }
#> <environment: 0x56101abb1678>
# function(param_1 = "/data/input.csv", param_2 = "output.csv") {
#   df <- read.csv(param_1)
#   write.csv(df, param_2)
# }

# --- Local bindings are protected ---
x <- 42
expr2 <- expression({
  x <- 1
  y <- x + 1
})
fn2 <- from_example_to_function(expr2)
# x is assigned inside the block, so it is NOT parameterized
# even though x = 42 exists in the environment
```
