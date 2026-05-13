# Toolchain & system dependencies

This document covers what you need installed locally to build and contribute
to `david-prime-backend`. CI installs the same set on every run.

## Today

### Rust

The project pins to stable Rust via [`rust-toolchain.toml`](../rust-toolchain.toml).
If you have `rustup`, just `cd` into the repo and the right toolchain
installs automatically.

```bash
# Install rustup (if you don't have it)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# Then in this repo:
cd path/to/david-prime-backend
rustup show                  # confirms stable + rustfmt + clippy are installed
cargo build --workspace      # builds everything
cargo test --workspace       # runs the test suite
```

Minimum supported Rust version (MSRV): **1.74.1**. Workspace lints rely on
[`[workspace.lints]`](https://rust-lang.github.io/rfcs/3389-workspace-lints.html)
which lands in 1.74; older toolchains will refuse to build.

### Platform notes

- **macOS:** Xcode Command Line Tools (`xcode-select --install`) for the
  system linker. No other prereqs at this stage.
- **Linux:** `build-essential` (Debian/Ubuntu) or equivalent for `cc` and
  `pkg-config`. SQLite headers are not required yet — `rusqlite` will
  bundle them when the storage crate pulls it in.
- **Windows:** the workspace builds on stable MSVC Rust, but CI is
  Linux-only. Treat Windows as best-effort for now.

## Coming as development proceeds

These deps aren't required yet; they land as the relevant crates pick them
up. Documenting now so contributors can pre-install if they want.

### `oracle-store` (SQLite layer)

- **SQLite (bundled).** `rusqlite` with the `bundled` feature compiles
  SQLite from source — no system install needed. Add `bundled-sqlcipher`
  later if private oracles need encryption at rest.
- **sqlite-vec.** Vector-search extension. Bundled via `sqlite-vec-rs`
  crate.

### `oracle-index` (code parsing + reference resolution + embeddings)

- **Tree-sitter grammars (Rust crates).** Pulled in as `tree-sitter-rust`,
  `tree-sitter-go`, `tree-sitter-typescript`, `tree-sitter-python`. They
  compile from source on first build — first build is slow, subsequent
  builds are cached.
- **SCIP indexers (external binaries).** Required for reference resolution:
  - `scip-rust` — `cargo install scip-rust`
  - `scip-go` — `go install github.com/sourcegraph/scip-go/cmd/scip-go@latest`
  - `scip-typescript` — `npm install -g @sourcegraph/scip-typescript`
  - `scip-python` — `pip install scip-python` (or pipx)
  Without these, the indexer falls back to tree-sitter `locals` queries
  with reduced precision. The indexer detects which are installed and
  degrades gracefully.
- **ONNX runtime.** Used by `fastembed-rs` for code embeddings. macOS:
  bundled via crate. Linux: usually bundled, occasionally needs
  `libonnxruntime` system package. The model itself
  (`nomic-embed-code-v1.5`) downloads to `~/.cache/david-prime/models/`
  on first run.

### `oracle-verify` (cite-or-refuse with pluggable composer)

- **API key for the default composer.** `oracle verify` uses Gemini 3 Flash
  Preview by default; set `GOOGLE_API_KEY` (or `GEMINI_API_KEY`).
  Alternate composers:
  - Anthropic (`ANTHROPIC_API_KEY`) — `--composer=anthropic`.
  - Ollama (local, no key) — `--composer=ollama --ollama-url=http://localhost:11434`.
  See `SPEC.md` §7.1.1 — the composer is pluggable from day one.

### `oracle-hub` (federation hub lifecycle)

- **launchd / systemd-user.** Needed only if you want the hub to start at
  login. `oracle hub install` writes the appropriate unit file; macOS
  needs no extra deps. Linux needs `systemctl --user` available
  (standard on most desktop distributions).

## Pre-commit hook (optional)

If you want to run the CI checks locally before each commit, drop this in
`.git/hooks/pre-commit` and `chmod +x` it:

```bash
#!/usr/bin/env bash
set -euo pipefail
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

It's intentionally not auto-installed — many contributors prefer running
checks on demand.
