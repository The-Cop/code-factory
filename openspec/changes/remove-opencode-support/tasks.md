## 1. Baseline and Approval Gate

- [x] 1.1 Record the clean Git status, the tracked OpenCode inventory, ignored repository-local `.opencode/` artifacts, and active OpenCode references before editing.
- [x] 1.2 Run the current `make all` baseline and identify the direct Claude Code, Codex, and Pi MCP paths that must survive deletion of `sync-mcp.sh`.
- [x] 1.3 Request explicit user approval to edit `settings.json`; name `WebFetch(domain:opencode.ai)` as the only entry to remove and commit to preserving every unrelated setting.

## 2. Canonical Guidance and Metadata

- [x] 2.1 Update `productivity/skills/skill-workbench/SKILL.md` to remove OpenCode managed paths, red flags, command generation, and error handling while preserving source-path safety and the remaining skill workflow.
- [x] 2.2 Bump `productivity/.claude-plugin/plugin.json` from `0.50.0` to `0.51.0` for the functional authoring-workflow removal.
- [x] 2.3 Update `README.md` so the supported platform list, installation flow, development notes, configuration reference, MCP description, and generated-output guidance cover only Claude Code, Codex, and Pi.
- [x] 2.4 Update `AGENTS.md` to remove OpenCode files, generated-directory rules, sync validation claims, and protected-config references while keeping source and remaining generated-platform instructions accurate.

## 3. Bootstrap, Validation, and OpenCode Asset Removal

- [x] 3.1 Update `init.sh` to remove the OpenCode root-config link, `sync-mcp.sh` invocation, generated-asset sync, global manifest/link lifecycle, and obsolete header text without changing Claude Code, Codex, Pi, OpenSpec, or direct MCP setup.
- [x] 3.2 Remove the now-orphaned `.githooks/pre-commit` and git-hook installation block, then remove README and AGENTS claims about repository-managed git hooks.
- [x] 3.3 Update `Makefile` to remove OpenCode and MCP-projection phony targets, recipes, check dependencies, and help text; remove the JSONC lint phase because no tracked JSONC consumer remains.
- [x] 3.4 Delete `opencode.jsonc`, `sync-opencode.sh`, `sync-mcp.sh`, and `validate-jsonc.mjs` after all callers are removed.
- [x] 3.5 Delete the complete repository-local `.opencode/` directory, including 139 tracked assets and ignored package metadata, lockfile, dependencies, and directory-local ignore file.

## 4. Protected Settings Change

- [x] 4.1 After task 1.3 approval, remove only `WebFetch(domain:opencode.ai)` from `settings.json`, validate its JSON, and inspect the focused diff to prove every unrelated setting is preserved.

## 5. Supported Generated Mirrors

- [x] 5.1 Run `make sync-codex` and `make sync-pi` after canonical skill edits; do not edit `.codex/` or `.pi/` directly.
- [x] 5.2 Inspect generated Codex and Pi skill-workbench assets to verify OpenCode path, command, permission, and error-handling guidance is absent and source parity is maintained.

## 6. Validation and Completion Audit

- [x] 6.1 Run `bash -n init.sh`, `make help`, and `make all`; fix every syntax, frontmatter, version, reference, supported-mirror freshness, configuration, or lint failure.
- [x] 6.2 Audit active tracked files outside `openspec/changes/**` for case-insensitive OpenCode references and remove every remaining support claim or implementation reference.
- [x] 6.3 Verify `.opencode/`, `opencode.jsonc`, `sync-opencode.sh`, `sync-mcp.sh`, `validate-jsonc.mjs`, and `.githooks/pre-commit` are absent from both the working tree and tracked-file set.
- [x] 6.4 Verify `init.sh`, `install-codex-mcp.sh`, and `sync-pi.sh` still retain direct Claude Code, Codex, and Pi MCP behavior and contain no external OpenCode cleanup command.
- [x] 6.5 Run `git diff --check` and inspect final diff/status for intended deletions, `0.51.0` metadata, the approved minimal settings edit, generated consistency, preserved historical OpenSpec records, and no unrelated changes.
- [x] 6.6 Report the removed surfaces, preserved platform behavior, validation evidence, approval-dependent decision, external-state boundary, and any remaining limitation without creating a second implementation-notes artifact.
