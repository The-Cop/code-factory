#!/usr/bin/env bash
#
# sync-opencode.sh -- Generate OpenCode-compatible skills, agents, and commands from plugins.
#
# This script:
#   1. Discovers plugins from .claude-plugin/marketplace.json
#   2. Copies skills (with body rewrites) to .opencode/skills/{name}/SKILL.md
#   3. Transforms agent frontmatter and copies to .opencode/agents/{name}.md
#   4. Generates .opencode/commands/{name}.md for user-invocable skills
#
# All output stays within the repo (.opencode/ directory).
# Run `make install` to propagate to ~/.config/opencode/.
#
# Usage:
#   ./sync-opencode.sh          # Full sync
#   ./sync-opencode.sh --check  # Dry-run: exit 0 if up-to-date, exit 1 if stale
#
# This script is idempotent: running it multiple times produces the same result.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE="$SCRIPT_DIR/.claude-plugin/marketplace.json"

OPENCODE_DIR="$SCRIPT_DIR/.opencode"
SKILLS_DIR="$OPENCODE_DIR/skills"
AGENTS_DIR="$OPENCODE_DIR/agents"
COMMANDS_DIR="$OPENCODE_DIR/commands"

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

# transform_agent: transform Claude Code agent to OpenCode format
#   $1 = source agent file, $2 = destination file
transform_agent() {
    local src="$1" dest="$2"

    awk '
    BEGIN { in_fm = 0; fence = 0; done_fm = 0 }

    # Track frontmatter boundaries
    /^---$/ {
        fence++
        if (fence == 1) {
            in_fm = 1
            print
            next
        }
        if (fence == 2) {
            # Insert mode: subagent before closing ---
            print "mode: subagent"
            # Print collected tools block
            if (tools_count > 0) {
                print "tools:"
                for (i = 1; i <= tools_count; i++) {
                    print "  " tools_list[i] ": true"
                }
            }
            in_fm = 0
            done_fm = 1
            print
            next
        }
    }

    # Inside frontmatter: transform fields
    in_fm == 1 {
        # Model alias expansion
        if ($0 ~ /^model:/) {
            gsub(/"opus"/, "\"anthropic/claude-opus-4-6\"")
            gsub(/"sonnet"/, "\"anthropic/claude-sonnet-4-5\"")
            gsub(/"haiku"/, "\"anthropic/claude-haiku-4-5\"")
            print
            next
        }

        # Convert allowed_tools array to tools map (collected, printed before closing ---)
        if ($0 ~ /^allowed_tools:/) {
            # Extract the JSON array content
            line = $0
            sub(/^allowed_tools:[[:space:]]*\[/, "", line)
            sub(/\][[:space:]]*$/, "", line)
            # Split by comma
            n = split(line, items, ",")
            tools_count = 0
            for (i = 1; i <= n; i++) {
                tool = items[i]
                # Strip quotes and whitespace
                gsub(/[[:space:]"'\'']+/, "", tool)
                if (tool == "") continue

                # Map tool names
                if (tool == "AskUserQuestion") {
                    tools_count++
                    tools_list[tools_count] = "question"
                } else if (tool ~ /^mcp__/) {
                    # Strip mcp__ prefix, replace __ with _
                    mapped = tool
                    sub(/^mcp__/, "", mapped)
                    gsub(/__/, "_", mapped)
                    tools_count++
                    tools_list[tools_count] = mapped
                } else {
                    tools_count++
                    tools_list[tools_count] = tolower(tool)
                }
            }
            next
        }

        # Pass through other frontmatter lines (name, description, etc.)
        print
        next
    }

    # Body text (after frontmatter): print as-is
    done_fm == 1 { print }
    ' "$src" > "$dest"

    # Validate transformed output
    local valid=true
    for field in "name:" "description:" "mode:" "tools:"; do
        if ! head -30 "$dest" | grep -q "^${field}" 2>/dev/null; then
            # tools: may be absent if agent had no allowed_tools
            if [[ "$field" == "tools:" ]]; then continue; fi
            valid=false
        fi
    done
    if [[ "$valid" != "true" ]]; then
        echo "  ERROR  $(basename "$src") -- transformed output missing required fields, skipping" >&2
        rm -f "$dest"
        return 1
    fi

    return 0
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

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    local skill_count=0
    local agent_count=0
    local command_count=0

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
        local real_commands_dir="$COMMANDS_DIR"
        SKILLS_DIR="$tmpdir/skills"
        AGENTS_DIR="$tmpdir/agents"
        COMMANDS_DIR="$tmpdir/commands"
    else
        # Clear and regenerate — no manifest needed since output is in-repo
        rm -rf "$SKILLS_DIR" "$AGENTS_DIR" "$COMMANDS_DIR"
    fi

    mkdir -p "$SKILLS_DIR" "$AGENTS_DIR" "$COMMANDS_DIR"

    # Discover and sync
    while IFS= read -r plugin_dir; do
        [[ -d "$plugin_dir" ]] || continue

        # --- Skills ---
        if [[ -d "$plugin_dir/skills" ]]; then
            while IFS= read -r skill_path; do
                local skill_name skill_src_dir
                skill_name=$(basename "$(dirname "$skill_path")")
                skill_src_dir=$(dirname "$skill_path")
                cp -R "$skill_src_dir" "$SKILLS_DIR/$skill_name"
                rewrite_body "$SKILLS_DIR/$skill_name/SKILL.md"

                skill_count=$((skill_count + 1))

                if [[ "$CHECK_MODE" != "true" ]]; then
                    echo "  SYNC  skill: $skill_name"
                fi

                # --- Commands (for user-invocable skills) ---
                if has_frontmatter_field "$skill_path" "user-invocable"; then
                    local desc
                    desc=$(extract_frontmatter_field "$skill_path" "description")
                    # Truncate multi-sentence descriptions to first sentence
                    desc=$(echo "$desc" | sed 's/\. .*/\./')

                    cat > "$COMMANDS_DIR/$skill_name.md" <<CMDEOF
---
description: >
  $desc
---

Invoke the \`$skill_name\` skill with explicit syntax:

skill({ name: "$skill_name" })
CMDEOF

                    command_count=$((command_count + 1))

                    if [[ "$CHECK_MODE" != "true" ]]; then
                        echo "  SYNC  command: $skill_name"
                    fi
                fi
            done < <(find "$plugin_dir/skills" -name "SKILL.md" 2>/dev/null | sort)
        fi

        # --- Agents ---
        if [[ -d "$plugin_dir/agents" ]]; then
            while IFS= read -r agent_path; do
                local agent_name
                agent_name=$(basename "$agent_path" .md)
                if transform_agent "$agent_path" "$AGENTS_DIR/$agent_name.md"; then
                    rewrite_body "$AGENTS_DIR/$agent_name.md"

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
        for dir_pair in "$SKILLS_DIR:$real_skills_dir" "$AGENTS_DIR:$real_agents_dir" "$COMMANDS_DIR:$real_commands_dir"; do
            local tmp_dir="${dir_pair%%:*}"
            local real_dir="${dir_pair##*:}"

            if [[ ! -d "$real_dir" ]]; then
                echo "STALE  $real_dir does not exist (run ./sync-opencode.sh)"
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

        echo "OpenCode sync is up-to-date."
        exit 0
    fi

    echo ""
    echo "Synced $skill_count skills, $agent_count agents, $command_count commands."
}

main
