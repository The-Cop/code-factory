## Why

OpenCode is no longer a supported consumer of this marketplace, but its generated assets, configuration, bootstrap logic, validation, and authoring guidance still impose maintenance cost and couple unrelated workflows to an unused platform. Removing that active support lets the repository focus on Claude Code, Codex, and Pi while keeping their behavior intact.

## What Changes

- **BREAKING**: Remove OpenCode as a supported repository and installation target.
- Delete tracked and ignored repository-local `.opencode/` assets, the OpenCode configuration, its generator, its MCP projection script, and tooling that exists only to validate OpenCode JSONC.
- Remove OpenCode generation, freshness checks, global linking, and the now-orphaned OpenCode-only pre-commit hook from bootstrap and validation workflows.
- Remove OpenCode-specific paths, command generation, permissions, and instructions from active skills, settings, README guidance, and repository agent guidance.
- Regenerate Codex and Pi mirrors from the remaining source skills and preserve Claude Code, Codex, Pi, OpenSpec, and MCP behavior.
- Keep completed OpenSpec artifacts as historical evidence and leave user-owned `~/.config/opencode` state untouched.

## Capabilities

### New Capabilities

- `platform-support-boundary`: Defines the supported agent platforms, the absence of active OpenCode support, repository-local cleanup expectations, and preservation requirements for remaining surfaces.

### Modified Capabilities

None.

## Impact

- Deletes `.opencode/`, `opencode.jsonc`, `sync-opencode.sh`, `sync-mcp.sh`, the OpenCode-only pre-commit hook, and the now-unused JSONC validator.
- Updates `Makefile`, `init.sh`, `README.md`, `AGENTS.md`, `settings.json`, `productivity/skills/skill-workbench/SKILL.md`, and productivity plugin metadata.
- Regenerates affected `.codex/` and `.pi/` skill mirrors through their existing sync scripts.
- Does not modify external OpenCode configuration, rewrite completed OpenSpec evidence, or remove shared `mcp.json` behavior used by Claude Code, Codex, and Pi.
