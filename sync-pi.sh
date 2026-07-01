#!/usr/bin/env bash
#
# sync-pi.sh -- Generate pi.dev-compatible skills, prompts, agents, extensions, and MCP config.
#
# This script:
#   1. Discovers plugins from .claude-plugin/marketplace.json
#   2. Copies skills (with body rewrites + stripped frontmatter) to .pi/skills/{name}/SKILL.md
#   3. Generates .pi/prompts/{name}.md for every user-invocable skill
#   4. Transforms agent Markdown files to .pi/agents/{name}.md
#   5. Copies local Pi extensions from pi-extensions/
#   6. Generates .pi/mcp.json for pi-mcp-adapter from mcp.json
#
# All output stays within the repo (.pi/ directory).
# Run `make install` to propagate to ~/.pi/agent/.
#
# Usage:
#   ./sync-pi.sh          # Full sync
#   ./sync-pi.sh --check  # Dry-run: exit 0 if up-to-date, exit 1 if stale
#
# This script is idempotent: running it multiple times produces the same result.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="$SCRIPT_DIR/.claude-plugin/marketplace.json"
MCP_CONFIG="$SCRIPT_DIR/mcp.json"
EXT_SRC_DIR="$SCRIPT_DIR/pi-extensions"

PI_DIR="$SCRIPT_DIR/.pi"
SKILLS_DIR="$PI_DIR/skills"
PROMPTS_DIR="$PI_DIR/prompts"
AGENTS_DIR="$PI_DIR/agents"
EXTENSIONS_DIR="$PI_DIR/extensions"
PI_ADAPTER_CONFIG="$PI_DIR/mcp.json"

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_MODE=true
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# discover_plugins: prints one plugin source path per line (absolute)
discover_plugins() {
    python3 -c "
import json, os
data = json.load(open('$MARKETPLACE'))
for p in data['plugins']:
    print(os.path.join('$SCRIPT_DIR', p['source']))
"
}

# extract_frontmatter_field: read a YAML field from frontmatter (handles folded > values)
#   $1 = file path, $2 = field name
extract_frontmatter_field() {
    local file="$1" field="$2"
    awk -v field="$field" '
        /^---$/ { if (++fence == 2) exit; next }
        fence == 1 {
            if ($0 ~ "^" field ":") {
                val = $0
                sub("^" field ":[[:space:]]*>?[[:space:]]*", "", val)
                if (val != "") { print val; exit }
                while ((getline line) > 0) {
                    if (line ~ /^[[:space:]]/) {
                        sub(/^[[:space:]]+/, "", line)
                        print line
                        exit
                    } else { exit }
                }
            }
        }
    ' "$file"
}

# has_frontmatter_field: returns 0 if field exists within frontmatter, 1 otherwise
has_frontmatter_field() {
    local file="$1" field="$2"
    awk -v field="$field" '
        /^---$/ { if (++fence == 2) exit; next }
        fence == 1 && $0 ~ "^" field ":" { found = 1; exit }
        END { exit !found }
    ' "$file"
}

make_temp_dir() {
    mktemp -d 2>/dev/null || mktemp -d -p /private/tmp
}

