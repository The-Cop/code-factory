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

expect_forbidden() {
    expect_decision "$RULES" forbidden "$@"
}

expect_unmatched() {
    expect_decision "$RULES" none "$@"
}

expect_forbidden sudo ls
expect_forbidden dd if=/dev/zero of=/tmp/x
expect_forbidden diskutil eraseDisk APFS test disk2
expect_forbidden chmod -R 777 .
expect_forbidden chown -R rodrigo .
expect_forbidden rm -rf /
expect_forbidden rm -r -f /Users/rodrigo.fernandes
expect_forbidden git reset --hard HEAD
expect_forbidden git clean -fd
expect_forbidden git clean -fdx
expect_forbidden git push --force origin main
expect_forbidden git push origin --force main
expect_forbidden git push origin main --force
expect_forbidden git branch -D old-branch
expect_forbidden git checkout -- README.md
expect_forbidden git rebase main
expect_forbidden git stash drop
expect_forbidden brew install jq
expect_forbidden npm install -g typescript
expect_forbidden npm i --global typescript

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
