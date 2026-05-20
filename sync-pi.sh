#!/usr/bin/env bash
#
# sync-pi.sh -- Generate pi.dev-compatible skills, prompts, agents, and MCP extension.
#
# This script:
#   1. Discovers plugins from .claude-plugin/marketplace.json
#   2. Copies skills (with body rewrites + stripped frontmatter) to .pi/skills/{name}/SKILL.md
#   3. Generates .pi/prompts/{name}.md for every user-invocable skill
#   4. Transforms agent Markdown files to .pi/agents/{name}.md
#   5. Builds .pi/extensions/mcp-wrapper/ (TS source + servers.json from mcp.json)
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

# rewrite_body: apply body-text rewrites in-place (subagent refs, mcp tool names, plugin paths)
rewrite_body() {
    local file="$1"
    local sed_i
    if sed --version 2>/dev/null | grep -q 'GNU'; then
        sed_i=(-i)
    else
        sed_i=(-i '')
    fi
    sed "${sed_i[@]}" 's/subagent_type = "\([^:]*\):\([^"]*\)"/subagent = "\2"/g' "$file"
    sed "${sed_i[@]}" 's/subagent_type="\([^:]*\):\([^"]*\)"/subagent="\2"/g' "$file"
    sed "${sed_i[@]}" 's/subagent_type=\([A-Za-z0-9_-]*\)/subagent=\1/g' "$file"
    sed "${sed_i[@]}" 's/mcp__\([^_]*\)__/\1_/g' "$file"
    sed "${sed_i[@]}" 's|\${CLAUDE_PLUGIN_ROOT}/skills/[^/]*/|./|g' "$file"
    sed "${sed_i[@]}" 's|\$CLAUDE_PLUGIN_ROOT/skills/[^/]*/|./|g' "$file"
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

Use the \`$skill_name\` skill to handle this request: {{args}}
PROMPTEOF
}

# normalize_agent_frontmatter: pass agent files through, but rename allowed_tools -> tools
# (pi-subagents convention) and drop fields that don't survive the trip.
normalize_agent_frontmatter() {
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
            out_fm.append('tools:' + line[len('allowed_tools:'):])
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

# generate_mcp_servers_json: emit .pi/extensions/mcp-wrapper/servers.json from
# mcp.json (HTTP servers only for v1).
generate_mcp_servers_json() {
    local out_file="$1"
    python3 - "$MCP_CONFIG" "$out_file" << 'PYEOF'
import json, sys

src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))

servers = []
for name, cfg in sorted(data.get('mcpServers', {}).items()):
    if cfg.get('type') != 'http':
        continue
    servers.append({
        'name': name,
        'url': cfg['url'],
        'oauth': cfg.get('oauth'),
    })

with open(dst, 'w') as f:
    json.dump({'servers': servers}, f, indent=2)
    f.write('\n')
PYEOF
}

# build_extensions: copy every directory under pi-extensions/ into
# .pi/extensions/<name>/, then run extension-specific post-steps.
build_extensions() {
    [[ -d "$EXT_SRC_DIR" ]] || return 0

    for ext_src in "$EXT_SRC_DIR"/*/; do
        [[ -d "$ext_src" ]] || continue
        local name
        name=$(basename "$ext_src")
        local out_dir="$EXTENSIONS_DIR/$name"

        mkdir -p "$out_dir"
        cp -R "$ext_src." "$out_dir/"

        case "$name" in
            mcp-wrapper) generate_mcp_servers_json "$out_dir/servers.json" ;;
        esac

        if [[ "$CHECK_MODE" != "true" ]]; then
            echo "  SYNC  extension: $name"
        fi
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local skill_count=0 prompt_count=0 agent_count=0

    if [[ "$CHECK_MODE" == "true" ]]; then
        local tmpdir
        tmpdir=$(mktemp -d)
        # Expand $tmpdir at trap-set time: it is `local` to main(), so the trap
        # cannot resolve it later when EXIT fires after main() returns.
        trap "rm -rf '$tmpdir'" EXIT
        local real_skills_dir="$SKILLS_DIR"
        local real_prompts_dir="$PROMPTS_DIR"
        local real_agents_dir="$AGENTS_DIR"
        local real_extensions_dir="$EXTENSIONS_DIR"
        SKILLS_DIR="$tmpdir/skills"
        PROMPTS_DIR="$tmpdir/prompts"
        AGENTS_DIR="$tmpdir/agents"
        EXTENSIONS_DIR="$tmpdir/extensions"
    else
        rm -rf "$SKILLS_DIR" "$PROMPTS_DIR" "$AGENTS_DIR" "$EXTENSIONS_DIR"
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
                rewrite_body "$SKILLS_DIR/$skill_name/SKILL.md"

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

    # --- Extensions (mcp-wrapper, subagent-runner, etc.) ---
    build_extensions

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
