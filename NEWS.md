# genproc 0.0.0.9000

* Package skeleton initialized.
* `from_example_to_function()`: transform an example expression into a
  parameterized function (modular AST rewrite engine, zero rlang dependency).
* `from_function_to_mask()`: derive a one-row template mask (data.frame)
  from a function's signature.
* `rename_function_params()`: rename parameters in formals and body.
* `add_trycatch_logrow()`: wrap a function with error handling, real
  traceback capture, and timing.
