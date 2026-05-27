#!/usr/bin/env bash
#
# init.sh -- Bootstrap code-factory: symlink configs and install OpenCode assets globally.
#
# This script:
#   1. Symlinks configuration files into the user's home directory.
#   2. Syncs MCP servers into Claude Code.
#   3. Symlinks Claude Code hooks, rules, and git hooks.
#   4. Runs sync-opencode.sh to generate OpenCode assets in the repo.
#   5. Symlinks .opencode/{skills,agents,commands} into ~/.config/opencode/.
#   6. Installs managed Codex config, skills, agents, and execpolicy rules.
#   7. Updates Claude Code CLI and all installed marketplace plugins.
#
# Behavior:
#   - If the destination is an existing symlink, it is removed and re-created.
#   - If the destination is a regular file, the script records an error.
#     To fix, back up or remove the existing file manually and re-run.
#   - If the destination does not exist, the symlink is created.
#   - Parent directories are created as needed (e.g., ~/.claude/, ~/.config/opencode/).
#   - The script exits non-zero if any file fails to link, with a summary at the end.
#
# This script is idempotent: running it multiple times produces the same result.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

errors=()

# Source local node env if previously installed (mirrors cargo env pattern)
if [[ -f "$HOME/.local/node/env" ]]; then
    . "$HOME/.local/node/env"
fi

# Install Node.js if not available (required by statusLine npx command and hooks)
echo "Checking Node.js installation..."
if command -v node &>/dev/null; then
    echo "  OK  node already installed ($(node --version))"
else
    case "$(uname -s)" in
        Linux)
            echo "  Installing Node.js..."
            ARCH=$(uname -m)
            NODE_ARCH=""
            case "$ARCH" in
                x86_64)  NODE_ARCH="x64" ;;
                aarch64) NODE_ARCH="arm64" ;;
                *)
                    errors+=("node: unsupported architecture $ARCH")
                    echo "  FAIL  unsupported architecture $ARCH"
                    ;;
            esac
            if [[ -n "$NODE_ARCH" ]]; then
                NODE_VERSION="v22.14.0"
                NODE_DIST="node-${NODE_VERSION}-linux-${NODE_ARCH}"
                TMP_DIR=$(mktemp -d)
                if curl -fsSL "https://nodejs.org/dist/${NODE_VERSION}/${NODE_DIST}.tar.xz" -o "$TMP_DIR/node.tar.xz"; then
                    tar -xJf "$TMP_DIR/node.tar.xz" -C "$TMP_DIR"
                    rm -rf "$HOME/.local/node"
                    mv "$TMP_DIR/$NODE_DIST" "$HOME/.local/node"
                    # Create env file (mirrors ~/.cargo/env pattern)
                    cat > "$HOME/.local/node/env" << 'NODEENV'
# Node.js environment (installed by code-factory init.sh)
case ":${PATH}:" in
    *":$HOME/.local/node/bin:"*) ;;
    *) export PATH="$HOME/.local/node/bin:$PATH" ;;
esac
NODEENV
                    . "$HOME/.local/node/env"
                    # Persist in shell profiles so future shells find node
                    for profile in "$HOME/.bashrc" "$HOME/.profile"; do
                        if [[ -f "$profile" ]] && ! grep -q '.local/node/env' "$profile"; then
                            printf '\n# Node.js (installed by code-factory)\n[ -f "$HOME/.local/node/env" ] && . "$HOME/.local/node/env"\n' >> "$profile"
                        fi
                    done
                    echo "  OK  node installed ($(node --version))"
                else
                    errors+=("node: download failed")
                    echo "  FAIL  node download failed"
                fi
                rm -rf "$TMP_DIR"
            fi
            ;;
        *)
            echo "  SKIP  node not found, install manually from https://nodejs.org"
            ;;
    esac
fi
echo ""

SRCS=(
    "$SCRIPT_DIR/settings.json"
    "$SCRIPT_DIR/opencode.jsonc"
    "$SCRIPT_DIR/claude/CLAUDE.md"
)
DESTS=(
    "$HOME/.claude/settings.json"
    "$HOME/.config/opencode/opencode.jsonc"
    "$HOME/.claude/CLAUDE.md"
)

