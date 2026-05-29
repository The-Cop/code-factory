#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
    echo "  SKIP  codex CLI not found"
    exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$ROOT/codex/rules/code-factory.rules"

expect_decision() {
    local rules="$1"
    local expected="$2"
    shift 2

    local output
    output="$(codex execpolicy check --rules "$rules" "$@" 2>/dev/null)"

    local output_file
    output_file="$(mktemp)"
    printf '%s' "$output" > "$output_file"

    python3 - "$expected" "$*" "$output_file" <<'PY'
import json
import sys
from pathlib import Path

expected = sys.argv[1]
command = sys.argv[2]
data = json.loads(Path(sys.argv[3]).read_text())
actual = data.get("decision", "none")

if actual != expected:
    raise SystemExit(f"{command}: expected {expected}, got {actual}; output={data}")
PY

    rm -f "$output_file"
}

expect_prompt() {
    expect_decision "$RULES" prompt "$@"
}

expect_unmatched() {
    expect_decision "$RULES" none "$@"
}

expect_prompt sudo ls
expect_prompt dd if=/dev/zero of=/tmp/x
expect_prompt diskutil eraseDisk APFS test disk2
expect_prompt chmod -R 777 .
expect_prompt chown -R rodrigo .
expect_prompt rm -rf /
expect_prompt rm -r -f /Users/rodrigo.fernandes
expect_prompt git reset --hard HEAD
expect_prompt git clean -fd
expect_prompt git clean -fdx
expect_prompt git push --force origin main
expect_prompt git push origin --force main
expect_prompt git push origin main --force
expect_prompt git branch -D old-branch
expect_prompt git checkout -- README.md
expect_prompt git rebase main
expect_prompt git stash drop
expect_prompt brew install jq
expect_prompt npm install -g typescript
expect_prompt npm i --global typescript

expect_unmatched git status
expect_unmatched rg pattern
expect_unmatched make all
expect_unmatched python -m pytest tests
expect_unmatched rm -rf /tmp/code-factory-test
expect_unmatched git push origin HEAD

TMP_RULES="$(mktemp)"
trap 'rm -f "$TMP_RULES"' EXIT
cat > "$TMP_RULES" <<'EOF'
prefix_rule(pattern=["git", "reset"], decision="forbidden")
prefix_rule(pattern=["git", "reset", "--hard"], decision="allow")
EOF

expect_decision "$TMP_RULES" forbidden git reset --hard HEAD

echo "  OK  Codex execpolicy rules"
