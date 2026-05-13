# David Prime — Oracle Protocol v0.1

**Status:** draft  •  **Date:** 2026-05-13

> **Stateless agents over a federated network of per-repo oracles.**
>
> Each repo publishes a portable, SHA-pinned, citation-verified oracle. Agents stay small and ephemeral; they query the oracles they're allowed to reach for the slice they need. A per-user **hub** routes those queries — locally it supervises on-demand oracle processes, remotely it proxies to hosted oracles. Access is governed by per-repo policy: each consumer repo declares which **groups** of oracles (and which individual oracles) it can reach. The oracle is the persistence layer — agents never carry the whole repo in context, never pay to "restore" it, and can query peer repos' oracles through the same hub they use for their own.

---

## 0. Why this exists

Today, agents working in real codebases pay a giant tax:
- A fresh session greps and reads its way around the repo: tens of thousands of tokens just to orient itself.
- A resumed session replays the entire prior transcript on every turn — every old `Read`, every old `grep` result, billed again.
- Cross-repo work is essentially impossible — you can't drag two monorepos into one context window.

The architectural shift this protocol enables:

| | Old model | Oracle model |
|---|---|---|
| Where repo knowledge lives | Inside each agent's context | Inside the repo's oracle, indexed once per SHA |
| Cost per task | O(repo size) to orient + O(transcript) to resume | O(answer size) — only the slice needed |
| `--resume` | Required, expensive | Irrelevant — agent is stateless by design |
| Cross-repo queries | Re-index B inside A's session | Hub-routed MCP call to B's oracle, gated by policy |

The product isn't a faster `--resume`; it's a world where `--resume` isn't needed because state was never on the agent.

---

## 1. Design goals

1. **Stateless-agent-friendly.** The oracle answers narrow questions with narrow responses. Agents stay tiny; they ask, get a cited slice, move on. No agent ever needs to "load" the repo.
2. **Portable.** The oracle is a file (or set of files) you can copy, commit, or publish as a release artifact. It is the primary object, not a cache of one.
3. **SHA-pinned.** Every oracle is built for exactly one commit SHA. Answers are deterministic and reproducible. New commit → new oracle.
4. **Cite-or-refuse.** Every `ask` answer either carries verified file:line citations into the indexed SHA, or refuses. No ungrounded prose.
5. **Network-reachable.** Spoken over MCP (stdio + streamable-HTTP). Any agent runtime that speaks MCP can consume it. Self-host or hosted; same protocol.
6. **Federation-friendly.** A per-user hub provides a single MCP entry point that routes across many local and remote oracles, supervises local processes on demand, and enforces per-repo access policy. Agents see one URL; the hub handles the rest.
7. **Cache-friendly.** Stable response shapes + stable system-prompt-able digests make Anthropic-style prompt caching cheap on the consumer side. Repeat queries cost ~10%.
8. **Trust-bounded.** Oracles can be signed by the repo's key. Consumers may verify the signature before trusting answers. The hub may enforce access policy; in hosted mode it also enforces identity.

Non-goals for v0.1: multi-turn conversation state, streaming, write operations, code execution, hosted multi-tenant hub (v0.2).

---

## 2. Terminology

- **Repo** — a git repository being indexed.
- **Artifact** — the portable file(s) holding the index for one SHA. By convention: `.oracle/index.db` (SQLite). Implementations MAY use additional sidecar files.
- **Oracle** — a process serving the artifact over MCP. Identified by a two-segment slash-separated `name` (`<org>/<repo>`, e.g., `acme/backend-api`).
- **Group** — a label that one or more oracles self-assign in their manifest. Groups are namespaced by the oracle's org prefix (an oracle named `acme/backend-api` declaring `groups: ["backend"]` is in the canonical group `acme/backend`). Groups are flat — they do not contain other groups, and they do not carry policy.
- **Consumer repo** — a repo whose agent makes oracle queries. A consumer repo declares its access in `.oracle/access.toml` at its root.
- **Hub** — a per-user process that maintains a registry of known oracles, supervises local oracle child processes on demand, proxies MCP traffic to local or remote oracles, and enforces per-consumer-repo access policy. Reachable by default at `http://localhost:9494`.
- **Consumer** — any agent / runtime making `ask` / `search` calls, typically through the hub.
- **Citation** — a span `(path, line_start, line_end)` resolvable at the artifact's SHA.