for i in "${!SRCS[@]}"; do
    src="${SRCS[$i]}"
    dest="${DESTS[$i]}"

    if [[ ! -f "$src" ]]; then
        errors+=("$src -> $dest: source file not found")
        echo "FAIL  $src (source file not found)"
        continue
    fi

    mkdir -p "$(dirname "$dest")"

    if [[ -L "$dest" ]]; then
        rm "$dest"
    elif [[ -f "$dest" && ! -s "$dest" ]]; then
        # Empty stub (e.g. Claude Code default ~/.claude/CLAUDE.md) is safe to replace.
        rm "$dest"
    elif [[ -f "$dest" ]] && cmp -s "$dest" "$src"; then
        # Regular file with identical content — Claude Code can rewrite the
        # symlink as a regular copy. Safe to replace with a symlink.
        rm "$dest"
    elif [[ -f "$dest" ]]; then
        # Regular file with different content. Claude Code rewrites
        # ~/.claude/settings.json as a regular file when it edits settings, so
        # back up and replace instead of failing. Other destinations keep the
        # stricter "back up and skip" behaviour so user edits are preserved.
        backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
        if ! mv "$dest" "$backup"; then
            errors+=("$src -> $dest: dest differed from source and backup failed")
            echo "FAIL  could not back up $dest, skipping"
            continue
        fi
        if [[ "$dest" == "$HOME/.claude/settings.json" ]]; then
            echo "WARN  $dest differed from source, backed up to $backup and relinking"
        else
            errors+=("$src -> $dest: dest differed from source; backed up to $backup")
            echo "FAIL  $dest differed from source, backed up to $backup and skipped"
            continue
        fi
    elif [[ -e "$dest" ]]; then
        errors+=("$src -> $dest: destination already exists (not a regular file)")
        echo "FAIL  $dest already exists and is not a regular file, cannot link"
        continue
    fi

    if ! ln -s "$src" "$dest"; then
        errors+=("$src -> $dest: ln -s failed")
        echo "FAIL  could not link $dest -> $src"
        continue
    fi
    echo "LINK  $dest -> $src"
done

# Sync MCP servers: regenerate opencode.jsonc block + install into Claude Code
echo ""
echo "Syncing MCP servers..."
"$SCRIPT_DIR/sync-mcp.sh"

echo ""
echo "Installing MCP servers into Claude Code (user scope)..."

# Clean up stale ~/.mcp.json symlink from old approach
if [[ -L "$HOME/.mcp.json" ]]; then
    rm "$HOME/.mcp.json"
    echo "  Removed stale ~/.mcp.json symlink"
fi

