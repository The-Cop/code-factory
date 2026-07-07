# AGENTS.md

Instructions for AI coding agents working in this repository.

## Project Overview

Plugin marketplace for Claude Code, OpenCode, Codex, and pi.dev. Two plugins — **productivity** and **git** — each containing skills and optionally agents. Tech stack: Markdown skill definitions, JSON configs, Makefile, shell scripts.

## Repository Structure

```
.claude-plugin/marketplace.json   # Marketplace manifest (version, plugin list)
{plugin}/                         # One directory per plugin
  .claude-plugin/plugin.json      #   Plugin manifest
  agents/                         #   Agent definitions (optional)
    {name}.md
  skills/                         #   Skill definitions
    {name}/SKILL.md
Makefile                          # all, check, lint, and install targets
init.sh                           # Bootstrap script
sync-opencode.sh                  # Regenerates .opencode/ from plugin sources
sync-codex.sh                     # Regenerates .codex/ from plugin sources
sync-pi.sh                        # Regenerates .pi/ from plugin sources
rules/                            # Claude Code rules linked into ~/.claude/rules/ by init.sh
hooks/                            # Claude Code hook scripts linked by init.sh
.githooks/                        # Git hooks linked into .git/hooks by init.sh
pi-extensions/                    # Hand-written pi.dev TypeScript extensions (ask-question)
vendor/                           # Vendored third-party scripts (e.g. Plannotator installer)
.opencode/                        # Generated OpenCode assets (do not edit directly)
.codex/                           # Generated Codex assets (do not edit directly)
.pi/                              # Generated Pi assets (do not edit directly)
settings.json                     # Claude Code global settings
mcp.json                          # MCP server configuration
opencode.jsonc                    # OpenCode CLI configuration
```

Discover available skills and agents by browsing the plugin directories. Each `SKILL.md` and agent `.md` file is self-describing — read it for purpose, usage, and behavior.

## Conventions

### Skill Frontmatter

Required fields for every `SKILL.md`:

| Field | Format | Example |
|-------|--------|---------|
| `name` | kebab-case | `commit`, `skill-workbench` |
| `description` | Starts with "Use when" | `Use when the user wants to...` |
| `argument-hint` | Bracketed placeholder | `[optional PR title]` |
| `user-invocable` | `true` or `false` | `true` |

Optional fields:

| Field | Purpose | Example |
|-------|---------|---------|
| `allowed-tools` | Restrict tool access (kebab-case) | `Bash(git:*), Read, Grep, Glob` |
| `disable-model-invocation` | Prevent auto-invocation by model (skill only runs when user explicitly invokes it) | `true` |

### Skill Structure

Every skill follows this structure:

1. **Announce line**: First line after the heading — a quoted string the agent says when starting.
2. **Numbered Steps**: `## Step N: Title` sections with clear actions.
3. **Error Handling**: Final section covering failure modes as a table or bullet list.

### Agent Frontmatter

Required fields for agent definitions in `agents/*.md`:

| Field | Format |
|-------|--------|
| `name` | kebab-case |
| `description` | Free text |

Optional: `model`, `allowed_tools` (note: **snake_case** in agents, **kebab-case** in skills).

### Cross-References

Skills reference each other with backtick-quoted slash patterns: `` `/commit` ``, `` `/branch` ``. The `make check-refs` target validates these resolve to real skill directories.

## Workflow

Every change must follow these four steps in order.

### 1. Plan

Plan before implementing. Describe:

- The approach and rationale.
- Which files will be created, modified, or deleted.
- Acceptance criteria for the change.

Do not write code until the plan is complete.

### 2. Implement

- Execute the plan step-by-step.
- Keep changes minimal and aligned with existing conventions.
- One logical change per commit.

### 3. Validate

Run after every implementation:

```bash
make all
```

- `make check` verifies skill frontmatter, agent frontmatter, skill cross-references, agent skill references, description conventions, skill structure, plugin manifest references, OpenCode sync freshness, Codex sync freshness, and Pi sync freshness.
- `make lint` validates all JSON and JSONC files.