# rewrite_body: apply body-text rewrites in-place (subagent refs, MCP adapter calls, plugin paths)
rewrite_body() {
    local file="$1"
    python3 - "$file" << 'PYEOF'
import ast
import json
import re
import sys

path = sys.argv[1]


def pi_mcp_tool_name(server: str, tool: str) -> str:
    return f'{server.replace("-", "_")}_{tool}'


def pi_agent_name(name: str) -> str:
    agent = name.strip().strip('"').strip("'")
    if ":" in agent:
        agent = agent.rsplit(":", 1)[1]
    return {
        "Explore": "explorer",
    }.get(agent, agent)


def split_top_level_args(text: str) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    quote: str | None = None
    escape = False
    for char in text:
        if quote:
            current.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == quote:
                quote = None
            continue
        if char in ("'", '"'):
            quote = char
            current.append(char)
            continue
        if char == ",":
            part = "".join(current).strip()
            if part:
                parts.append(part)
            current = []
            continue
        current.append(char)
    part = "".join(current).strip()
    if part:
        parts.append(part)
    return parts


def parse_arg_value(raw: str) -> object:
    value = raw.strip().rstrip(",").strip()
    if not value:
        return ""
    if value in ("true", "false"):
        return value == "true"
    if value == "null":
        return None
    if re.fullmatch(r"-?\d+", value):
        return int(value)
    if re.fullmatch(r"-?\d+\.\d+", value):
        return float(value)
    if value[0:1] in ("'", '"') and value[-1:] == value[0]:
        try:
            return ast.literal_eval(value)
        except Exception:
            return value[1:-1]
    return value


def parse_call_args(args_text: str) -> dict[str, object]:
    normalized = " ".join(line.strip() for line in args_text.splitlines()).strip()
    normalized = normalized.strip(",").strip()
    if not normalized:
        return {}

    parsed: dict[str, object] = {}
    for part in split_top_level_args(normalized):
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$", part)
        if not match:
            return {"raw": normalized}
        key, raw_value = match.groups()
        parsed[key] = parse_arg_value(raw_value)
    return parsed


def render_args_literal(args_text: str) -> str:
    payload = json.dumps(parse_call_args(args_text), separators=(",", ":"))
    return json.dumps(payload)


def render_mcp_call(
    indent: str,
    server: str,
    tool: str,
    args_text: str,
    suffix: str,
    newline: str,
    multiline: bool,
) -> str:
    tool_name = pi_mcp_tool_name(server, tool)
    args_literal = render_args_literal(args_text)
    if multiline:
        return (
            f'{indent}mcp({{\n'
            f'{indent}  tool: "{tool_name}",\n'
            f'{indent}  args: {args_literal}\n'
            f'{indent}}}){suffix}{newline}'
        )
    return f'{indent}mcp({{ tool: "{tool_name}", args: {args_literal} }}){suffix}{newline}'


def rewrite_mcp_call_blocks(text: str) -> str:
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    call_re = re.compile(r'^(\s*)mcp__([A-Za-z0-9_-]+)__([A-Za-z0-9_-]+)\((.*)$')

    while i < len(lines):
        line = lines[i]
        match = call_re.match(line)
        if not match:
            out.append(line)
            i += 1
            continue

        indent, server, tool, rest = match.groups()
        newline = "\n" if line.endswith("\n") else ""

        if ")" in rest:
            args, suffix = rest.split(")", 1)
            out.append(render_mcp_call(indent, server, tool, args, suffix, newline, multiline=False))
            i += 1
            continue

        i += 1
        arg_lines = []
        closing_newline = "\n"
        suffix = ""
        found_close = False
        while i < len(lines):
            arg_line = lines[i]
            if arg_line.strip().startswith(")"):
                closing_newline = "\n" if arg_line.endswith("\n") else ""
                suffix = arg_line.strip()[1:]
                found_close = True
                i += 1
                break
            arg_lines.append(arg_line)
            i += 1

        out.append(render_mcp_call(indent, server, tool, "".join(arg_lines), suffix, closing_newline, multiline=True))
        if not found_close:
            out.append("\n")

    return "".join(out)


def rewrite_inline_mcp_call(match: re.Match[str]) -> str:
    server, tool, args = match.groups()
    return render_mcp_call("", server, tool, args, "", "", multiline=False)


def rewrite_bare_mcp_tool(match: re.Match[str]) -> str:
    server, tool = match.groups()
    return f'mcp({{ tool: "{pi_mcp_tool_name(server, tool)}", args: "{{}}" }})'


text = open(path).read()

text = rewrite_mcp_call_blocks(text)
text = re.sub(
    r'\bmcp__([A-Za-z0-9_-]+)__([A-Za-z0-9_-]+)\(([^()\n]*)\)',
    rewrite_inline_mcp_call,
    text,
)
text = re.sub(
    r'\bmcp__([A-Za-z0-9_-]+)__([A-Za-z0-9_-]+)',
    rewrite_bare_mcp_tool,
    text,
)

text = re.sub(r'\bTask\(', 'subagent(', text)
text = re.sub(r'\bAgent\(', 'subagent(', text)
text = text.replace('"Task"', '"subagent"')
text = text.replace("'Task'", "'subagent'")
text = text.replace('`Task`', '`subagent`')
text = text.replace('Task tool', 'subagent tool')
text = text.replace('WebSearch and WebFetch', 'web_search')
text = text.replace('WebSearch/WebFetch', 'web_search')
text = text.replace('WebSearch or WebFetch', 'web_search')
text = text.replace('WebSearch', 'web_search')
text = text.replace('WebFetch', 'web_search')
text = text.replace('AskUserQuestion', 'ask_question')
text = re.sub(
    r'subagent_type\s*=\s*("[^"]+"|\'[^\']+\'|[A-Za-z0-9_-]+)',
    lambda m: f'agent = "{pi_agent_name(m.group(1))}"',
    text,
)
text = re.sub(r'\bprompt\s*=', 'task =', text)

text = re.sub(r'\$\{CLAUDE_PLUGIN_ROOT\}/skills/[^/]+/', './', text)
text = re.sub(r'\$CLAUDE_PLUGIN_ROOT/skills/[^/]+/', './', text)

with open(path, "w") as f:
    f.write(text)
PYEOF
}

