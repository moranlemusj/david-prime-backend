# david-prime-backend

> Stateless agents over a federated network of per-repo oracles.

Rust reference implementation of the **David Prime Oracle Protocol** — a
SHA-pinned, citation-verified knowledge layer that agents query instead of
loading whole repos into context. Ships as a single `oracle` CLI that
indexes a repo, serves it over MCP, and runs a per-user **hub** that routes
queries across many local and remote oracles with per-repo access policy.

**Status:** very early. The workspace, CI, and protocol specification are
in place; the first functional crate (`oracle-protocol`) is the next
deliverable.

- **Spec:** [`SPEC.md`](./SPEC.md) — Oracle Protocol v0.1, including the
  federation layer (§§3–6).
- **Companion:** [`moranlemusj/david-prime-frontend`](https://github.com/moranlemusj/david-prime-frontend) —
  web UI for browsing oracles, asking questions, and managing the hub.

## Crate layout

| Crate              | Role |
|--------------------|------|
| `oracle-cli`       | The `oracle` binary — `index`, `serve`, `hub`, `verify`, `inspect`, `init` subcommands |
| `oracle-protocol`  | Wire types for every shape in `SPEC.md`; generates JSON Schemas |
| `oracle-store`     | SQLite read/write per SPEC §8 (manifest, files, spans, edges, FTS, vec) |
| `oracle-index`     | Repo → artifact pipeline: tree-sitter, SCIP, embeddings |
| `oracle-verify`    | Cite-or-refuse verifier (§7.1.1) with pluggable LLM composer |
| `oracle-serve`     | MCP server (stdio + streamable-HTTP) for one artifact |
| `oracle-hub`       | Per-user federation hub: registry, supervisor, MCP proxy, access policy |

## Build

```bash
cargo build --workspace
cargo test --workspace
./scripts/check.sh   # full sanity sweep (test + clippy + fmt + structural)
```

Toolchain: stable Rust, auto-installed via `rust-toolchain.toml` when you
`cd` in with `rustup`. See [`docs/TOOLCHAIN.md`](./docs/TOOLCHAIN.md) for
system-dep prerequisites that later development phases will introduce
(tree-sitter grammars, SCIP indexers, ONNX runtime).

## Contributing

Read [`CLAUDE.md`](./CLAUDE.md) for the architecture overview and code
conventions before opening a PR. CI runs `cargo test`, `cargo clippy
-D warnings`, and `cargo fmt --check` on every PR; `scripts/check.sh`
is the recommended local pre-PR command.

## License

MIT — see [`LICENSE`](./LICENSE).
