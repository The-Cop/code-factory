#!/usr/bin/env bash
#
# install-codex-mcp.sh -- Install Codex MCP server config from mcp.json.
#
# mcp.json is the single source of truth for MCP server definitions.
# This script updates $CODEX_HOME/config.toml, preserving unrelated Codex
# settings and unrelated MCP servers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_JSON="${MCP_JSON:-$SCRIPT_DIR/mcp.json}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-$CODEX_HOME/config.toml}"

mkdir -p "$CODEX_HOME"

python3 - "$MCP_JSON" "$CODEX_CONFIG" <<'PYEOF'
import json
import re
import sys
from pathlib import Path

MCP_JSON = Path(sys.argv[1])
CODEX_CONFIG = Path(sys.argv[2])

START = "# --- MCP Servers (managed by code-factory from mcp.json) ---"
END = "# --- End MCP Servers ---"


def toml_key(value):
    if re.fullmatch(r"[A-Za-z0-9_-]+", value):
        return value
    return json.dumps(value)


def toml_value(value):
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value))


def table_path(*parts):
    return ".".join(toml_key(part) for part in parts)


def generated_section_prefixes(names):
    prefixes = set()
    for name in names:
        prefixes.add(table_path("mcp_servers", name))
        prefixes.add(f'mcp_servers."{name}"')
    return prefixes


def is_managed_section(line, prefixes):
    match = re.match(r"\s*\[([^\]]+)\]\s*$", line)
    if not match:
        return False

    section = match.group(1).strip()
    return any(section == prefix or section.startswith(prefix + ".") for prefix in prefixes)


def strip_managed_sections(content, names):
    marker_re = re.compile(
        r"\n?" + re.escape(START) + r"\n.*?\n" + re.escape(END) + r"\n?",
        re.DOTALL,
    )
    content = marker_re.sub("\n", content)

    prefixes = generated_section_prefixes(names)
    kept = []
    skipping = False
    for line in content.splitlines():
        if re.match(r"\s*\[[^\]]+\]\s*$", line):
            skipping = is_managed_section(line, prefixes)
            if skipping:
                continue
        if skipping:
            continue
        kept.append(line)

    return "\n".join(kept).rstrip()


def oauth_value(oauth, *names):
    for name in names:
        if name in oauth and oauth[name] not in (None, ""):
            return oauth[name]
    return None


def generate_block(servers):
    lines = [START]

    for index, (name, cfg) in enumerate(servers.items()):
        if index:
            lines.append("")

        lines.append(f"[{table_path('mcp_servers', name)}]")

        if "url" in cfg:
            lines.append(f"url = {toml_value(cfg['url'])}")

            bearer = cfg.get("bearerTokenEnvVar") or cfg.get("bearer_token_env_var")
            if bearer:
                lines.append(f"bearer_token_env_var = {toml_value(bearer)}")

            oauth = cfg.get("oauth") or {}
            resource = oauth_value(oauth, "resource", "oauthResource", "oauth_resource")
            if resource:
                lines.append(f"oauth_resource = {toml_value(resource)}")

            client_id = oauth_value(oauth, "clientId", "client_id")
            if client_id:
                lines.append("")
                lines.append(f"[{table_path('mcp_servers', name, 'oauth')}]")
                lines.append(f"client_id = {toml_value(client_id)}")

        elif "command" in cfg:
            lines.append(f"command = {toml_value(cfg['command'])}")
            args = cfg.get("args", [])
            if args:
                if not isinstance(args, list):
                    raise TypeError(f"{name}: args must be a list")
                lines.append(f"args = {toml_value(args)}")

            env = cfg.get("env") or {}
            if env:
                if not isinstance(env, dict):
                    raise TypeError(f"{name}: env must be an object")
                lines.append("")
                lines.append(f"[{table_path('mcp_servers', name, 'env')}]")
                for key, value in sorted(env.items()):
                    lines.append(f"{toml_key(key)} = {toml_value(value)}")
        else:
            raise ValueError(f"{name}: expected either url or command")

    lines.append(END)
    return "\n".join(lines) + "\n"


data = json.loads(MCP_JSON.read_text())
servers = data.get("mcpServers", {})
if not isinstance(servers, dict):
    raise TypeError("mcpServers must be an object")

existing = CODEX_CONFIG.read_text() if CODEX_CONFIG.exists() else ""
base = strip_managed_sections(existing, set(servers))
block = generate_block(servers)
new_content = f"{base}\n\n{block}" if base else block

CODEX_CONFIG.parent.mkdir(parents=True, exist_ok=True)
CODEX_CONFIG.write_text(new_content)

print(f"Installed {len(servers)} MCP servers into {CODEX_CONFIG}")
PYEOF
