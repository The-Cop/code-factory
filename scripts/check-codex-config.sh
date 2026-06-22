#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
    echo "  SKIP  codex CLI not found"
    exit 0
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

make_temp_dir() {
    mktemp -d 2>/dev/null || mktemp -d -p /private/tmp
}

TMP_DIR="$(make_temp_dir)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/config.toml" <<'EOF'
model = "gpt-5.5"
approval_policy = "on-request"
sandbox_mode = "read-only"
default_permissions = "stale-profile"

[sandbox_workspace_write]
network_access = false

[permissions.datadog-dev]
description = "stale profile that should be replaced"

[permissions.datadog-dev.filesystem]
"/tmp/stale-codex-permissions" = "write"

[permissions.code-factory]
description = "stale profile that should be replaced"

[permissions.code-factory.filesystem]
"/tmp/stale-code-factory-permissions" = "write"

[permissions.read-all-write-selected]
description = "legacy managed profile that should be removed"

[permissions.read-all-write-selected.filesystem]
"/tmp/legacy-codex-permissions" = "write"

[projects."/tmp/code-factory-preserve"]
trust_level = "trusted"

[mcp_servers.unrelated]
command = "true"
EOF

CODEX_HOME="$TMP_DIR" "$ROOT/install-codex-mcp.sh" >/dev/null

PROFILE_DISABLED_SENTINEL="$TMP_DIR/code-factory-profile-disabled"

python3 - "$TMP_DIR/config.toml" "$PROFILE_DISABLED_SENTINEL" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
profile_disabled_sentinel = Path(sys.argv[2])
content = path.read_text()

# If the permissions.code-factory profile is commented out, skip full validation.
if re.search(r"(?m)^#\s*\[permissions\.code-factory\]\s*$", content):
    profile_disabled_sentinel.write_text("1")
    sys.exit(0)

required = [
    "# --- Codex Settings (managed by code-factory from codex/config.toml) ---",
    "# --- End Codex Settings ---",
    "# --- MCP Servers (managed by code-factory from mcp.json) ---",
    "# --- End MCP Servers ---",
    'sandbox_mode = "danger-full-access"',
    'default_permissions = "code-factory"',
    'allow_login_shell = true',
    'approvals_reviewer = "auto_review"',
    "[approval_policy.granular]",
    "sandbox_approval = false",
    "rules = true",
    "mcp_elicitations = true",
    "request_permissions = true",
    "skill_approval = true",
    "[shell_environment_policy]",
    'inherit = "all"',
    'set = { BROWSER = "/usr/bin/open", TMPDIR = "/tmp", TMP = "/tmp", TEMP = "/tmp" }',
    "[permissions.code-factory]",
    "[permissions.code-factory.filesystem]",
    '":root" = "read"',
    '"/Users/rodrigo.fernandes/.config/ddtool" = "write"',
    "[permissions.code-factory.workspace_roots]",
    '"/Users/rodrigo.fernandes/dev" = true',
    '"/tmp" = true',
    '"/var/folders" = true',
    '[permissions.code-factory.filesystem.":workspace_roots"]',
    '"." = "write"',
    "[permissions.code-factory.network]",
    'enabled = true',
    'mode = "full"',
    "[permissions.code-factory.network.domains]",
    '"*" = "allow"',
    "[mcp_servers.atlassian]",
    'default_tools_approval_mode = "auto"',
    "[mcp_servers.unrelated]",
    '[projects."/tmp/code-factory-preserve"]',
    'model = "gpt-5.5"',
]

missing = [item for item in required if item not in content]
if missing:
    raise SystemExit(f"missing expected Codex config entries: {missing}")

singletons = [
    "default_permissions",
    "sandbox_mode",
    "mcp_oauth_callback_port",
    "mcp_oauth_callback_url",
]
for key in singletons:
    count = len(re.findall(rf"(?m)^{re.escape(key)}\s*=", content))
    if count != 1:
        raise SystemExit(f"expected exactly one {key}, found {count}")

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

data = tomllib.loads(content)
if data.get("sandbox_mode") != "danger-full-access":
    raise SystemExit("sandbox_mode must be danger-full-access")

if data.get("default_permissions") != "code-factory":
    raise SystemExit("default_permissions must select code-factory")

if data.get("approvals_reviewer") != "auto_review":
    raise SystemExit("approvals_reviewer must be auto_review")

granular_approvals = data.get("approval_policy", {}).get("granular", {})
expected_granular_approvals = {
    "sandbox_approval": False,
    "rules": True,
    "mcp_elicitations": True,
    "request_permissions": True,
    "skill_approval": True,
}
for key, expected in expected_granular_approvals.items():
    actual = granular_approvals.get(key)
    if actual is not expected:
        raise SystemExit(f"approval_policy.granular.{key}: expected {expected}, got {actual}")

shell_environment_policy = data.get("shell_environment_policy", {})
if "sandbox_mode" in shell_environment_policy:
    raise SystemExit("sandbox_mode must not be nested under shell_environment_policy")

