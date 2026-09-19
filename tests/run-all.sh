#!/usr/bin/env bash
# Runs every test in tests/ and the manifest validator. First failure stops it.
set -euo pipefail
cd "$(dirname "$0")/.."
for t in tests/test-*.sh; do [ -e "$t" ] || continue; echo "== $t"; bash "$t"; done
for t in tests/test-*.py; do [ -e "$t" ] || continue; echo "== $t"; python3 "$t"; done
for t in tests/*.cjs; do [ -e "$t" ] || continue; echo "== $t"; node "$t"; done
if command -v omarchy >/dev/null; then echo "== omarchy plugin validate"; omarchy plugin validate .; fi
echo "all green"