# strip_pi_frontmatter: keep name, description, and disable-model-invocation only.
# Collapses multi-line descriptions to a single line. Truncates to 1024 chars
# at sentence boundary (agentskills.io limit).
strip_pi_frontmatter() {
    local file="$1"
    local tmpfile="${file}.tmp"
    python3 - "$file" "$tmpfile" << 'PYEOF'
import sys, re

src, dst = sys.argv[1], sys.argv[2]
lines = open(src).readlines()

fence_indices = [i for i, l in enumerate(lines) if l.strip() == '---']
if len(fence_indices) < 2:
    open(dst, 'w').writelines(lines)
    sys.exit(0)

fm_start, fm_end = fence_indices[0], fence_indices[1]
fm_lines = lines[fm_start + 1 : fm_end]
body_lines = lines[fm_end:]

fields = {}
current_field = None
for line in fm_lines:
    m = re.match(r'^([a-zA-Z][-a-zA-Z_]*)\s*:\s*(.*)', line)
    if m:
        current_field = m.group(1)
        val = m.group(2).strip().lstrip('>').strip()
        fields[current_field] = val
        continue
    if current_field and re.match(r'^[ \t]', line):
        prev = fields.get(current_field, '')
        piece = line.strip()
        fields[current_field] = (prev + ' ' + piece).strip() if prev else piece
        continue
    current_field = None

name = fields.get('name', '').strip('"').strip("'")
desc = fields.get('description', '').strip('"').strip("'")
disable_mi = fields.get('disable-model-invocation', '').strip().lower()

if len(desc) > 1024:
    truncated = desc[:1021].rsplit('.', 1)[0] + '.'
    if len(truncated) < 20:
        truncated = desc[:1021] + '...'
    desc = truncated

name_escaped = name.replace('"', '\\"')
desc_escaped = desc.replace('"', '\\"')

with open(dst, 'w') as f:
    f.write('---\n')
    f.write(f'name: "{name_escaped}"\n')
    f.write(f'description: "{desc_escaped}"\n')
    if disable_mi in ('true', 'yes', '1'):
        f.write('disable-model-invocation: true\n')
    f.write('---\n')
    for line in body_lines[1:]:
        f.write(line)
PYEOF
    mv "$tmpfile" "$file"
}

