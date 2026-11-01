# goosefmt

`goosefmt` is a Goose command-line formatter and linter, implemented in Goose. It uses Goose's
standard `os` module for file access and has no third-party dependencies.

## Run

Run directly through the Goose compiler:

```sh
goose run src/goosefmt.goose -- format .
goose run src/goosefmt.goose -- lint src/
goose run src/goosefmt.goose -- check .
```

Build a native executable with `goose build src/goosefmt.goose -o ./goosefmt`, then run `./goosefmt`
with the same commands. Running without arguments displays the help output. With no paths, the
current directory is scanned recursively for `.goose` files. `format` writes changes atomically;
`format --check` reports files that would change without writing them. `check` combines format
checking with linting. Pass `-` as the only path to read source from standard input.

The directory scan skips hidden entries, `.git`, `node_modules`, `target`, `build`, `dist`,
`vendor`, and `coverage`.

## Configuration

The CLI reads `.goosefmt.toml` from the current directory when present. Use `--config FILE` to select
another file. The supported settings are:

```toml
[format]
indent_width = 4
final_newline = true

[lint]
max_line_length = 120
max_file_lines = 500
max_function_parameters = 6
max_function_returns = 3
max_function_lines = 70

# Individual checks can be disabled.
indentation = true
spacing = true
one_statement_per_line = true
line_length = true
final_newline = true
naming = true
signature_size = true
file_length = true
import_order = true
redundant_condition_parens = true
function_length = true
extern_const_slice = true
const_global_naming = true
reference_bind_push = true
split_compound_assert = true
bounded_control_flow = true
strict_safety = false
```

The linter reports these rules:

- `G001`: indentation
- `G002`–`G004`: binary operator, comma, and colon spacing
- `G005`: multiple statements on one line
- `G006`–`G007`: line length and final newline
- `G008`–`G009`: positional parameter and return-value counts
- `G010`: file length
- `G011`: Goose naming conventions
- `G012`: import placement, grouping, ordering, and duplicates
- `G013`: redundant condition and return parentheses
- `G014`: configurable function length (`max_function_lines`, default 70)
- `G015`: non-const slices in `extern fn` parameters
- `G016`: top-level constant naming
- `G017`: reference bindings from `.push(...)` and `.alloc_ref(...)`
- `G018`: compound assertions
- `G019`: visible loop termination (recursive functions are checked when `strict_safety` is enabled)

The formatter sorts imports into package, standard library, and project module groups. It keeps
multi-value returns, multi-bindings, and `for` headers on one line, recognizes Goose generic and
prefix-reference syntax, and attaches `else` branches to the preceding closing brace.

The formatter tokenizes Goose comments, strings, raw strings, and nested block comments before
changing whitespace. It expands blocks and statement separators vertically, uses four-space
indentation by default, and preserves literal contents.

`G014` counts physical lines from the opening body brace through the closing brace, including
comments and blank lines. `G017` is a local, syntax-based warning: it tracks direct pool-result
bindings and subsequent writes or links, respects local shadowing, and excludes recognized
variable-size values. It does not resolve types across modules. `G019` checks for visible exits
or a step counter with an asserted bound; it does not prove that a loop terminates.

Run `task test` for the Goose regression suite, `task build` to build the executable, and
`./goosefmt check src` to check this repository with its default limits. The regression runner
also accepts source file paths: `goose run src/tests.goose -- path/to/file.goose` verifies
formatting stability and preservation of code tokens outside sorted imports.
