#!/usr/bin/env bash
#
# sync-codex.sh -- Generate Codex-compatible skills and agents from plugins.
#
# This script:
#   1. Discovers plugins from .claude-plugin/marketplace.json
#   2. Copies skills (with body rewrites + stripped frontmatter) to .codex/skills/{name}/SKILL.md
#   3. Generates agents/openai.yaml per skill with UI metadata
#   4. Transforms agent Markdown files to .codex/agents/{name}.toml
#
# All output stays within the repo (.codex/ directory).
# Run `make install` to propagate to ~/.codex/.
#
# Usage:
#   ./sync-codex.sh          # Full sync
#   ./sync-codex.sh --check  # Dry-run: exit 0 if up-to-date, exit 1 if stale
#
# This script is idempotent: running it multiple times produces the same result.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="$SCRIPT_DIR/.claude-plugin/marketplace.json"

CODEX_DIR="$SCRIPT_DIR/.codex"
SKILLS_DIR="$CODEX_DIR/skills"
AGENTS_DIR="$CODEX_DIR/agents"

CHECK_MODE=false
if [[ "${1:-}" == "--check" ]]; then
    CHECK_MODE=true
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# discover_plugins: prints one plugin source path per line (relative to repo root)
discover_plugins() {
    python3 -c "
import json, os
data = json.load(open('$MARKETPLACE'))
for p in data['plugins']:
    print(os.path.join('$SCRIPT_DIR', p['source']))
"
}

