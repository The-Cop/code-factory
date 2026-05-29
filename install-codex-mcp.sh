#!/usr/bin/env bash
#
# install-codex-mcp.sh -- Install Codex config from code-factory sources.
#
# mcp.json is the single source of truth for MCP server definitions.
# codex/config.toml is the source of truth for managed Codex permissions.
# This script updates $CODEX_HOME/config.toml, preserving unrelated Codex
# settings and unrelated MCP servers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_JSON="${MCP_JSON:-$SCRIPT_DIR/mcp.json}"
CODEX_SETTINGS="${CODEX_SETTINGS:-$SCRIPT_DIR/codex/config.toml}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_CONFIG="${CODEX_CONFIG:-$CODEX_HOME/config.toml}"

mkdir -p "$CODEX_HOME"

python3 - "$MCP_JSON" "$CODEX_SETTINGS" "$CODEX_CONFIG" <<'PYEOF'
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

MCP_JSON = Path(sys.argv[1])
CODEX_SETTINGS = Path(sys.argv[2])
CODEX_CONFIG = Path(sys.argv[3])

START = "# --- MCP Servers (managed by code-factory from mcp.json) ---"
END = "# --- End MCP Servers ---"
SETTINGS_START = "# --- Codex Settings (managed by code-factory from codex/config.toml) ---"
SETTINGS_END = "# --- End Codex Settings ---"


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


def generated_mcp_section_prefixes(names):
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


def strip_marker_block(content, start, end):
    marker_re = re.compile(r"\n?" + re.escape(start) + r"\n.*?\n" + re.escape(end) + r"\n?", re.DOTALL)
    return marker_re.sub("\n", content)


def strip_managed_sections(content, mcp_names, root_keys, table_prefixes):
    content = strip_marker_block(content, START, END)
    content = strip_marker_block(content, SETTINGS_START, SETTINGS_END)

    prefixes = generated_mcp_section_prefixes(mcp_names)
    prefixes.update(table_prefixes)
    kept = []
    skipping = False
    in_table = False
    for line in content.splitlines():
        if re.match(r"\s*\[[^\]]+\]\s*$", line):
            in_table = True
            skipping = is_managed_section(line, prefixes)
            if skipping:
                continue
        if not in_table and any(re.match(rf"\s*{re.escape(key)}\s*=", line) for key in root_keys):
            continue
        if skipping:
            continue
        kept.append(line)

    return "\n".join(kept).rstrip()


def insert_root_settings(content, root_lines):
    if not root_lines:
        return content

    lines = content.splitlines()
    table_index = next(
        (index for index, line in enumerate(lines) if re.match(r"\s*\[[^\]]+\]\s*$", line)),
        len(lines),
    )
    prefix = "\n".join(lines[:table_index]).rstrip()
    suffix = "\n".join(lines[table_index:]).lstrip()
    settings = "\n".join(root_lines)

    return "\n\n".join(part for part in (prefix, settings, suffix) if part).rstrip()


def insert_block_before_first_table(content, block):
    if not block:
        return content

    lines = content.splitlines()
    table_index = next(
        (index for index, line in enumerate(lines) if re.match(r"\s*\[[^\]]+\]\s*$", line)),
        len(lines),
    )
    prefix = "\n".join(lines[:table_index]).rstrip()
    suffix = "\n".join(lines[table_index:]).lstrip()

    return "\n\n".join(part for part in (prefix, block.rstrip(), suffix) if part).rstrip()


def oauth_value(oauth, *names):
    for name in names:
        if name in oauth and oauth[name] not in (None, ""):
            return oauth[name]
    return None


def codex_oauth_callback_config(servers):
    ports = []
    urls = []
    for name, cfg in servers.items():
        oauth = cfg.get("oauth") or {}
        port = oauth_value(oauth, "callbackPort", "callback_port")
        url = oauth_value(oauth, "callbackUrl", "callback_url")

        if port not in (None, ""):
            try:
                port = int(port)
            except (TypeError, ValueError):
                raise ValueError(f"{name}: oauth callbackPort must be an integer") from None
            if not 1 <= port <= 65535:
                raise ValueError(f"{name}: oauth callbackPort must be between 1 and 65535")
            ports.append(port)

        if url not in (None, ""):
            urls.append(str(url))

    unique_ports = sorted(set(ports))
    unique_urls = sorted(set(urls))
    if len(unique_ports) > 1:
        raise ValueError("Codex only supports one global MCP OAuth callback port")
    if len(unique_urls) > 1:
        raise ValueError("Codex only supports one global MCP OAuth callback URL")

    port = unique_ports[0] if unique_ports else None
    url = unique_urls[0] if unique_urls else None

    if url and port is None:
        parsed = urlparse(url)
        if parsed.port is None:
            raise ValueError("Codex MCP OAuth callback URL must include a port")
        port = parsed.port

    if port is not None and not url:
        url = f"http://localhost:{port}/callback"

    return port, url


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


def generate_root_settings(callback_port, callback_url):
    lines = []
    if callback_port is not None:
        lines.append(f"mcp_oauth_callback_port = {toml_value(callback_port)}")
    if callback_url:
        lines.append(f"mcp_oauth_callback_url = {toml_value(callback_url)}")
    return lines


def generate_codex_settings_block(path):
    if not path.exists():
        raise FileNotFoundError(f"{path} does not exist")

    content = path.read_text().strip()
    if not content:
        return ""

    return "\n".join([SETTINGS_START, content, SETTINGS_END]) + "\n"


data = json.loads(MCP_JSON.read_text())
servers = data.get("mcpServers", {})
if not isinstance(servers, dict):
    raise TypeError("mcpServers must be an object")

existing = CODEX_CONFIG.read_text() if CODEX_CONFIG.exists() else ""
callback_port, callback_url = codex_oauth_callback_config(servers)
managed_root_keys = []
if callback_port is not None:
    managed_root_keys.append("mcp_oauth_callback_port")
if callback_url:
    managed_root_keys.append("mcp_oauth_callback_url")
managed_root_keys.extend(["approval_policy", "sandbox_mode", "default_permissions"])
managed_table_prefixes = {"sandbox_workspace_write", "permissions.read-all-write-selected"}
base = strip_managed_sections(existing, set(servers), managed_root_keys, managed_table_prefixes)
base = insert_root_settings(base, generate_root_settings(callback_port, callback_url))
base = insert_block_before_first_table(base, generate_codex_settings_block(CODEX_SETTINGS))
block = generate_block(servers)
new_content = f"{base}\n\n{block}" if base else block

CODEX_CONFIG.parent.mkdir(parents=True, exist_ok=True)
CODEX_CONFIG.write_text(new_content)

print(f"Installed Codex settings and {len(servers)} MCP servers into {CODEX_CONFIG}")
PYEOF