environment_set = shell_environment_policy.get("set", {})
expected_environment = {
    "BROWSER": "/usr/bin/open",
    "TMPDIR": "/tmp",
    "TMP": "/tmp",
    "TEMP": "/tmp",
}
for key, expected in expected_environment.items():
    actual = environment_set.get(key)
    if actual != expected:
        raise SystemExit(f"shell_environment_policy.set.{key}: expected {expected}, got {actual}")

if re.search(r"(?m)^\[sandbox_workspace_write\]\s*$", content):
    raise SystemExit("legacy [sandbox_workspace_write] table should be removed")

permissions = data.get("permissions", {})
if "read-all-write-selected" in permissions:
    raise SystemExit("legacy permissions.read-all-write-selected table should be removed")
if "datadog-dev" in permissions:
    raise SystemExit("legacy permissions.datadog-dev table should be removed")

profile = permissions.get("code-factory")
if not profile:
    if not re.search(r"(?m)^#\s*\[permissions\.code-factory\]\s*$", content):
        raise SystemExit("permissions.code-factory profile is missing")
    profile_disabled_sentinel.write_text("1")
else:
    filesystem = profile.get("filesystem", {})
    expected_filesystem = {
        ":root": "read",
        "/Users/rodrigo.fernandes/.config/ddtool": "write",
        "/Users/rodrigo.fernandes/.config/datadog": "write",
        "/Users/rodrigo.fernandes/.vault-token": "write",
    }
    for key, expected in expected_filesystem.items():
        actual = filesystem.get(key)
        if actual != expected:
            raise SystemExit(f"filesystem {key}: expected {expected}, got {actual}")

    workspace_roots = profile.get("workspace_roots", {})
    for root in [
        "/Users/rodrigo.fernandes/docs",
        "/Users/rodrigo.fernandes/dev",
        "/Users/rodrigo.fernandes/dd",
        "/Users/rodrigo.fernandes/go",
        "/Users/rodrigo.fernandes/Downloads",
        "/tmp",
        "/private/tmp",
        "/var/folders",
    ]:
        if workspace_roots.get(root) is not True:
            raise SystemExit(f"workspace root {root} must be enabled")

    workspace_filesystem = filesystem.get(":workspace_roots", {})
    if workspace_filesystem.get(".") != "write":
        raise SystemExit('filesystem.":workspace_roots"."." must be write')

    network = profile.get("network", {})
    if network.get("enabled") is not True:
        raise SystemExit("code-factory network must be enabled")
    if network.get("mode") != "full":
        raise SystemExit("code-factory network mode must be full")
    if network.get("domains", {}).get("*") != "allow":
        raise SystemExit("code-factory network must allow all domains")

mcp_servers = data.get("mcp_servers", {})
for name in [
    "atlassian",
    "slack",
    "slack-sandbox",
    "datadog-google-workspace",
    "datadog-gmail",
    "datadog-google-calendar",
]:
    server = mcp_servers.get(name, {})
    if server.get("default_tools_approval_mode") != "auto":
        raise SystemExit(f"{name}: default_tools_approval_mode must be auto")

if "default_tools_approval_mode" in mcp_servers.get("unrelated", {}):
    raise SystemExit("unrelated preserved MCP server should not receive managed approval settings")
PY

if [[ -f "$PROFILE_DISABLED_SENTINEL" ]]; then
    echo "  SKIP  Codex strict config and sandbox probes (permissions.code-factory is commented out)"
    echo "  OK  Codex managed config"
    exit 0
fi

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

ALLOWED_WRITE="/tmp/code-factory-codex-permissions-allowed-$$"
SANDBOX_PROBE_LOG="$TMP_DIR/sandbox-probe.log"
if ! CODEX_HOME="$TMP_DIR" codex sandbox --permissions-profile code-factory --include-managed-config -- true 2>"$SANDBOX_PROBE_LOG"; then
    if grep -q "sandbox_apply: Operation not permitted" "$SANDBOX_PROBE_LOG"; then
        echo "  SKIP  Codex sandbox permission probes (sandbox-exec unavailable)"
        echo "  OK  Codex managed config"
        exit 0
    fi

    cat "$SANDBOX_PROBE_LOG" >&2
    exit 1
fi

CODEX_HOME="$TMP_DIR" codex sandbox --permissions-profile code-factory --include-managed-config -- sh -c 'touch "$1" && rm "$1"' sh "$ALLOWED_WRITE"

DENIED_WRITE="/Users/rodrigo.fernandes/code-factory-codex-permissions-denied-$$"
if CODEX_HOME="$TMP_DIR" codex sandbox --permissions-profile code-factory --include-managed-config -- sh -c 'touch "$1"' sh "$DENIED_WRITE" 2>"$TMP_DIR/denied-write.log"; then
    rm -f "$DENIED_WRITE"
    echo "write outside managed roots unexpectedly succeeded" >&2
    exit 1
fi
rm -f "$DENIED_WRITE"

echo "  OK  Codex managed config"