# extract_frontmatter_field: extract a field value from YAML frontmatter
#   $1 = file path, $2 = field name
#   Handles both single-line and multi-line (folded >) YAML values.
extract_frontmatter_field() {
    local file="$1" field="$2"
    awk -v field="$field" '
        /^---$/ { if (++fence == 2) exit; next }
        fence == 1 {
            # Match the target field
            if ($0 ~ "^" field ":") {
                val = $0
                sub("^" field ":[[:space:]]*>?[[:space:]]*", "", val)
                if (val != "") { print val; exit }
                # Multi-line: read continuation lines
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

# has_frontmatter_field: check if a field exists in YAML frontmatter
#   $1 = file path, $2 = field name
#   Only matches within --- fences (not in body text).
has_frontmatter_field() {
    local file="$1" field="$2"
    awk -v field="$field" '
        /^---$/ { if (++fence == 2) exit; next }
        fence == 1 && $0 ~ "^" field ":" { found = 1; exit }
        END { exit !found }
    ' "$file"
}

# rewrite_body: apply body-text rewrites to a file in-place
#   $1 = file path
rewrite_body() {
    local file="$1"
    # Portable in-place sed: GNU sed uses -i, BSD sed uses -i ''
    local sed_i=(-i)
    if sed --version 2>/dev/null | grep -q 'GNU'; then
        sed_i=(-i)
    else
        sed_i=(-i '')
    fi
    # subagent_type = "plugin:name" -> subagent = "name" (quoted, plugin-prefixed)
    sed "${sed_i[@]}" 's/subagent_type = "\([^:]*\):\([^"]*\)"/subagent = "\2"/g' "$file"
    # subagent_type="plugin:name" -> subagent="name" (no spaces variant)
    sed "${sed_i[@]}" 's/subagent_type="\([^:]*\):\([^"]*\)"/subagent="\2"/g' "$file"
    # subagent_type=Name -> subagent=Name (unquoted built-in agent)
    sed "${sed_i[@]}" 's/subagent_type=\([A-Za-z0-9_-]*\)/subagent=\1/g' "$file"
    # MCP tool name references: mcp__<server>__<tool> -> <server>_<tool>
    sed "${sed_i[@]}" 's/mcp__\([^_]*\)__/\1_/g' "$file"
    # CLAUDE_PLUGIN_ROOT paths: ${CLAUDE_PLUGIN_ROOT}/skills/<name>/<rest> -> ./<rest>
    # Handles both ${CLAUDE_PLUGIN_ROOT} and $CLAUDE_PLUGIN_ROOT forms
    sed "${sed_i[@]}" 's|\${CLAUDE_PLUGIN_ROOT}/skills/[^/]*/|./|g' "$file"
    sed "${sed_i[@]}" 's|\$CLAUDE_PLUGIN_ROOT/skills/[^/]*/|./|g' "$file"
}

# strip_codex_frontmatter: rewrite SKILL.md frontmatter to Codex format
#   - Keeps only name and description fields
#   - Collapses multi-line values into single-line quoted strings
#   - Truncates description to 1024 chars (Codex limit)
#   $1 = file path (modified in-place)
strip_codex_frontmatter() {
    local file="$1"
    local tmpfile="${file}.tmp"
    python3 - "$file" "$tmpfile" << 'PYEOF'
import sys, re

src, dst = sys.argv[1], sys.argv[2]
lines = open(src).readlines()

# --- Parse frontmatter ---
fence_indices = [i for i, l in enumerate(lines) if l.strip() == '---']
if len(fence_indices) < 2:
    # No valid frontmatter; copy as-is
    open(dst, 'w').writelines(lines)
    sys.exit(0)

fm_start, fm_end = fence_indices[0], fence_indices[1]
fm_lines = lines[fm_start + 1 : fm_end]
body_lines = lines[fm_end:]  # includes closing ---

# --- Extract fields from frontmatter ---
fields = {}
current_field = None
for line in fm_lines:
    # Top-level field
    m = re.match(r'^([a-zA-Z][-a-zA-Z_]*)\s*:\s*(.*)', line)
    if m:
        current_field = m.group(1)
        val = m.group(2).strip().lstrip('>').strip()
        fields[current_field] = val
        continue
    # Continuation line (indented)
    if current_field and re.match(r'^[ \t]', line):
        prev = fields.get(current_field, '')
        piece = line.strip()
        if prev:
            fields[current_field] = prev + ' ' + piece
        else:
            fields[current_field] = piece
        continue
    current_field = None

# --- Keep only name and description ---
name = fields.get('name', '').strip('"').strip("'")
desc = fields.get('description', '').strip('"').strip("'")

# Truncate description to 1024 chars at sentence boundary
if len(desc) > 1024:
    truncated = desc[:1021].rsplit('.', 1)[0] + '.'
    if len(truncated) < 20:
        truncated = desc[:1021] + '...'
    desc = truncated

# Escape internal double quotes
name_escaped = name.replace('"', '\\"')
desc_escaped = desc.replace('"', '\\"')

# --- Write output ---
with open(dst, 'w') as f:
    f.write('---\n')
    f.write(f'name: "{name_escaped}"\n')
    f.write(f'description: "{desc_escaped}"\n')
    f.write('---\n')
    # Write body (starts with the closing --- which we already wrote, skip it)
    # body_lines[0] is '---\n', skip it
    for line in body_lines[1:]:
        f.write(line)
PYEOF
    mv "$tmpfile" "$file"
}

# generate_openai_yaml: create agents/openai.yaml for a Codex skill
#   $1 = source SKILL.md (original, pre-transform)
#   $2 = destination directory (the skill output dir)
#   Uses Python to handle YAML quoting and smart prompt generation.
generate_openai_yaml() {
    local src="$1" dest_dir="$2"

    local skill_name
    skill_name=$(extract_frontmatter_field "$src" "name")

    local skill_desc
    skill_desc=$(extract_frontmatter_field "$src" "description")

    mkdir -p "$dest_dir/agents"

    python3 - "$skill_name" "$skill_desc" "$dest_dir/agents/openai.yaml" << 'PYEOF'
import sys, re

name, desc, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

# Display name: hyphen-to-space, title case
display_name = name.replace('-', ' ').title()

# Short description: first sentence, max 80 chars
short = desc.split('. ')[0]
if not short.endswith('.'):
    short += '.'
if len(short) > 80:
    short = short[:77] + '...'

# Default prompt: convert description to an imperative action
action = desc
# Strip common description prefixes to get the action
prefixes = [
    r'^Use when the user wants to\s+',
    r'^Use when the user asks to\s+',
    r'^Use when the user says\s+',
    r'^Use when the user needs to\s+',
    r'^Use when the user\s+',
    r'^Use when user says\s+',
    r'^Use when user wants to\s+',
    r'^Use when user asks to\s+',
    r'^Use when user\s+',
    r'^Use when encountering\s+',
    r'^Use when reviewing\s+',
    r'^Use when\s+',
]
for prefix in prefixes:
    m = re.match(prefix, action, re.IGNORECASE)
    if m:
        action = action[m.end():]
        break

# Truncate action to first sentence or 120 chars
first_sentence = action.split('. ')[0]
if not first_sentence.endswith('.'):
    first_sentence += '.'
if len(first_sentence) > 120:
    first_sentence = first_sentence[:117] + '...'
action = first_sentence

prompt = f'Use ${name} to {action}'

# Escape for YAML double-quoted scalars: backslash then double-quote
def yaml_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')

with open(out_path, 'w') as f:
    f.write('interface:\n')
    f.write(f'  display_name: "{yaml_escape(display_name)}"\n')
    f.write(f'  short_description: "{yaml_escape(short)}"\n')
    f.write(f'  default_prompt: "{yaml_escape(prompt)}"\n')
PYEOF
}

# transform_agent_to_toml: convert Claude Code agent .md to Codex .toml
#   $1 = source agent file, $2 = destination .toml file
transform_agent_to_toml() {
    local src="$1" dest="$2"

    local name
    name=$(extract_frontmatter_field "$src" "name")
    # Strip surrounding quotes from YAML value
    name=$(echo "$name" | sed 's/^"//;s/"$//')

    local desc
    desc=$(extract_frontmatter_field "$src" "description")
    # Strip surrounding quotes from YAML value
    desc=$(echo "$desc" | sed 's/^"//;s/"$//')
    # Escape internal double quotes for TOML
    desc=$(echo "$desc" | sed 's/"/\\"/g')

    # Extract body: everything after the second ---
    local body
    body=$(awk '
        /^---$/ { fence++; if (fence == 2) { body=1; next } next }
        body { print }
    ' "$src")

    # Escape any literal triple single-quotes in body (rare but defensive)
    body=$(printf '%s' "$body" | sed "s/'''/'''\"'''\"'''/g")

    # Write TOML — developer_instructions is a flat string, not a table.
    # Use TOML literal strings (''') to avoid backslash escape issues.
    {
        printf 'name = "%s"\n' "$name"
        printf 'description = "%s"\n' "$desc"
        printf 'model_reasoning_effort = "high"\n'
        printf "developer_instructions = '''\n"
        printf '%s\n' "$body"
        printf "'''\n"
    } > "$dest"

    # Validate: check required fields exist
    if ! head -5 "$dest" | grep -q '^name = ' 2>/dev/null; then
        echo "  ERROR  $(basename "$src") -- transformed output missing name, skipping" >&2
        rm -f "$dest"
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local skill_count=0
    local agent_count=0

    # --check mode: sync to temp dirs and compare
    if [[ "$CHECK_MODE" == "true" ]]; then
        local tmpdir
        tmpdir=$(mktemp -d)
        # Expand $tmpdir at trap-set time: it is `local` to main(), so the trap
        # cannot resolve it later when EXIT fires after main() returns.
        trap "rm -rf '$tmpdir'" EXIT

        # Override output dirs to temp
        local real_skills_dir="$SKILLS_DIR"
        local real_agents_dir="$AGENTS_DIR"
        SKILLS_DIR="$tmpdir/skills"
        AGENTS_DIR="$tmpdir/agents"
    else
        # Clear and regenerate
        rm -rf "$SKILLS_DIR" "$AGENTS_DIR"
    fi

    mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

    # Discover and sync
    while IFS= read -r plugin_dir; do
        [[ -d "$plugin_dir" ]] || continue

        # --- Skills ---
        if [[ -d "$plugin_dir/skills" ]]; then
            while IFS= read -r skill_path; do
                local skill_name skill_src_dir
                skill_name=$(basename "$(dirname "$skill_path")")
                skill_src_dir=$(dirname "$skill_path")

                # Copy entire skill directory (SKILL.md, references/, scripts/)
                cp -R "$skill_src_dir" "$SKILLS_DIR/$skill_name"

                # Generate agents/openai.yaml from original source metadata
                generate_openai_yaml "$skill_path" "$SKILLS_DIR/$skill_name"

                # Strip Claude-specific frontmatter, collapse to single-line quoted values
                strip_codex_frontmatter "$SKILLS_DIR/$skill_name/SKILL.md"

                # Apply body rewrites
                rewrite_body "$SKILLS_DIR/$skill_name/SKILL.md"

                skill_count=$((skill_count + 1))

                if [[ "$CHECK_MODE" != "true" ]]; then
                    echo "  SYNC  skill: $skill_name"
                fi
            done < <(find "$plugin_dir/skills" -name "SKILL.md" 2>/dev/null | sort)
        fi

        # --- Agents ---
        if [[ -d "$plugin_dir/agents" ]]; then
            while IFS= read -r agent_path; do
                local agent_name
                agent_name=$(basename "$agent_path" .md)
                if transform_agent_to_toml "$agent_path" "$AGENTS_DIR/$agent_name.toml"; then
                    rewrite_body "$AGENTS_DIR/$agent_name.toml"

                    agent_count=$((agent_count + 1))

                    if [[ "$CHECK_MODE" != "true" ]]; then
                        echo "  SYNC  agent: $agent_name"
                    fi
                fi
            done < <(find "$plugin_dir/agents" -name "*.md" 2>/dev/null | sort)
        fi

    done < <(discover_plugins)

    # --check mode: compare temp output against real output
    if [[ "$CHECK_MODE" == "true" ]]; then
        local stale=false

        # Compare generated dirs recursively
        for dir_pair in "$SKILLS_DIR:$real_skills_dir" "$AGENTS_DIR:$real_agents_dir"; do
            local tmp_dir="${dir_pair%%:*}"
            local real_dir="${dir_pair##*:}"

            if [[ ! -d "$real_dir" ]]; then
                echo "STALE  $real_dir does not exist (run ./sync-codex.sh)"
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

        echo "Codex sync is up-to-date."
        exit 0
    fi

    echo ""
    echo "Synced $skill_count skills, $agent_count agents."
}

main
