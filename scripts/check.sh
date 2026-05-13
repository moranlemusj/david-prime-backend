#!/usr/bin/env bash
# Project sanity sweep: build/test/lint/format the workspace plus verify
# the expected structural pieces (crates, fixture, docs, CI) are in place.
# CI runs the test/lint/format subset; this script extends it with
# structural assertions useful when bootstrapping a fresh checkout or
# before opening a PR.
#
# Usage:  ./scripts/check.sh
#
# `set -uo pipefail` deliberately omits -e: failing commands must let
# `check` tally them rather than aborting the script.

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
check() {
  local label="$1"; shift
  if "$@"; then
    echo "PASS: $label"
    PASS=$((PASS+1))
  else
    echo "FAIL: $label"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Project sanity check ==="

# --- workspace builds, tests pass, lints clean, format clean ---
check "cargo build --workspace" cargo build --workspace --quiet
check "cargo test --workspace" cargo test --workspace --quiet
check "cargo clippy clean" cargo clippy --workspace --all-targets --quiet -- -D warnings
check "cargo fmt clean" cargo fmt --all -- --check

# --- workspace contains exactly the seven planned crates ---
check "workspace has 7 members" bash -c '
  count=$(cargo metadata --format-version=1 --no-deps 2>/dev/null \
    | python3 -c "import json,sys; print(len(json.load(sys.stdin)[\"workspace_members\"]))")
  [ "$count" -eq 7 ]
'

# --- crate skeleton files present ---
for crate in oracle-cli oracle-protocol oracle-store oracle-index \
             oracle-verify oracle-serve oracle-hub; do
  check "crates/$crate/Cargo.toml" test -f "crates/$crate/Cargo.toml"
  if [ "$crate" = "oracle-cli" ]; then
    check "crates/$crate/src/main.rs" test -f "crates/$crate/src/main.rs"
  else
    check "crates/$crate/src/lib.rs" test -f "crates/$crate/src/lib.rs"
  fi
done

# --- tiny-repo fixture: one source per language ---
check "tiny-repo Rust fixture" test -f examples/tiny-repo/rust/src/lib.rs
check "tiny-repo Go fixture" test -f examples/tiny-repo/go/greet.go
check "tiny-repo Python fixture" test -f examples/tiny-repo/python/greet.py

# --- CI workflow exists and parses as YAML ---
check ".github/workflows/ci.yml exists" test -f .github/workflows/ci.yml
check "ci.yml parses as YAML" \
  python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"

# --- toolchain pin present ---
check "rust-toolchain.toml exists" test -f rust-toolchain.toml

# --- top-level docs + license ---
check "README.md exists" test -f README.md
check "CLAUDE.md exists" test -f CLAUDE.md
check "docs/TOOLCHAIN.md exists" test -f docs/TOOLCHAIN.md
check "LICENSE exists" test -f LICENSE

echo
echo "Total: $PASS passed, $FAIL failed."
[ "$FAIL" -eq 0 ]