---

## 3. Discovery

The protocol has two layers of discovery:

1. **Single-oracle discovery** — how an agent or hub finds *one* oracle by its repo path or git URL. This is the `.well-known/oracle.json` file described below.
2. **Federation discovery** — how a consumer repo's agent finds the *set* of oracles it's allowed to reach. This is the hub's `GET /hub/agents/me` endpoint, described in §6.

In normal use, agents do not call single-oracle discovery directly. They call the hub once at session start and receive a list of resolved oracle URLs to mount as MCP servers. Single-oracle discovery is what the hub itself uses to populate its registry.

### 3.1 `.well-known/oracle.json`

Every repo that publishes an oracle MUST commit a `.well-known/oracle.json` at its root. This is how the hub finds an oracle when registering a local repo or proxying to a remote one.

```json
{
  "spec_version": "0.1",
  "name": "acme/backend-api",
  "groups": ["backend", "core"],
  "repo_sha": "abc1234...",
  "artifact": {
    "kind": "sqlite",
    "path": ".oracle/index.db",
    "size_bytes": 12482931,
    "sha256": "sha256:..."
  },
  "endpoints": [
    { "transport": "mcp-http", "url": "https://oracle.acme.com/backend-api" },
    { "transport": "mcp-stdio", "command": "oracle serve --artifact=.oracle/index.db" }
  ],
  "auth": "anonymous",
  "signing": {
    "alg": "ed25519",
    "public_key": "base64...",
    "signature": "base64..."
  }
}
```

- `name`: REQUIRED. Two-segment slash-separated identifier `<org>/<repo>`. Globally unique within a hub's registry.
- `groups`: optional list of bare group names. Each is canonicalized by the hub to `<org>/<group>` using the oracle's name's `<org>` prefix. Same org, same canonical group name. Different orgs cannot share a group.
- `repo_sha`: SHA the artifact was built for. MUST match the artifact's internal `repo_sha`.
- `endpoints`: zero or more transports the oracle can be reached over. If empty, only the artifact is published and the hub must self-host it (local fork via `mcp-stdio`).
- `auth`: `anonymous` | `bearer` | `mtls`. `bearer` and `mtls` MAY require additional out-of-band setup; v0.1 only fully specifies `anonymous`. The hub may inject auth headers when proxying to a remote oracle whose policy requires them.
- `signing`: optional. If present, `signature` is over the canonical JSON of the rest of the file plus the artifact's `sha256`.

#### 3.1.1 Diff-noise mitigation (informative)

`sha256` and `size_bytes` change on every code-changing commit. To keep PR diffs reviewable, implementations MAY:
- Move those two fields into an uncommitted sidecar (`.well-known/oracle.lock`), regenerated locally / by CI, and `.gitignore`d.
- OR omit them entirely from the in-repo file and publish them as part of a release artifact pipeline (the hub fetches them at registration).

Indexers MUST skip `.well-known/oracle.json`, `.well-known/oracle.lock`, and `.oracle/` from their input file set so that updates to these files do not themselves trigger reindexing.

### 3.2 Discovering a single remote oracle by git URL

When the hub is asked to proxy to a remote oracle named `acme/backend-api` that is not in its registry, it MAY locate the manifest by fetching:

```
https://raw.githubusercontent.com/acme/backend-api/main/.well-known/oracle.json
```

The hub caches the fetched manifest with a TTL of 1 hour (configurable). `oracle hub refresh <name>` forces a refetch. The protocol does not specify a non-GitHub fallback in v0.1; private git hosts require explicit registration.

---

## 4. Groups & access policy

### 4.1 Group semantics

- An oracle declares zero or more bare group names in its manifest's `groups` array. Bare names are canonicalized to `<org>/<group>` using the oracle's `name`'s org prefix.
- An oracle MAY be in multiple groups.
- Groups have no other state. They are not entities the hub stores independently — they exist only as labels on oracles. A group "exists" iff at least one oracle declares it.
- Two oracles with different orgs declaring the same bare group (`acme/backend-api: groups=["backend"]` vs `subway/backend-api: groups=["backend"]`) are in two distinct groups: `acme/backend` and `subway/backend`. There is no cross-org group sharing in v0.1.

