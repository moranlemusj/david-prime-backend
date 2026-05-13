# CLAUDE.md — context for AI assistants

Orientation for any AI assistant (Claude Code, Cursor, etc.) editing this
repo. Read this first; it points at everything else.

## What this project is

Rust reference implementation of the **David Prime Oracle Protocol** — a
SHA-pinned, citation-verified knowledge layer that AI assistants query
instead of loading whole repositories into context. The protocol itself
is defined in [`SPEC.md`](./SPEC.md); this repo ships the canonical
implementation.

Headline shape:

- Each repo publishes an **oracle** (a SQLite artifact + an MCP server).
- A per-user **hub** routes queries across many oracles, supervises local
  child processes on demand, and enforces per-repo access policy.
- Consumers talk to one URL (`http://localhost:9494/<name>/`) and the hub
  handles the rest.

`SPEC.md` is the contract. When in doubt, defer to it.

## Repo layout

```
Cargo.toml                  # workspace root
crates/
  oracle-cli/               # `oracle` binary
  oracle-protocol/          # wire types, JSON Schemas (SPEC source of truth)
  oracle-store/             # SQLite read/write (SPEC §8)
  oracle-index/             # repo → artifact pipeline
  oracle-verify/            # cite-or-refuse + pluggable composer
  oracle-serve/             # MCP server for one artifact
  oracle-hub/               # federation hub
examples/tiny-repo/         # multi-language test fixture (Rust + Go + Python)
scripts/                    # contributor helpers (check.sh runs full sanity)
docs/                       # toolchain + contributor docs
SPEC.md                     # protocol contract
```

## Commands

```bash
cargo build --workspace                                   # build everything
cargo test --workspace                                    # run all tests
cargo clippy --workspace --all-targets -- -D warnings     # lint
cargo fmt --all -- --check                                # format check
./scripts/check.sh                                        # full sanity sweep
```

CI runs the test + clippy + fmt subset on every PR — see
`.github/workflows/ci.yml`. `scripts/check.sh` extends that with
structural assertions (workspace shape, fixture presence, doc/license
presence) and is the recommended local pre-PR check.

## Conventions

**Wire shapes live in `oracle-protocol`.** If you find yourself defining
a struct that crosses a process boundary (MCP, HTTP, file format) outside
that crate, move it there and depend on it. Single source of truth.

**SHA-pinned everything.** Artifacts, citations, manifests — every
output this codebase produces is reproducible from a commit SHA. If
you're about to design something whose output depends on wall-clock time
or non-deterministic ordering, stop and reconsider.

**No `unsafe`.** Forbidden at the workspace level (`workspace.lints`).

**No `unwrap` / `expect` in library code.** Library crates return
`Result`; unwrapping is only acceptable at top-level binary boundaries or
in tests.

**Tests exercise real boundaries.** No mocking the thing under test;
no stubs replacing the code path the test claims to verify. Integration
tests hit real files, real subprocesses, real network where applicable.
A test whose only assertion is "this function was called" is wiring,
not behavior — assert on behavior.

**Errors:** `thiserror` for library errors (typed), `anyhow` for binary
and glue code. Don't mix the two in the same module.

**Logging:** `tracing` with structured fields. No `println!` in library
code.

## How to find things

- Protocol spec — [`SPEC.md`](./SPEC.md)
- Toolchain & system-dep setup — [`docs/TOOLCHAIN.md`](./docs/TOOLCHAIN.md)
- Per-crate purpose — module-level doc comments in `crates/*/src/{lib,main}.rs`
- CI pipeline — `.github/workflows/ci.yml`
- Sanity check script — [`scripts/check.sh`](./scripts/check.sh)
