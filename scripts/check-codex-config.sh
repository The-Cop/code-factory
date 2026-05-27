#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
    echo "  SKIP  codex CLI not found"
    exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/config.toml" <<'EOF'
model = "gpt-5.5"
approval_policy = "on-request"
sandbox_mode = "read-only"

[sandbox_workspace_write]
network_access = false

[projects."/tmp/code-factory-preserve"]
trust_level = "trusted"

[mcp_servers.unrelated]
command = "true"
EOF

CODEX_HOME="$TMP_DIR" "$ROOT/install-codex-mcp.sh" >/dev/null

python3 - "$TMP_DIR/config.toml" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
content = path.read_text()

required = [
    "# --- Codex Settings (managed by code-factory from codex/config.toml) ---",
    "# --- End Codex Settings ---",
    "# --- MCP Servers (managed by code-factory from mcp.json) ---",
    "# --- End MCP Servers ---",
    'approval_policy = "never"',
    'sandbox_mode = "workspace-write"',
    "[sandbox_workspace_write]",
    "network_access = true",
    "[mcp_servers.atlassian]",
    "[mcp_servers.unrelated]",
    '[projects."/tmp/code-factory-preserve"]',
    'model = "gpt-5.5"',
]

missing = [item for item in required if item not in content]
if missing:
    raise SystemExit(f"missing expected Codex config entries: {missing}")

singletons = [
    "approval_policy",
    "sandbox_mode",
    "mcp_oauth_callback_port",
    "mcp_oauth_callback_url",
]
for key in singletons:
    count = len(re.findall(rf"(?m)^{re.escape(key)}\s*=", content))
    if count != 1:
        raise SystemExit(f"expected exactly one {key}, found {count}")

if len(re.findall(r"(?m)^\[sandbox_workspace_write\]\s*$", content)) != 1:
    raise SystemExit("expected exactly one [sandbox_workspace_write] table")
PY

DOCTOR_JSON="$TMP_DIR/doctor.json"
CODEX_HOME="$TMP_DIR" codex --strict-config doctor --json >"$DOCTOR_JSON" 2>/dev/null || true

python3 - "$DOCTOR_JSON" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
config = data.get("checks", {}).get("config.load", {})
if config.get("status") != "ok":
    raise SystemExit(f"Codex config.load check failed: {config}")
PY

echo "  OK  Codex managed config"