### 4.2 `.oracle/access.toml`

Each consumer repo declares its access list in `.oracle/access.toml` at its root, committed to source control.

```toml
# spec version
version = "0.1"

# (Optional) declare which org this consumer belongs to.
# Used to resolve bare group references in `access` below. Defaults to the
# `<org>` segment of the repo's own oracle name if it has one, else REQUIRED.
org = "acme"

# Access list. Each entry references either a group or a single oracle by name.
# Resolution order: group entries expand to all oracles labeled with that group,
# then individual oracle entries are unioned in. Duplicates are deduped.
access = [
  { group = "backend" },                    # bare → "acme/backend" by `org`
  { group = "subway/graphql" },             # fully-qualified
  { oracle = "shared/design-tokens" },
]
```

- `org`: provides the namespace used to expand bare `group` references. If omitted, falls back to the consumer repo's own `<org>` from its own `.well-known/oracle.json`; if that is also absent, the file is invalid.
- `access`: a flat list. Each entry is either `{ group = "..." }` or `{ oracle = "..." }`. Other shapes are reserved for future versions.
- A consumer repo with no `.oracle/access.toml` has empty access (no oracles reachable through the hub). It MAY still query oracles directly if it knows their MCP URLs out-of-band; the hub's role is to *enable* not to *enforce* network reachability.

### 4.3 Resolution

When the hub is asked "what does consumer repo at path P see?":

1. Read `P/.oracle/access.toml`.
2. For each `group` entry, canonicalize the name and collect all oracles in the hub's registry whose canonical group set contains it.
3. For each `oracle` entry, look up the oracle by name in the registry.
4. Filter out any oracle the hub cannot currently reach (no endpoint, no cached manifest, etc.).
5. Return the deduped list as `[{name, mcp_url}, …]`.

Resolution is non-transitive: groups only group targets. There are no rules of the form "group X may reach group Y."

### 4.4 What "access" means

Access governs what the hub *exposes* to a caller. It does not encrypt or authenticate the underlying oracles — an oracle that is reachable directly (e.g., via a known `http://localhost:7777` URL) can be called by anyone who can reach it. v0.1's local hub is a convenience layer, not a security boundary. v0.2's hosted hub is the security boundary, and oracles behind it are required to be reachable only through the hub.

---

## 5. The hub

### 5.1 What it is

The hub is a per-user process that:

1. Maintains a **registry** of known oracles (local repos and remote URLs), keyed by oracle `name`.
2. Resolves each consumer repo's `.oracle/access.toml` into a list of reachable oracles on demand.
3. **Supervises** local oracle child processes — for a registered local repo, the hub forks `oracle serve --stdio` on first request and idles it out after N minutes of no traffic (default 15).
4. **Proxies MCP** traffic from the agent to the underlying oracle (local child process via stdio, or remote URL via HTTP).
5. Serves a small **HTTP control plane** for registration, status, and resolution.

The hub is NOT itself an oracle — it does not index repos or compose answers. It is a directory + supervisor + proxy.

### 5.2 Default address

The hub listens on `http://localhost:9494` by default. Configurable via `--listen` flag or `ORACLE_HUB_LISTEN` env var.

### 5.3 HTTP control plane

JSON over HTTP. Loopback-only in v0.1 (anonymous).

#### `GET /hub/status`

```json
{
  "spec_version": "0.1",
  "hub_version": "0.1.0",
  "registry_count": 4,
  "running_children": 1
}
```

#### `GET /hub/oracles`

List every oracle in the registry.

```json
{
  "oracles": [
    {
      "name": "acme/backend-api",
      "groups": ["acme/backend", "acme/core"],
      "source": "local",
      "path": "/Users/me/code/acme-backend-api",
      "mcp_url": "http://localhost:9494/acme/backend-api/",
      "status": "registered"
    },
    {
      "name": "shared/design-tokens",
      "groups": [],
      "source": "remote",
      "manifest_url": "https://raw.githubusercontent.com/shared/design-tokens/main/.well-known/oracle.json",
      "mcp_url": "http://localhost:9494/shared/design-tokens/",
      "status": "registered"
    }
  ]
}
```

#### `GET /hub/agents/me?repo=<absolute-path>`