All checks must pass before proceeding.

### 4. Update Documentation and Metadata

If changes affect functionality, configuration, or behavior:

- Update relevant Markdown docs (`README.md`, skill `SKILL.md` files).
- Update metadata files:
  - `plugin.json` in the affected plugin's `.claude-plugin/` directory.
  - `.claude-plugin/marketplace.json` if plugins are added or removed.
- Keep `settings.json` skill permissions in sync:
  - When adding a new skill: add a `Skill(<name>)` entry to `permissions.allow`.
  - When removing a skill: remove its `Skill(<name>)` entry from `permissions.allow`.
  - Only repo-defined skills get entries — never use `Skill(*)`.
- Bump version numbers following [semantic versioning](https://semver.org/):
  - **patch** — bug fixes, typo corrections.
  - **minor** — new skills, new features, backward-compatible changes.
  - **major** — breaking changes to skill interfaces or plugin structure.

## Context Efficiency

### Subagent Discipline

**Context-aware delegation:**
- Under ~50k context: prefer inline work for tasks under ~5 tool calls.
- Over ~50k context: prefer subagents for self-contained tasks, even simple ones —
  the per-call token tax on large contexts adds up fast.

When using subagents, include output rules: "Final response under 2000 characters. List outcomes, not process."
Never call TaskOutput twice for the same subagent. If it times out, increase the timeout — don't re-read.

### File Reading

Read files with purpose. Before reading a file, know what you're looking for.
Use Grep to locate relevant sections before reading entire large files.
Never re-read a file you've already read in this session.
For files over 500 lines, use offset/limit to read only the relevant section.

### Responses

Don't echo back file contents you just read — the user can see them.
Don't narrate tool calls ("Let me read the file..." / "Now I'll edit..."). Just do it.
Keep explanations proportional to complexity. Simple changes need one sentence, not three paragraphs.

**Tables — STRICT RULES (apply everywhere, always):**
- Markdown tables: use minimum separator (`|-|-|`). Never pad with repeated hyphens (`|---|---|`).
- NEVER use box-drawing / ASCII-art tables with characters like `┌`, `┬`, `─`, `│`, `└`, `┘`, `├`, `┤`, `┼`. These are completely banned.
- No exceptions. Not for "clarity", not for alignment, not for terminal output.

## Boundaries

**Always do:**

- Run `make all` before considering work complete.
- Plan before implementing.
- Follow existing file and directory naming patterns.
- Keep skill definitions self-contained in their `SKILL.md` files.

**Ask first:**

- Adding new plugins to the marketplace.
- Changing `settings.json`, `mcp.json`, or `opencode.jsonc`.
- Modifying agent definitions in `agents/`.

**Never do:**

- Commit secrets, tokens, or credentials.
- Force-push to `main`.
- Push with `git push` directly — always use `./push.sh`.
- Delete existing skills or plugins without explicit approval.
- Skip validation (`make all`).
- Modify files in `~/.claude/plugins/cache/`. This directory is a read-only deployment artifact managed by Claude Code's plugin system. Always make changes in the source repo — they propagate to the cache on the next plugin update.
- Edit files in `.opencode/` directly. This directory is generated by `sync-opencode.sh` (run via `make all`). Always edit the source files in `{plugin}/skills/` and `{plugin}/agents/` — changes propagate to `.opencode/` automatically.
- Edit files in `.codex/` directly. This directory is generated by `sync-codex.sh` (run via `make all`). Always edit the source files in `{plugin}/skills/` and `{plugin}/agents/` — changes propagate to `.codex/` automatically.
- Edit files in `.pi/` directly. This directory is generated by `sync-pi.sh` (run via `make all`). Always edit the source files in `{plugin}/skills/`, `{plugin}/agents/`, and `pi-extensions/` — changes propagate to `.pi/` automatically.
