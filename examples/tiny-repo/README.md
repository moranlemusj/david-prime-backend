# tiny-repo

Multi-language fixture for testing `oracle-index`, `oracle-store`, and
downstream crates. Each language implements the same trivial "greeter":

- `greet(name)` — public entry point.
- `format_greeting(name)` — helper, called only by `greet`.

This gives every test:

- a single deterministic call edge per language (`greet` → `format_greeting`),
- consistent symbol names across languages so parity tests are trivial to
  assert,
- enough syntactic surface area for tree-sitter and SCIP extractors to do
  real work, without any platform-specific I/O or external dependencies.

The fixture is intentionally excluded from the parent workspace
(`exclude = ["examples"]` in the root `Cargo.toml`) so `cargo build` at the
workspace root never tries to compile it.