The session-start lookup. Returns the resolved access list for the consumer repo at `repo`.

```json
{
  "repo": "/Users/me/code/acme-frontend",
  "org": "acme",
  "accessible": [
    { "name": "acme/backend-api",     "mcp_url": "http://localhost:9494/acme/backend-api/" },
    { "name": "acme/backend-wallet",  "mcp_url": "http://localhost:9494/acme/backend-wallet/" },
    { "name": "shared/design-tokens", "mcp_url": "http://localhost:9494/shared/design-tokens/" }
  ],
  "policy_path": "/Users/me/code/acme-frontend/.oracle/access.toml",
  "policy_sha256": "sha256:..."
}
```

If the consumer repo has no `.oracle/access.toml`, the response carries an empty `accessible` array and `policy_path: null`.

#### `POST /hub/oracles` — register a local repo

```json
{ "path": "/Users/me/code/acme-backend-api" }
```

Hub reads `<path>/.well-known/oracle.json`, validates, adds to registry under the manifest's `name`. Conflicts on `name` return `409 Conflict`.

#### `POST /hub/oracles/remote` — register a remote oracle

```json
{ "name": "shared/design-tokens" }
```

Hub fetches `https://raw.githubusercontent.com/shared/design-tokens/main/.well-known/oracle.json`, validates, adds to registry.

#### `DELETE /hub/oracles/{name}`

Unregister. Local children of this oracle are SIGTERM'd.

#### `POST /hub/refresh/{name}`

Force the hub to re-read a local manifest (after a code change) or re-fetch a remote manifest.

### 5.4 MCP proxy plane

For each registered oracle named `<org>/<repo>`, the hub exposes an MCP streamable-HTTP endpoint at:

```
http://localhost:9494/<org>/<repo>/
```

When an agent connects to this URL and issues an MCP tool call:
- **Local oracle:** hub ensures a child `oracle serve --stdio --artifact=<path>/.oracle/index.db` is running (forks on first request, reuses on subsequent), forwards the MCP call over the child's stdio, streams the response back to the caller.
- **Remote oracle:** hub forwards the MCP call to the remote endpoint URL from the manifest. Authenticates as configured.

The hub MUST NOT serve `<org>/<repo>` to a caller for whom `GET /hub/agents/me` would not have returned it. In v0.1's loopback hub this is advisory; v0.2's hosted hub enforces it.

### 5.5 Identity (caller identification)

- **v0.1 local:** the caller of the control plane sends the consumer repo's absolute path in the request (`?repo=…`). The hub does not authenticate; it trusts that loopback callers run as the user. The path's `.oracle/access.toml` is the policy.
- **v0.1 MCP proxy plane:** the agent sends no special identity. The agent knows its allowed oracle URLs from the prior `agents/me` call and only mounts those; the hub does not re-check on every MCP call.
- **v0.2 hosted (deferred):** caller sends `Authorization: Bearer <token>` plus `X-Oracle-Repo: <org>/<repo>`. Hub validates the token and the user's permission to act as that repo identity, then resolves policy from the server-side store. Tokens are short-lived and minted by an SSO flow. v0.2 enforces access at the MCP proxy plane.

### 5.6 Lifecycle

- Hub starts up: reads registry from `~/.david-prime/registry.toml`, opens HTTP listener.
- First request for a local oracle: hub forks `oracle serve --stdio`, holds a handle, pipes MCP both ways.
- Idle child: hub SIGTERMs children after `child_idle_seconds` (default 900) of no traffic. New request respawns.
- Registry mutation: writes through to `~/.david-prime/registry.toml` synchronously.
- Hub install / uninstall: `oracle hub install` registers a launchd plist (macOS) or systemd `--user` unit (linux) so the hub starts at login. `oracle hub uninstall` removes it.

### 5.7 What the hub deliberately does NOT do (v0.1)

- It does not encrypt traffic between agent and hub (loopback only).
- It does not authenticate callers (loopback only).
- It does not enforce access — it serves what `access.toml` declares but doesn't prevent direct connections to the underlying oracles.
- It does not host oracles (no multi-tenant identity, no audit log).
- It does not index repos. That's `oracle index`.

All of these except indexing are v0.2 work.

---

## 6. Transports

