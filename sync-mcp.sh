#!/usr/bin/env bash
#
# sync-mcp.sh -- Regenerate the MCP block in opencode.jsonc from mcp.json.
#
# mcp.json is the single source of truth for MCP server definitions.
# This script only touches local files (opencode.jsonc).
# To install MCPs into Claude Code and Codex, run `make install` (init.sh).
#
# Usage:
#   ./sync-mcp.sh          # Regenerate opencode.jsonc MCP block
#   ./sync-mcp.sh --check  # Dry-run: exit 0 if up-to-date, exit 1 if stale
#
# This script is idempotent: running it multiple times produces the same result.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_JSON="$SCRIPT_DIR/mcp.json"
OPENCODE_JSONC="$SCRIPT_DIR/opencode.jsonc"

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_MODE=true
fi

# ---------------------------------------------------------------------------
# Generate the opencode MCP block from mcp.json
# ---------------------------------------------------------------------------
generate_opencode_mcp_block() {
    python3 -c "
import json, sys

data = json.load(open('$MCP_JSON'))
servers = data.get('mcpServers', {})

lines = []
names = list(servers.keys())
for i, name in enumerate(names):
    config = servers[name]
    trailing = ',' if i < len(names) - 1 else ''

    if 'command' in config:
        # stdio server -> local
        cmd = [config['command']] + config.get('args', [])
        cmd_str = json.dumps(cmd)
        lines.append(f'    \"{name}\": {{')
        lines.append(f'      \"type\": \"local\",')
        lines.append(f'      \"command\": {cmd_str}')
        lines.append(f'    }}{trailing}')
    elif 'url' in config:
        # http/sse -> remote
        lines.append(f'    \"{name}\": {{')
        lines.append(f'      \"type\": \"remote\",')
        lines.append(f'      \"url\": \"{config[\"url\"]}\"')
        lines.append(f'    }}{trailing}')

print('\n'.join(lines))
"
}

# ---------------------------------------------------------------------------
# Update opencode.jsonc between markers
# ---------------------------------------------------------------------------
update_opencode_jsonc() {
    local mcp_block="$1"
    local target="$2"

    python3 - "$mcp_block" "$target" <<'PYEOF'
import sys, re

mcp_block = sys.argv[1]
target = sys.argv[2]

MARKER_START = "// --- MCP Servers (generated from mcp.json) ---"
MARKER_END = "// --- End MCP Servers ---"

with open(target, "r") as f:
    content = f.read()

new_section = (
    f"  {MARKER_START}\n"
    f"  \"mcp\": {{\n"
    f"{mcp_block}\n"
    f"  }},\n"
    f"  {MARKER_END}"
)

if MARKER_START in content:
    pattern = re.escape(f"  {MARKER_START}") + r".*?" + re.escape(f"  {MARKER_END}")
    content = re.sub(pattern, new_section, content, flags=re.DOTALL)
else:
    # First run: replace the existing "mcp" block.
    pattern = r'  // --- MCP Servers ---\n  "mcp": \{.*?\},\n'
    if re.search(pattern, content, flags=re.DOTALL):
        content = re.sub(pattern, new_section + "\n", content, flags=re.DOTALL)
    else:
        print("ERROR: could not find MCP block in opencode.jsonc", file=sys.stderr)
        sys.exit(1)

with open(target, "w") as f:
    f.write(content)
PYEOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [[ ! -f "$MCP_JSON" ]]; then
        echo "ERROR: $MCP_JSON not found" >&2
        exit 1
    fi

    local mcp_block
    mcp_block=$(generate_opencode_mcp_block)

    # --check mode: compare generated block against current opencode.jsonc
    if [[ "$CHECK_MODE" == "true" ]]; then
        local current_block
        current_block=$(python3 -c "
import re, sys

MARKER_START = '  // --- MCP Servers (generated from mcp.json) ---'
MARKER_END = '  // --- End MCP Servers ---'

with open('$OPENCODE_JSONC', 'r') as f:
    content = f.read()

if MARKER_START not in content:
    print('NO_MARKERS', end='')
    sys.exit(0)

pattern = re.escape(MARKER_START) + r'\n  \"mcp\": \{\n(.*?)\n  \},\n' + re.escape(MARKER_END)
m = re.search(pattern, content, flags=re.DOTALL)
if m:
    print(m.group(1), end='')
else:
    print('NO_MATCH', end='')
")
        if [[ "$current_block" == "$mcp_block" ]]; then
            echo "MCP sync is up-to-date."
            exit 0
        else
            echo "STALE  opencode.jsonc MCP block is out of sync with mcp.json"
            exit 1
        fi
    fi

    # --- opencode.jsonc: regenerate MCP block ---
    echo "Updating MCP servers in opencode.jsonc..."
    update_opencode_jsonc "$mcp_block" "$OPENCODE_JSONC"
    echo "  OK  opencode.jsonc"
}

main
