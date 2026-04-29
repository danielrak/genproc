# Package index

## Run an iteration

The central entry point. Wraps a function and a mask with the two
mandatory layers (logged + reproducibility) and exposes the optional
ones.

- [`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md)
  : Run a function over a mask with mandatory logging and
  reproducibility
- [`print(`*`<genproc_result>`*`)`](https://danielrak.github.io/genproc/reference/print.genproc_result.md)
  : Print a genproc result

## Optional execution layers

Composable specs passed to
[`genproc()`](https://danielrak.github.io/genproc/reference/genproc.md).
Parallel dispatches cases across workers via the future ecosystem.
Non-blocking returns immediately and lets you collect the result later.

- [`parallel_spec()`](https://danielrak.github.io/genproc/reference/parallel_spec.md)
  : Specify a parallel execution strategy for genproc()
- [`nonblocking_spec()`](https://danielrak.github.io/genproc/reference/nonblocking_spec.md)
  : Specify a non-blocking execution strategy for genproc()
- [`status()`](https://danielrak.github.io/genproc/reference/status.md)
  : Query the status of a genproc run without blocking
- [`await()`](https://danielrak.github.io/genproc/reference/await.md) :
  Block until a non-blocking genproc run has resolved

## Reproducibility tooling

Compare two runs to detect silent drift of upstream input files.

- [`diff_inputs()`](https://danielrak.github.io/genproc/reference/diff_inputs.md)
  [`print(`*`<genproc_input_diff>`*`)`](https://danielrak.github.io/genproc/reference/diff_inputs.md)
  : Compare input file fingerprints between two genproc runs

## Building blocks

Derive the function and the mask from a working example. Useful when
migrating an existing one-off script to a genproc workflow.

- [`from_example_to_function()`](https://danielrak.github.io/genproc/reference/from_example_to_function.md)
  : Transform an example expression into a parameterized function
- [`from_function_to_mask()`](https://danielrak.github.io/genproc/reference/from_function_to_mask.md)
  : Derive an iteration mask template from a function's signature
- [`rename_function_params()`](https://danielrak.github.io/genproc/reference/rename_function_params.md)
  : Rename the parameters of a function
- [`add_trycatch_logrow()`](https://danielrak.github.io/genproc/reference/add_trycatch_logrow.md)
  : Wrap a function with error handling and a structured log row