- **`mcp-stdio`** — REQUIRED. Local invocation; one process per consumer. The hub uses this to talk to its local children.
- **`mcp-http`** — REQUIRED for hosted oracles and for the hub's proxy plane. MCP streamable-HTTP. Stateless w.r.t. the artifact (multiple concurrent consumers OK).
- **`a2a`** — OPTIONAL. v0.2+.

Tool names use the standard MCP method format. All four oracle tools defined below MUST be exposed identically over every transport.

---

## 7. Tools (oracle data plane)

### 7.1 `ask`

Compose a grounded answer to a natural-language question about the repo.

**Request:**
```json
{
  "question": "How does the auth middleware reject expired tokens?",
  "min_citations": 1,
  "max_tokens": 1500,
  "expected_sha": null
}
```

- `min_citations` (default 1): refuse if fewer survive verification.
- `max_tokens` (default 1500): soft cap on answer length.
- `expected_sha` (optional): if set and does not match the oracle's `repo_sha`, oracle returns `STALE` (see §9). Lets consumers pin reproducible runs.

**Response (verified):**
```json
{
  "answer": "Expired tokens are rejected in `ValidateJWT` [1], which calls `parseClaims` [2] and returns `ErrTokenExpired` when `exp < now`.",
  "citations": [
    {
      "id": 1,
      "path": "src/middleware/auth.go",
      "line_start": 42,
      "line_end": 67,
      "snippet_sha256": "sha256:...",
      "preview": "func ValidateJWT(token string) error {"
    },
    {
      "id": 2,
      "path": "src/middleware/auth.go",
      "line_start": 88,
      "line_end": 104,
      "snippet_sha256": "sha256:...",
      "preview": "func parseClaims(tok string) (*Claims, error) {"
    }
  ],
  "repo_sha": "abc1234...",
  "verified": true,
  "usage": {
    "retrieval_ms": 18,
    "compose_ms": 612,
    "verify_ms": 9,
    "input_tokens": 1842,
    "output_tokens": 137,
    "cost_usd": 0.00231,
    "provider": "google/gemini-3-flash-preview"
  }
}
```

**Response (refusal):**
```json
{
  "answer": null,
  "citations": [],
  "repo_sha": "abc1234...",
  "verified": false,
  "refusal_reason": "INSUFFICIENT_CITATIONS",
  "details": "Composed answer cited 2 spans; 0 survived verification."
}
```

`usage.cost_usd` is the total provider-billed USD for the composer call. Implementations MUST populate it when the provider exposes billing info; if not available, the field is `null` and `provider` still identifies the model used.

#### 7.1.1 Cite-or-refuse algorithm (NORMATIVE)

An implementation MUST:

1. **Retrieve** candidate spans via §7.2 (`search`).
2. **Compose** a draft answer with sentence-level structural tags. Every sentence MUST be either:
   - `<claim cite="1,2">…</claim>` — asserts something verifiable about the code (names a symbol, describes behavior, asserts a contract). MUST carry at least one citation marker.
   - `<scaffolding>…</scaffolding>` — transitional or framing text. MUST NOT make verifiable code-level claims. MUST NOT carry citations.
   The composer is responsible for this classification. If a sentence makes a verifiable claim without a citation, implementations MUST treat it as a `claim` with zero citations (and therefore subject to step 5).
3. **Verify citations.** For each citation, re-read the file from the artifact at `repo_sha` and compute the SHA-256 of the cited line range. Compare to the snippet hash recorded at index time.
4. **Drop unverifiable citations** — any citation whose hash does not match (drift from source, hallucinated line range, etc.).
5. **Salvage claims with regeneration.** For each `claim` whose citations all dropped:
   1. Re-prompt the composer with surviving evidence only, asking it to either (a) re-cite the claim against a surviving span, or (b) remove the claim.
   2. If after one regeneration pass the claim still has no surviving citation, drop the sentence.
   Implementations MUST attempt at most one regeneration pass per claim. They MUST NOT loop.
6. **Pass scaffolding through ungated** — `scaffolding` sentences are not verified (they make no factual claims).
7. **Refuse if any of:**
   - Zero `claim` sentences survive.
   - The fraction of original `claim` sentences dropped exceeds `refusal_threshold` (default `0.5`).
   - The number of distinct surviving citations is less than `min_citations` (from the request).
   On refusal, return the standard refusal shape (§7.1) with `refusal_reason: "INSUFFICIENT_CITATIONS"`.