# generate_prompt: write .pi/prompts/<name>.md for a user-invocable skill.
# Pi prompt templates have no frontmatter -- just Markdown body with optional {{var}}.
generate_prompt() {
    local src_skill="$1" dest_prompt="$2"

    local skill_name short_desc
    skill_name=$(extract_frontmatter_field "$src_skill" "name")
    short_desc=$(extract_frontmatter_field "$src_skill" "description" | sed 's/\. .*/\./')

    cat > "$dest_prompt" <<PROMPTEOF
<!-- $short_desc -->

Use the \`$skill_name\` skill to handle this request: \$ARGUMENTS
PROMPTEOF
}

# normalize_agent_frontmatter: pass agent files through, but rename allowed_tools -> tools
# (pi-subagents convention) and drop fields that don't survive the trip.
normalize_agent_frontmatter() {
    local file="$1"
    local tmpfile="${file}.tmp"
    python3 - "$file" "$tmpfile" << 'PYEOF'
import ast
import json
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
lines = open(src).readlines()

fence_indices = [i for i, l in enumerate(lines) if l.strip() == '---']
if len(fence_indices) < 2:
    open(dst, 'w').writelines(lines)
    sys.exit(0)

fm_start, fm_end = fence_indices[0], fence_indices[1]
fm_lines = lines[fm_start + 1 : fm_end]
body_lines = lines[fm_end:]


def normalize_tool_name(tool: str) -> str:
    if tool.startswith("mcp__"):
        return "mcp"
    return {
        "Task": "subagent",
        "Agent": "subagent",
        "AskUserQuestion": "ask_question",
        "WebSearch": "web_search",
        "WebFetch": "web_search",
    }.get(tool, tool)


def normalize_tool_list(value: str) -> str:
    raw = value.strip()
    if not raw:
        return raw
    try:
        parsed = ast.literal_eval(raw)
    except Exception:
        parsed = [piece.strip().strip('"').strip("'") for piece in raw.split(",")]
    if not isinstance(parsed, list):
        parsed = [str(parsed)]

    tools: list[str] = []
    seen: set[str] = set()
    for item in parsed:
        tool = normalize_tool_name(str(item).strip())
        if not tool or tool in seen:
            continue
        seen.add(tool)
        tools.append(tool)
    return json.dumps(tools)


out_fm = []
skip_continuation = False
for line in fm_lines:
    if skip_continuation and re.match(r'^[ \t]', line):
        continue
    skip_continuation = False
    m = re.match(r'^([a-zA-Z][-a-zA-Z_]*)\s*:', line)
    if m:
        field = m.group(1)
        if field == 'allowed_tools':
            out_fm.append('tools: ' + normalize_tool_list(line[len('allowed_tools:'):]) + '\n')
            continue
        if field == 'tools':
            out_fm.append('tools: ' + normalize_tool_list(line[len('tools:'):]) + '\n')
            continue
        if field == 'hooks':
            skip_continuation = True
            continue
    out_fm.append(line)

with open(dst, 'w') as f:
    f.write('---\n')
    f.writelines(out_fm)
    f.writelines(body_lines)
PYEOF
    mv "$tmpfile" "$file"
}

# generate_pi_mcp_config: emit .pi/mcp.json for pi-mcp-adapter from mcp.json.
# Keep this HTTP-only and proxy-only; no stdio commands, imports, direct tools,
# or sampling auto-approval are generated by code-factory.
generate_pi_mcp_config() {
    local out_file="$1"
    python3 - "$MCP_CONFIG" "$out_file" << 'PYEOF'
import json
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))

servers = {}
for name, cfg in sorted(data.get('mcpServers', {}).items()):
    if cfg.get('type') != 'http':
        continue
    server = {
        'url': cfg['url'],
        'lifecycle': 'lazy',
        'directTools': False,
    }
    oauth = cfg.get('oauth')
    if oauth:
        server['auth'] = 'oauth'
        adapter_oauth = {}
        if oauth.get('clientId'):
            adapter_oauth['clientId'] = oauth['clientId']
        if oauth.get('callbackPort'):
            adapter_oauth['redirectUri'] = f"http://localhost:{oauth['callbackPort']}/callback"
        if adapter_oauth:
            server['oauth'] = adapter_oauth
    servers[name] = server

out = {
    'settings': {
        'directTools': False,
        'idleTimeout': 10,
        'autoAuth': False,
        'samplingAutoApprove': False,
    },
    'mcpServers': servers,
}

os.makedirs(os.path.dirname(dst), exist_ok=True)
with open(dst, 'w') as f:
    json.dump(out, f, indent=2)
    f.write('\n')
PYEOF
}

# build_extensions: copy every directory under pi-extensions/ into
# .pi/extensions/<name>/.
build_extensions() {
    [[ -d "$EXT_SRC_DIR" ]] || return 0

    for ext_src in "$EXT_SRC_DIR"/*/; do
        [[ -d "$ext_src" ]] || continue
        local name
        name=$(basename "$ext_src")
        local out_dir="$EXTENSIONS_DIR/$name"

        mkdir -p "$out_dir"
        cp -R "$ext_src." "$out_dir/"

        if [[ "$CHECK_MODE" != "true" ]]; then
            echo "  SYNC  extension: $name"
        fi
    done
}

# write_builtin_general_purpose_agent: Pi skills commonly delegate broad
# writing/implementation work to Claude's general-purpose agent. Pi needs a
# concrete local agent for those calls instead of aliasing them to explorer.
write_builtin_general_purpose_agent() {
    cat > "$AGENTS_DIR/general-purpose.md" << 'EOF'
---
name: general-purpose
description: "General-purpose agent for broad research, writing, implementation, and coordination tasks when no specialized agent is required."
tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash", "Skill", "subagent", "ask_question"]
---
# General Purpose Agent

You are a general-purpose execution agent for Pi workflows.

Take the requested task literally. You may research, write documents, edit files,
run local validation commands, and coordinate with other tools when the task
requires it. Preserve user changes you did not make, keep edits scoped to the
task, and report concise outcomes with any validation performed.

Use `ask_question` only when required information cannot be inferred from the
task or local context. If the task includes an output path, create or update that
path directly.
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local skill_count=0 prompt_count=0 agent_count=0

    if [[ "$CHECK_MODE" == "true" ]]; then
        local tmpdir
        tmpdir=$(make_temp_dir)
        # Expand $tmpdir at trap-set time: it is `local` to main(), so the trap
        # cannot resolve it later when EXIT fires after main() returns.
        trap "rm -rf '$tmpdir'" EXIT
        local real_skills_dir="$SKILLS_DIR"
        local real_prompts_dir="$PROMPTS_DIR"
        local real_agents_dir="$AGENTS_DIR"
        local real_extensions_dir="$EXTENSIONS_DIR"
        local real_pi_mcp_config="$PI_ADAPTER_CONFIG"
        SKILLS_DIR="$tmpdir/skills"
        PROMPTS_DIR="$tmpdir/prompts"
        AGENTS_DIR="$tmpdir/agents"
        EXTENSIONS_DIR="$tmpdir/extensions"
        PI_ADAPTER_CONFIG="$tmpdir/mcp.json"
    else
        rm -rf "$SKILLS_DIR" "$PROMPTS_DIR" "$AGENTS_DIR" "$EXTENSIONS_DIR"
        rm -f "$PI_ADAPTER_CONFIG"
    fi

    mkdir -p "$SKILLS_DIR" "$PROMPTS_DIR" "$AGENTS_DIR" "$EXTENSIONS_DIR"

    while IFS= read -r plugin_dir; do
        [[ -d "$plugin_dir" ]] || continue

        # --- Skills ---
        if [[ -d "$plugin_dir/skills" ]]; then
            while IFS= read -r skill_path; do
                local skill_name skill_src_dir
                skill_name=$(basename "$(dirname "$skill_path")")
                skill_src_dir=$(dirname "$skill_path")

                cp -R "$skill_src_dir" "$SKILLS_DIR/$skill_name"
                strip_pi_frontmatter "$SKILLS_DIR/$skill_name/SKILL.md"
                while IFS= read -r markdown_path; do
                    rewrite_body "$markdown_path"
                done < <(find "$SKILLS_DIR/$skill_name" -type f -name "*.md" 2>/dev/null | sort)

                skill_count=$((skill_count + 1))
                [[ "$CHECK_MODE" != "true" ]] && echo "  SYNC  skill: $skill_name"

                # --- Prompt (slash command) ---
                if has_frontmatter_field "$skill_path" "user-invocable"; then
                    local user_inv
                    user_inv=$(extract_frontmatter_field "$skill_path" "user-invocable")
                    if [[ "$user_inv" == "true" ]]; then
                        generate_prompt "$skill_path" "$PROMPTS_DIR/$skill_name.md"
                        prompt_count=$((prompt_count + 1))
                        [[ "$CHECK_MODE" != "true" ]] && echo "  SYNC  prompt: $skill_name"
                    fi
                fi
            done < <(find "$plugin_dir/skills" -name "SKILL.md" 2>/dev/null | sort)
        fi

        # --- Agents ---
        if [[ -d "$plugin_dir/agents" ]]; then
            while IFS= read -r agent_path; do
                local agent_name
                agent_name=$(basename "$agent_path" .md)
                cp "$agent_path" "$AGENTS_DIR/$agent_name.md"
                normalize_agent_frontmatter "$AGENTS_DIR/$agent_name.md"
                rewrite_body "$AGENTS_DIR/$agent_name.md"

                agent_count=$((agent_count + 1))
                [[ "$CHECK_MODE" != "true" ]] && echo "  SYNC  agent: $agent_name"
            done < <(find "$plugin_dir/agents" -name "*.md" 2>/dev/null | sort)
        fi
    done < <(discover_plugins)

    write_builtin_general_purpose_agent
    agent_count=$((agent_count + 1))
    [[ "$CHECK_MODE" != "true" ]] && echo "  SYNC  agent: general-purpose"

    # --- Extensions and MCP adapter config ---
    build_extensions
    generate_pi_mcp_config "$PI_ADAPTER_CONFIG"
    [[ "$CHECK_MODE" != "true" ]] && echo "  SYNC  mcp config: mcp.json"

    if [[ "$CHECK_MODE" == "true" ]]; then
        local stale=false
        for dir_pair in \
            "$SKILLS_DIR:$real_skills_dir" \
            "$PROMPTS_DIR:$real_prompts_dir" \
            "$AGENTS_DIR:$real_agents_dir" \
            "$EXTENSIONS_DIR:$real_extensions_dir"; do
            local tmp_dir="${dir_pair%%:*}"
            local real_dir="${dir_pair##*:}"

            if [[ ! -d "$real_dir" ]]; then
                echo "STALE  $real_dir does not exist (run ./sync-pi.sh)"
                stale=true
                continue
            fi

            if ! diff -rq "$tmp_dir" "$real_dir" > /dev/null 2>&1; then
                diff -rq "$tmp_dir" "$real_dir" 2>&1 | while IFS= read -r line; do
                    echo "STALE  $line"
                done
                stale=true
            fi
        done

        if [[ ! -f "$real_pi_mcp_config" ]]; then
            echo "STALE  $real_pi_mcp_config does not exist (run ./sync-pi.sh)"
            stale=true
        elif ! cmp -s "$PI_ADAPTER_CONFIG" "$real_pi_mcp_config"; then
            echo "STALE  $real_pi_mcp_config differs (run ./sync-pi.sh)"
            stale=true
        fi

        if [[ "$stale" == "true" ]]; then
            exit 1
        fi

        echo "Pi sync is up-to-date."
        exit 0
    fi

    echo ""
    echo "Synced $skill_count skills, $prompt_count prompts, $agent_count agents."
}

main