mcp_server_names=$(python3 -c "
import json
data = json.load(open('$SCRIPT_DIR/mcp.json'))
for name in data.get('mcpServers', {}):
    print(name)
")

for name in $mcp_server_names; do
    config=$(python3 -c "
import json
data = json.load(open('$SCRIPT_DIR/mcp.json'))
print(json.dumps(data['mcpServers']['$name']))
")
    # Remove existing (ignore errors if not present)
    claude mcp remove "$name" 2>/dev/null || true
    # Add with user scope
    if claude mcp add-json -s user "$name" "$config" 2>&1; then
        echo "  OK  $name"
    else
        errors+=("mcp: failed to install $name")
        echo "  FAIL  $name"
    fi
done

# Symlink Claude Code hooks from hooks/ into ~/.claude/hooks/
echo ""
echo "Linking Claude Code hooks..."
HOOKS_DIR="$HOME/.claude/hooks"
mkdir -p "$HOOKS_DIR"
for hook_src in "$SCRIPT_DIR/hooks"/*; do
    [[ -f "$hook_src" ]] || continue
    hook_name=$(basename "$hook_src")
    hook_dest="$HOOKS_DIR/$hook_name"
    if [[ -L "$hook_dest" ]]; then
        rm "$hook_dest"
    elif [[ -e "$hook_dest" ]]; then
        errors+=("$hook_src -> $hook_dest: destination already exists as a regular file")
        echo "  FAIL  $hook_dest already exists as a regular file, cannot link"
        continue
    fi
    if ! ln -s "$hook_src" "$hook_dest"; then
        errors+=("$hook_src -> $hook_dest: ln -s failed")
        echo "  FAIL  could not link $hook_dest -> $hook_src"
    else
        echo "  LINK  $hook_dest -> $hook_src"
    fi
done

# Symlink Claude Code rules from rules/ into ~/.claude/rules/
echo ""
echo "Linking Claude Code rules..."
RULES_DIR="$HOME/.claude/rules"
mkdir -p "$RULES_DIR"
for rule_src in "$SCRIPT_DIR/rules"/*.md; do
    [[ -f "$rule_src" ]] || continue
    rule_name=$(basename "$rule_src")
    rule_dest="$RULES_DIR/$rule_name"
    if [[ -L "$rule_dest" ]]; then
        rm "$rule_dest"
    elif [[ -e "$rule_dest" ]]; then
        errors+=("$rule_src -> $rule_dest: destination already exists as a regular file")
        echo "  FAIL  $rule_dest already exists as a regular file, cannot link"
        continue
    fi
    if ! ln -s "$rule_src" "$rule_dest"; then
        errors+=("$rule_src -> $rule_dest: ln -s failed")
        echo "  FAIL  could not link $rule_dest -> $rule_src"
    else
        echo "  LINK  $rule_dest -> $rule_src"
    fi
done

# Generate OpenCode assets in the repo
echo ""
echo "Syncing skills, agents, and commands..."
"$SCRIPT_DIR/sync-opencode.sh"

# Propagate .opencode/{skills,agents,commands} to ~/.config/opencode/
echo ""
echo "Linking to ~/.config/opencode/..."

GLOBAL_DIR="$HOME/.config/opencode"
OPENCODE_DIR="$SCRIPT_DIR/.opencode"
MANIFEST="$GLOBAL_DIR/.code-factory-managed"

new_manifest=()

# Read old manifest for cleanup
old_manifest=()
if [[ -f "$MANIFEST" ]]; then
    while IFS= read -r line; do
        old_manifest+=("$line")
    done < "$MANIFEST"
fi

# Symlink each rule file
RULES_SRC_DIR="$SCRIPT_DIR/rules"
if [[ -d "$RULES_SRC_DIR" ]]; then
    mkdir -p "$GLOBAL_DIR/rules"
    for rule_src in "$RULES_SRC_DIR"/*.md; do
        [[ -f "$rule_src" ]] || continue
        rule_name=$(basename "$rule_src")
        rule_dest="$GLOBAL_DIR/rules/$rule_name"
        if ! ln -sf "$rule_src" "$rule_dest"; then
            errors+=("$rule_src -> $rule_dest: ln -sf failed")
            echo "  FAIL  rules/$rule_name"
        else
            new_manifest+=("$rule_dest")
            echo "  LINK  rules/$rule_name"
        fi
    done
fi

# Symlink each skill directory
if [[ -d "$OPENCODE_DIR/skills" ]]; then
    mkdir -p "$GLOBAL_DIR/skills"
    for skill_src in "$OPENCODE_DIR/skills"/*/; do
        [[ -d "$skill_src" ]] || continue
        skill_name=$(basename "$skill_src")
        skill_dest="$GLOBAL_DIR/skills/$skill_name"
        if ! ln -sfn "$skill_src" "$skill_dest"; then
            errors+=("$skill_src -> $skill_dest: ln -sfn failed")
            echo "  FAIL  skills/$skill_name/"
        else
            new_manifest+=("$skill_dest")
            echo "  LINK  skills/$skill_name/"
        fi
    done
fi

# Symlink agent, command, and plugin files
for subdir in agents commands plugins; do
    src_dir="$OPENCODE_DIR/$subdir"
    dest_dir="$GLOBAL_DIR/$subdir"
    [[ -d "$src_dir" ]] || continue
    mkdir -p "$dest_dir"

    while IFS= read -r src_file; do
        rel="${src_file#"$src_dir"/}"
        dest_file="$dest_dir/$rel"
        if ! ln -sf "$src_file" "$dest_file"; then
            errors+=("$src_file -> $dest_file: ln -sf failed")
            echo "  FAIL  $subdir/$rel"
        else
            new_manifest+=("$dest_file")
            echo "  LINK  $subdir/$rel"
        fi
    done < <(find "$src_dir" -type f \( -name "*.md" -o -name "*.ts" \) | sort)
done

# Manifest cleanup: remove stale global files
sorted_manifest=$(printf '%s\n' "${new_manifest[@]}" | sort)
cleaned=0
for old_file in "${old_manifest[@]+"${old_manifest[@]}"}"; do
    [[ -z "$old_file" ]] && continue
    if ! echo "$sorted_manifest" | grep -qxF "$old_file"; then
        if [[ -e "$old_file" || -L "$old_file" ]]; then
            rm -f "$old_file"
            echo "  CLEAN  $old_file"
            cleaned=$((cleaned + 1))
        fi
        parent=$(dirname "$old_file")
        rmdir "$parent" 2>/dev/null || true
    fi
done

# Write new manifest
echo "$sorted_manifest" > "$MANIFEST"

echo ""
echo "Linked ${#new_manifest[@]} files to ~/.config/opencode/. Cleaned $cleaned stale files."

# Generate Codex assets in the repo
echo ""
echo "Syncing Codex skills and agents..."
"$SCRIPT_DIR/sync-codex.sh"

# Propagate .codex/{skills,agents} to ~/.codex/
echo ""
echo "Linking to ~/.codex/..."

CODEX_GLOBAL_DIR="$HOME/.codex"
CODEX_LOCAL_DIR="$SCRIPT_DIR/.codex"
CODEX_MANIFEST="$CODEX_GLOBAL_DIR/.code-factory-managed"

codex_new_manifest=()

# Read old Codex manifest for cleanup
codex_old_manifest=()
if [[ -f "$CODEX_MANIFEST" ]]; then
    while IFS= read -r line; do
        codex_old_manifest+=("$line")
    done < "$CODEX_MANIFEST"
fi

# Symlink each Codex skill directory
if [[ -d "$CODEX_LOCAL_DIR/skills" ]]; then
    mkdir -p "$CODEX_GLOBAL_DIR/skills"
    for skill_src in "$CODEX_LOCAL_DIR/skills"/*/; do
        [[ -d "$skill_src" ]] || continue
        skill_name=$(basename "$skill_src")
        skill_dest="$CODEX_GLOBAL_DIR/skills/$skill_name"
        if ! ln -sfn "$skill_src" "$skill_dest"; then
            errors+=("$skill_src -> $skill_dest: ln -sfn failed")
            echo "  FAIL  skills/$skill_name/"
        else
            codex_new_manifest+=("$skill_dest")
            echo "  LINK  skills/$skill_name/"
        fi
    done
fi

# Symlink each Codex agent file
if [[ -d "$CODEX_LOCAL_DIR/agents" ]]; then
    mkdir -p "$CODEX_GLOBAL_DIR/agents"
    while IFS= read -r agent_src; do
        agent_name=$(basename "$agent_src")
        agent_dest="$CODEX_GLOBAL_DIR/agents/$agent_name"
        if ! ln -sf "$agent_src" "$agent_dest"; then
            errors+=("$agent_src -> $agent_dest: ln -sf failed")
            echo "  FAIL  agents/$agent_name"
        else
            codex_new_manifest+=("$agent_dest")
            echo "  LINK  agents/$agent_name"
        fi
    done < <(find "$CODEX_LOCAL_DIR/agents" -name "*.toml" | sort)
fi

# Symlink each Codex execpolicy rule file
CODEX_RULES_SRC_DIR="$SCRIPT_DIR/codex/rules"
if [[ -d "$CODEX_RULES_SRC_DIR" ]]; then
    mkdir -p "$CODEX_GLOBAL_DIR/rules"
    while IFS= read -r rule_src; do
        rule_name=$(basename "$rule_src")
        rule_dest="$CODEX_GLOBAL_DIR/rules/$rule_name"
        if ! ln -sf "$rule_src" "$rule_dest"; then
            errors+=("$rule_src -> $rule_dest: ln -sf failed")
            echo "  FAIL  rules/$rule_name"
        else
            codex_new_manifest+=("$rule_dest")
            echo "  LINK  rules/$rule_name"
        fi
    done < <(find "$CODEX_RULES_SRC_DIR" -name "*.rules" | sort)
fi

# Codex manifest cleanup: remove stale global files
if [[ ${#codex_new_manifest[@]} -gt 0 ]]; then
    codex_sorted_manifest=$(printf '%s\n' "${codex_new_manifest[@]}" | sort)
else
    codex_sorted_manifest=""
fi
codex_cleaned=0
for old_file in "${codex_old_manifest[@]+"${codex_old_manifest[@]}"}"; do
    [[ -z "$old_file" ]] && continue
    if ! echo "$codex_sorted_manifest" | grep -qxF "$old_file"; then
        if [[ -e "$old_file" || -L "$old_file" ]]; then
            rm -f "$old_file"
            echo "  CLEAN  $old_file"
            codex_cleaned=$((codex_cleaned + 1))
        fi
        parent=$(dirname "$old_file")
        rmdir "$parent" 2>/dev/null || true
    fi
done

# Write new Codex manifest
if [[ -n "$codex_sorted_manifest" ]]; then
    echo "$codex_sorted_manifest" > "$CODEX_MANIFEST"
else
    : > "$CODEX_MANIFEST"
fi

echo ""
echo "Linked ${#codex_new_manifest[@]} entries to ~/.codex/. Cleaned $codex_cleaned stale entries."

echo ""
echo "Installing MCP servers into Codex config..."
if "$SCRIPT_DIR/install-codex-mcp.sh"; then
    echo "  OK  Codex MCP config"
else
    errors+=("mcp: failed to install Codex MCP config")
    echo "  FAIL  Codex MCP config"
fi

# Generate Pi assets in the repo
echo ""
echo "Syncing Pi skills, prompts, agents, and MCP extension..."
"$SCRIPT_DIR/sync-pi.sh"

# Propagate .pi/{skills,prompts,agents,extensions} to ~/.pi/agent/
echo ""
echo "Linking to ~/.pi/agent/..."

PI_GLOBAL_DIR="$HOME/.pi/agent"
PI_LOCAL_DIR="$SCRIPT_DIR/.pi"
PI_MANIFEST="$PI_GLOBAL_DIR/.code-factory-managed"

pi_new_manifest=()

pi_old_manifest=()
if [[ -f "$PI_MANIFEST" ]]; then
    while IFS= read -r line; do
        pi_old_manifest+=("$line")
    done < "$PI_MANIFEST"
fi

# Symlink each Pi skill directory
if [[ -d "$PI_LOCAL_DIR/skills" ]]; then
    mkdir -p "$PI_GLOBAL_DIR/skills"
    for skill_src in "$PI_LOCAL_DIR/skills"/*/; do
        [[ -d "$skill_src" ]] || continue
        skill_name=$(basename "$skill_src")
        skill_dest="$PI_GLOBAL_DIR/skills/$skill_name"
        if ! ln -sfn "$skill_src" "$skill_dest"; then
            errors+=("$skill_src -> $skill_dest: ln -sfn failed")
            echo "  FAIL  skills/$skill_name/"
        else
            pi_new_manifest+=("$skill_dest")
            echo "  LINK  skills/$skill_name/"
        fi
    done
fi

# Symlink each Pi prompt file
if [[ -d "$PI_LOCAL_DIR/prompts" ]]; then
    mkdir -p "$PI_GLOBAL_DIR/prompts"
    while IFS= read -r prompt_src; do
        prompt_name=$(basename "$prompt_src")
        prompt_dest="$PI_GLOBAL_DIR/prompts/$prompt_name"
        if ! ln -sf "$prompt_src" "$prompt_dest"; then
            errors+=("$prompt_src -> $prompt_dest: ln -sf failed")
            echo "  FAIL  prompts/$prompt_name"
        else
            pi_new_manifest+=("$prompt_dest")
            echo "  LINK  prompts/$prompt_name"
        fi
    done < <(find "$PI_LOCAL_DIR/prompts" -name "*.md" | sort)
fi

# Symlink each Pi agent file
if [[ -d "$PI_LOCAL_DIR/agents" ]]; then
    mkdir -p "$PI_GLOBAL_DIR/agents"
    while IFS= read -r agent_src; do
        agent_name=$(basename "$agent_src")
        agent_dest="$PI_GLOBAL_DIR/agents/$agent_name"
        if ! ln -sf "$agent_src" "$agent_dest"; then
            errors+=("$agent_src -> $agent_dest: ln -sf failed")
            echo "  FAIL  agents/$agent_name"
        else
            pi_new_manifest+=("$agent_dest")
            echo "  LINK  agents/$agent_name"
        fi
    done < <(find "$PI_LOCAL_DIR/agents" -name "*.md" | sort)
fi

# Symlink each Pi extension directory
if [[ -d "$PI_LOCAL_DIR/extensions" ]]; then
    mkdir -p "$PI_GLOBAL_DIR/extensions"
    for ext_src in "$PI_LOCAL_DIR/extensions"/*/; do
        [[ -d "$ext_src" ]] || continue
        ext_name=$(basename "$ext_src")
        ext_dest="$PI_GLOBAL_DIR/extensions/$ext_name"
        if ! ln -sfn "$ext_src" "$ext_dest"; then
            errors+=("$ext_src -> $ext_dest: ln -sfn failed")
            echo "  FAIL  extensions/$ext_name/"
        else
            pi_new_manifest+=("$ext_dest")
            echo "  LINK  extensions/$ext_name/"
        fi
    done
fi

# Pi manifest cleanup
if [[ ${#pi_new_manifest[@]} -gt 0 ]]; then
    pi_sorted_manifest=$(printf '%s\n' "${pi_new_manifest[@]}" | sort)
else
    pi_sorted_manifest=""
fi
pi_cleaned=0
for old_file in "${pi_old_manifest[@]+"${pi_old_manifest[@]}"}"; do
    [[ -z "$old_file" ]] && continue
    if ! echo "$pi_sorted_manifest" | grep -qxF "$old_file"; then
        if [[ -e "$old_file" || -L "$old_file" ]]; then
            rm -f "$old_file"
            echo "  CLEAN  $old_file"
            pi_cleaned=$((pi_cleaned + 1))
        fi
        parent=$(dirname "$old_file")
        rmdir "$parent" 2>/dev/null || true
    fi
done

mkdir -p "$PI_GLOBAL_DIR"
if [[ -n "$pi_sorted_manifest" ]]; then
    echo "$pi_sorted_manifest" > "$PI_MANIFEST"
else
    : > "$PI_MANIFEST"
fi

echo ""
echo "Linked ${#pi_new_manifest[@]} entries to ~/.pi/agent/. Cleaned $pi_cleaned stale entries."

# Install curated pi.dev packages
echo ""
echo "Installing Pi packages..."
if ! command -v pi &>/dev/null; then
    if command -v npm &>/dev/null; then
        echo "  pi CLI not found; installing @earendil-works/pi-coding-agent..."
        if npm i -g @earendil-works/pi-coding-agent 2>&1 | tail -3; then
            echo "  OK  pi CLI installed"
        else
            echo "  WARN  pi CLI install failed"
        fi
    else
        echo "  SKIP  pi CLI not found and npm unavailable (install Node.js, then re-run init)"
    fi
fi
if ! command -v pi &>/dev/null; then
    echo "  SKIP  pi CLI still not available"
else
    # Datadog packages: clone-or-update the marketplace repo, then install by local path.
    # The repo root is intentionally a catalog, not a pi package -- each subdir under
    # packages/ must be installed individually.
    DD_PI_REPO="${DD_PI_REPO:-$HOME/dd/datadog-pi-packages}"
    DD_PI_REMOTE="git@github.com:ddoghq-sandbox/datadog-pi-packages.git"
    mkdir -p "$(dirname "$DD_PI_REPO")"
    if [[ -d "$DD_PI_REPO/.git" ]]; then
        if git -C "$DD_PI_REPO" pull --ff-only 2>&1 | tail -1; then
            echo "  OK  $DD_PI_REPO updated"
        else
            echo "  WARN  $DD_PI_REPO update failed"
        fi
    elif [[ ! -e "$DD_PI_REPO" ]]; then
        if git clone --depth 1 "$DD_PI_REMOTE" "$DD_PI_REPO" 2>&1 | tail -1; then
            echo "  OK  $DD_PI_REPO cloned"
        else
            echo "  WARN  $DD_PI_REPO clone failed (need access to ddoghq-sandbox; see https://github.com/ddoghq-sandbox/datadog-pi-packages/blob/main/docs/github-auth.md)"
        fi
    fi

    if [[ -d "$DD_PI_REPO/packages" ]]; then
        DD_PI_PACKAGES=(
            "refresh-models"
            "confluence-adf"
        )
        for pkg in "${DD_PI_PACKAGES[@]}"; do
            pkg_path="$DD_PI_REPO/packages/$pkg"
            if [[ ! -d "$pkg_path" ]]; then
                echo "  WARN  $pkg not found at $pkg_path"
                continue
            fi
            if pi install "$pkg_path" 2>&1 | tail -1; then
                echo "  OK  datadog-pi-packages/$pkg"
            else
                echo "  WARN  datadog-pi-packages/$pkg install failed"
            fi
        done
    fi
fi

# Configure Pi to use Datadog AI Gateway (opt out via PI_AUTOCONFIG=0)
echo ""
echo "Configuring Pi AI Gateway..."
configure_pi_aigateway() {
    if [[ "${PI_AUTOCONFIG:-1}" == "0" ]]; then
        echo "  SKIP  PI_AUTOCONFIG=0"
        return 0
    fi
    if ! command -v pi &>/dev/null && [[ ! -d "$HOME/.pi" ]]; then
        echo "  SKIP  pi not installed"
        return 0
    fi
    if ! command -v ddtool &>/dev/null; then
        echo "  SKIP  ddtool not installed (see https://datadoghq.atlassian.net/wiki/spaces/~5e9d84f05f50bf0c0b460b93/pages/6699122806)"
        return 0
    fi
    # Choose AI gateway datacenter. Workspaces cannot reach prod vault, so they
    # use staging by default. Override with DD_AIGW_DC to force a specific DC.
    # `IN_WORKSPACE=1` is set by the workspaces daemon via /etc/fish/conf.d.
    local aigw_dc="${DD_AIGW_DC:-}"
    if [[ -z "$aigw_dc" ]]; then
        if [[ "${IN_WORKSPACE:-}" == "1" ]]; then
            aigw_dc="us1.staging.dog"
        else
            aigw_dc="us1.prod.dog"
        fi
    fi
    echo "  using ai-gateway datacenter: $aigw_dc"
    if ! ddtool auth token rapid-ai-platform --datacenter "$aigw_dc" >/dev/null 2>&1; then
        if [[ ! -t 0 ]]; then
            echo "  SKIP  ddtool not authed and shell is non-interactive (run: ddtool auth login --datacenter $aigw_dc)"
            return 0
        fi
        echo "  ddtool not authed for rapid-ai-platform; running auth login..."
        if ! ddtool auth login --datacenter "$aigw_dc"; then
            echo "  SKIP  ddtool auth login failed"
            return 0
        fi
        if ! ddtool auth token rapid-ai-platform --datacenter "$aigw_dc" >/dev/null 2>&1; then
            echo "  SKIP  ddtool auth still not valid after login"
            return 0
        fi
        echo "  OK  ddtool authed for rapid-ai-platform"
    fi

    local cfg="$PI_GLOBAL_DIR/models.json"
    local pi_config="$SCRIPT_DIR/pi.json"
    local email team
    email=$(git config --global user.email 2>/dev/null || echo "$USER@datadoghq.com")
    team="${DD_TEAM:-unknown}"

    mkdir -p "$(dirname "$cfg")"

    if [[ ! -f "$pi_config" ]]; then
        errors+=("pi: $pi_config not found")
        echo "  FAIL  $pi_config not found"
        return 1
    fi

    # Skip if any Datadog AI Gateway provider is already present. Detects both
    # our static seed names ("datadog-ai-gateway", "datadog-ai-gateway-anthropic")
    # and the /refresh-models-managed "ai-gw-*" names. Lets users adopt
    # /refresh-models as the source of truth without us clobbering their config.
    if [[ -f "$cfg" ]] && jq -e '(.providers // {}) | keys | map(select(startswith("ai-gw-") or startswith("datadog-ai-gateway"))) | length > 0' "$cfg" >/dev/null 2>&1; then
        echo "  OK  $cfg already configured"
        return 0
    fi

    local template
    if ! template=$(jq --arg email "$email" --arg team "$team" --arg aigw_dc "$aigw_dc" \
        '(.. | strings) |= (gsub("\\{\\{email\\}\\}"; $email) | gsub("\\{\\{team\\}\\}"; $team) | gsub("\\{\\{aigw_dc\\}\\}"; $aigw_dc))' \
        "$pi_config" 2>/dev/null); then
        errors+=("pi: failed to render $pi_config")
        echo "  FAIL  could not render $pi_config"
        return 1
    fi

    if [[ -f "$cfg" ]]; then
        cp "$cfg" "$cfg.bak.$(date +%s)"
        echo "$template" | jq --slurpfile existing "$cfg" '.providers + $existing[0].providers as $merged | $existing[0] | .providers = $merged' > "$cfg.tmp"
        mv "$cfg.tmp" "$cfg"
        echo "  OK  merged Datadog AI Gateway providers into $cfg"
    else
        echo "$template" > "$cfg"
        echo "  OK  wrote $cfg"
    fi

    if ! jq . "$cfg" >/dev/null 2>&1; then
        errors+=("pi: models.json is invalid JSON after autoconfig")
        echo "  FAIL  $cfg invalid JSON"
    fi
}
configure_pi_aigateway

# Install git hooks from .githooks/
for HOOK_SRC in "$SCRIPT_DIR/.githooks"/*; do
    [[ -f "$HOOK_SRC" ]] || continue
    HOOK_NAME=$(basename "$HOOK_SRC")
    HOOK_DEST="$SCRIPT_DIR/.git/hooks/$HOOK_NAME"
    if [[ -L "$HOOK_DEST" ]]; then
        rm "$HOOK_DEST"
    elif [[ -e "$HOOK_DEST" ]]; then
        errors+=("$HOOK_SRC -> $HOOK_DEST: destination already exists as a regular file")
        echo "FAIL  $HOOK_DEST already exists as a regular file, cannot link"
        continue
    fi
    if [[ ! -e "$HOOK_DEST" ]]; then
        if ! ln -s "$HOOK_SRC" "$HOOK_DEST"; then
            errors+=("$HOOK_SRC -> $HOOK_DEST: ln -s failed")
            echo "FAIL  could not link $HOOK_DEST -> $HOOK_SRC"
        else
            echo "LINK  $HOOK_DEST -> $HOOK_SRC"
        fi
    fi
done

# Update Claude Code and marketplace plugins (after all setup is complete)
echo ""
echo "Updating Claude Code and marketplace plugins..."
if command -v claude &>/dev/null; then
    if claude update 2>&1; then
        echo "  OK  claude updated"
    else
        echo "  WARN  claude update failed (may already be up-to-date)"
    fi
    marketplace_repos=$(jq -r '.extraKnownMarketplaces | to_entries[].value.source.repo' "$SCRIPT_DIR/settings.json" 2>/dev/null || true)
    if [[ -n "$marketplace_repos" ]]; then
        while IFS= read -r repo; do
            if claude plugin marketplace add "$repo" 2>&1; then
                echo "  OK  marketplace $repo added"
            else
                echo "  WARN  marketplace $repo add failed (may already exist)"
            fi
        done <<< "$marketplace_repos"
    fi
    enabled_plugins=$(jq -r '.enabledPlugins | keys[]' "$SCRIPT_DIR/settings.json" 2>/dev/null || true)
    if [[ -n "$enabled_plugins" ]]; then
        while IFS= read -r plugin; do
            if claude plugin install "$plugin" 2>&1; then
                echo "  OK  plugin $plugin installed"
            else
                echo "  WARN  plugin $plugin install failed (may already be installed)"
            fi
        done <<< "$enabled_plugins"
    fi
    # Update installed marketplaces
    marketplace_names=$(claude plugin marketplace list --json 2>/dev/null | jq -r '.[].name' 2>/dev/null || true)
    if [[ -n "$marketplace_names" ]]; then
        while IFS= read -r marketplace; do
            if claude plugin marketplace update "$marketplace" 2>&1; then
                echo "  OK  marketplace $marketplace updated"
            else
                echo "  WARN  marketplace $marketplace update failed"
            fi
        done <<< "$marketplace_names"
    else
        echo "  No marketplaces installed"
    fi
    # Update installed plugins (preserve each plugin's installation scope)
    installed_plugins=$(claude plugin list --json 2>/dev/null | jq -r '.[] | "\(.id)\t\(.scope)"' 2>/dev/null || true)
    if [[ -n "$installed_plugins" ]]; then
        while IFS=$'\t' read -r plugin scope; do
            if claude plugin update "$plugin" --scope "$scope" 2>&1; then
                echo "  OK  plugin $plugin updated (scope $scope)"
            else
                echo "  WARN  plugin $plugin update failed (scope $scope)"
            fi
        done <<< "$installed_plugins"
    else
        echo "  No plugins installed"
    fi
else
    echo "  SKIP  claude CLI not found"
fi

# Final error summary
if [[ ${#errors[@]} -gt 0 ]]; then
    echo ""
    echo "========================================="
    echo "ERROR: ${#errors[@]} file(s) failed to link or sync:"
    for err in "${errors[@]}"; do
        echo "  - $err"
    done
    echo "========================================="
    exit 1
fi