8. **Strip tags before returning.** The final `answer` field MUST NOT contain `<claim>` / `<scaffolding>` markup; that markup is internal to the verifier. Citation markers (`[1]`, `[2]`) remain in the prose.

Implementations MAY add additional verification (NLI checks, embedding similarity between claim and cited span, etc.). They MUST NOT relax steps 3–7 or skip the regeneration pass in step 5.

The composer itself MUST be pluggable. Reference implementation defaults to `google/gemini-3-flash-preview` but selects via configuration; conforming implementations may use any model that can produce the structural markup in step 2.

##### Rationale

Strict "drop any sentence whose citations all dropped" produces choppy output and over-refuses when most of an answer is fine. The claim/scaffolding split lets transitional text flow naturally while keeping the verifiable-content contract strict. The single regeneration pass handles the common case where the composer cited a near-miss span — given surviving evidence it usually re-cites correctly.

### 7.2 `search`

Hybrid retrieval. No LLM composition. Returns ranked candidates.

**Request:**
```json
{
  "query": "auth middleware",
  "k": 10,
  "kind": "hybrid",
  "filters": { "path_glob": "src/**", "lang": ["go"] }
}
```

- `kind`: `hybrid` (default) | `bm25` | `vector` | `symbol`.
- `filters` (optional): path glob, language(s), node-kind whitelist.

**Response:**
```json
{
  "results": [
    {
      "path": "src/middleware/auth.go",
      "line_start": 42,
      "line_end": 67,
      "snippet": "func ValidateJWT(token string) error { ... }",
      "snippet_sha256": "sha256:...",
      "score": 0.91,
      "kind_matched": "symbol:Function"
    }
  ],
  "repo_sha": "abc1234..."
}
```

### 7.3 `status`

Health + metadata.

**Response:**
```json
{
  "spec_version": "0.1",
  "name": "acme/backend-api",
  "groups": ["acme/backend", "acme/core"],
  "repo_sha": "abc1234...",
  "indexed_at": "2026-05-13T14:22:03Z",
  "schema_version": 1,
  "stats": {
    "files": 1284,
    "symbols": 18402,
    "languages": { "go": 0.81, "sql": 0.09, "yaml": 0.10 }
  }
}
```

### 7.4 `schema`

Structural schema for consumers that want to do their own queries (advanced use).

**Response:**
```json
{
  "node_kinds": ["File", "Function", "Method", "Class", "Interface", "Route", "..."],
  "edge_kinds": ["CALLS", "IMPORTS", "DEFINES", "IMPLEMENTS", "HTTP_CALLS", "..."],
  "search_kinds": ["hybrid", "bm25", "vector", "symbol"],
  "filters": ["path_glob", "lang", "node_kind"]
}
```

---

## 8. Artifact format (v0.1 reference)

Reference implementation uses SQLite. Other backends are permitted as long as they expose the tools above.

Required tables:

```sql
CREATE TABLE manifest (
  key TEXT PRIMARY KEY,
  value TEXT
);
-- rows: repo_sha, indexed_at, spec_version, schema_version, name, groups

CREATE TABLE files (
  path TEXT PRIMARY KEY,
  blob_sha TEXT NOT NULL,     -- git blob SHA at repo_sha
  lang TEXT,
  size_bytes INTEGER
);

CREATE TABLE spans (
  id INTEGER PRIMARY KEY,
  path TEXT NOT NULL,
  line_start INTEGER NOT NULL,
  line_end INTEGER NOT NULL,
  kind TEXT NOT NULL,         -- Function, Method, Class, ...
  name TEXT,
  signature TEXT,
  snippet_sha256 TEXT NOT NULL,
  FOREIGN KEY (path) REFERENCES files(path)
);

CREATE TABLE edges (
  src INTEGER NOT NULL,
  dst INTEGER NOT NULL,
  kind TEXT NOT NULL,         -- CALLS, IMPORTS, ...
  FOREIGN KEY (src) REFERENCES spans(id),
  FOREIGN KEY (dst) REFERENCES spans(id)
);

CREATE VIRTUAL TABLE spans_fts USING fts5(name, signature, content, content='spans');

-- Optional: sqlite-vec embeddings
CREATE VIRTUAL TABLE spans_vec USING vec0(span_id INTEGER PRIMARY KEY, embedding FLOAT[768]);
```

The artifact MUST be openable read-only by multiple concurrent processes (SQLite WAL or immutable mode). The artifact MUST NOT be mutated after publication for a given SHA; updates produce a new artifact.

---

## 9. Errors

All error responses use this shape:

```json
{ "error": "CODE", "message": "human-readable", "details": { } }
```

| Code | Meaning |
|---|---|
| `STALE` | Consumer passed `expected_sha` that doesn't match `repo_sha`. |
| `INSUFFICIENT_CITATIONS` | `ask` refused after verification. (Not strictly an error; same shape for symmetry.) |
| `RATE_LIMITED` | Too many requests. |
| `UNAUTHORIZED` | Missing/invalid credentials for non-anonymous oracle. |
| `INVALID_REQUEST` | Malformed input. |
| `POLICY_DENIED` | Hub refused to route: consumer repo's access list does not include this oracle. (v0.2 hosted hub enforces; v0.1 local hub is advisory.) |
| `ORACLE_UNREACHABLE` | Hub could not connect to the underlying oracle (local child failed to start, remote endpoint down). |
| `INTERNAL` | Unexpected. |

---

## 10. Versioning

- `spec_version` is the version of THIS document. Breaking changes bump the major.
- `schema_version` is the version of the artifact format. Implementations MAY support multiple.
- Consumers SHOULD ignore unknown response fields.

---

## 11. Security & trust (v0.1 baseline)

- **Signing (optional):** if `.well-known/oracle.json` has a `signing` block, consumers MAY verify the artifact `sha256` and the file's canonical bytes against the published `public_key`.
- **Anonymous oracles** make no trust claims beyond "this is the answer the artifact produces." Treat them as you would untrusted documentation.
- **v0.1 local hub** runs on loopback only. It does not authenticate callers and does not encrypt traffic. It is a convenience layer, not a security boundary. Users who need access enforcement should wait for v0.2 hosted hub.
- **Bearer / mTLS auth** (private repos) are noted but not specified in v0.1. Implementations should follow MCP's standard auth patterns.
- **Remote manifest fetch** (§3.2) inherits the trust model of the git host (TLS + whoever can push to `main`). Same threat surface as `cargo install` from crates.io.

---

## 12. Open questions for v0.2

- **Hosted multi-tenant hub.** Auth (SSO + short-lived tokens), tenant isolation, audit logs, per-tenant indexer service, billing.
- **Multi-turn / session state.** Needed for follow-up questions without re-grounding from scratch.
- **Streaming responses.** UX nicety; not required for correctness.
- **Cross-oracle citations.** When one repo's answer cites a peer repo, standardize the cross-reference shape.
- **Group ACLs.** v0.1 has groups only on the target side. v0.2 may add consumer-side grouping or hierarchical groups if real demand emerges.
- **Transitive policy.** Currently each consumer repo declares its own access list verbatim. Org-level default policy that consumers can inherit/override would help large deployments.
- **Non-GitHub remote discovery.** Generalize §3.2 beyond GitHub raw fetch (GitLab, Bitbucket, self-hosted gitea, etc.).
- **A2A binding.** When A2A v1.2+ stabilizes, define the agent-card translation.
- **Signed artifacts.** Default ed25519 + sigstore option.

---

## 13. Reference implementation roadmap (informative, not normative)

- `oracle index <repo>` → produces `.oracle/index.db` per §8.
- `oracle serve --artifact=path` → exposes tools per §7 over MCP stdio + streamable-HTTP.
- `oracle hub` → runs the hub per §5. Subcommands: `install`, `uninstall`, `start`, `stop`, `status`, `register <path>`, `register-remote <name>`, `unregister <name>`, `refresh <name>`, `ls`.
- `oracle verify <artifact>` → re-runs §7.1.1 against a held-out Q&A set; reports citation accuracy / refusal rate.
- Session-start integration for MCP clients: on launch, calls `GET /hub/agents/me?repo=$(git rev-parse --show-toplevel)` and writes the resulting MCP servers into the client's MCP config.

End.
