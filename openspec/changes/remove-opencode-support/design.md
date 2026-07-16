## Context

The repository currently treats Claude Code plugin sources as canonical and projects them into Codex, OpenCode, and Pi formats. OpenCode support is cross-cutting: 139 tracked files live under `.opencode/`, ignored package artifacts live beside them, and dedicated configuration, generators, MCP projection, JSONC validation, bootstrap linking, a pre-commit hook, skill-authoring instructions, permissions, and documentation keep the surface active.

OpenCode is no longer a supported consumer. Claude Code, Codex, Pi, OpenSpec, and the shared `mcp.json` source must continue to work. Repository rules require source-first edits, regenerated Codex/Pi mirrors, `make all`, version metadata for functional skill changes, and explicit approval before editing `settings.json`.

## Goals / Non-Goals

**Goals:**

- Remove every active repository-owned OpenCode asset, configuration, workflow, permission, and documentation claim.
- Remove tooling that becomes dead when OpenCode is gone instead of leaving dormant maintenance paths.
- Preserve Claude Code, Codex, Pi, OpenSpec, and MCP installation/generation behavior.
- Keep completed OpenSpec records truthful and make the active-reference audit distinguish history from supported behavior.
- Leave the repository in a validated, source/generated-consistent state.

**Non-Goals:**

- Deleting or rewriting user-owned files under `~/.config/opencode`.
- Rewriting Git history or completed OpenSpec evidence to erase historical OpenCode references.
- Replacing OpenCode with another platform or adding new validation and hook behavior.
- Changing skill behavior unrelated to removal of OpenCode output and path guidance.

## Decisions

### Remove support as one cross-cutting boundary

Delete the generated tree, hand-written OpenCode plugins, root configuration, generator, MCP projection, and all callers and active guidance in the same change. A dormant generator or config would still be a support obligation and would make the repository's declared platform boundary ambiguous.

**Alternative considered:** Keep the generator and configuration but stop installing them. Rejected because freshness checks, authoring rules, and dependency updates would remain necessary for an unused output.

### Delete single-purpose validation and hook infrastructure

`opencode.jsonc` is the only tracked JSONC file, so remove `validate-jsonc.mjs` and the JSONC phase of `make lint` with it. The sole pre-commit hook only checks OpenCode freshness, so remove the hook and the now-orphaned git-hook installation/documentation rather than repurposing them.

**Alternative considered:** Generalize the JSONC validator and pre-commit hook for possible future use. Rejected because no current consumer requires them and adding new validation behavior is outside this removal.

### Preserve shared MCP behavior directly

Delete `sync-mcp.sh` because it only projects `mcp.json` into `opencode.jsonc`. Keep the existing direct Claude Code installation, Codex installation through `install-codex-mcp.sh`, and Pi generation through `sync-pi.sh`. Validation must demonstrate those paths remain present and their generated state stays fresh.

**Alternative considered:** Rename or retain `sync-mcp.sh`. Rejected because it contains no remaining shared behavior after the OpenCode projection is removed.

### Keep historical evidence, audit active surfaces

Do not edit completed OpenSpec artifacts merely because they record that OpenCode mirrors existed when that change was implemented. The final absence audit excludes `openspec/changes/**` and Git history, while active source, configuration, scripts, generated Codex/Pi assets, README, and AGENTS guidance must contain no OpenCode support references.

**Alternative considered:** Make a repository-wide text search return zero matches. Rejected because the removal change and historical implementation evidence must name the removed platform to remain intelligible and truthful.

### Do not mutate external OpenCode state

Remove all code that writes or links `~/.config/opencode`, but do not clean that directory during implementation or bootstrap. Existing links may become stale; that is an expected consequence of dropping support and avoids destructive edits to user-owned configuration.

**Alternative considered:** Add a one-time external uninstaller. Rejected because it retains OpenCode-specific code, expands scope beyond the repository, and could delete user customizations.

### Change source first and regenerate only remaining mirrors

Remove OpenCode path and command-generation guidance from `productivity/skills/skill-workbench/SKILL.md`, bump productivity from `0.50.0` to `0.51.0` following the repository's established removal precedent, then run the Codex and Pi sync targets. Do not edit generated `.codex/` or `.pi/` files directly.

**Alternative considered:** Delete OpenCode output without changing authoring guidance or version metadata. Rejected because the canonical skill would continue instructing future changes to recreate unsupported assets.

## Risks / Trade-offs

- **Shared MCP installation is accidentally removed with `sync-mcp.sh`** → Verify the direct Claude Code loop, `install-codex-mcp.sh`, and Pi MCP generation remain, then run their existing checks through `make all`.
- **OpenCode references survive in generated Codex or Pi skills** → Update the source skill first and regenerate both supported mirrors before the final audit.
- **Ignored package artifacts keep `.opencode/` present locally** → Remove the entire repository-local directory after recording tracked deletions; verify the path no longer exists.
- **Existing global OpenCode links become broken** → State the repository-only boundary clearly and do not claim external cleanup.
- **Historical records create false-positive searches** → Scope the audit to active files and explicitly allow completed and current OpenSpec change artifacts.
- **Protected settings are edited without approval** → Make removal of only `WebFetch(domain:opencode.ai)` an explicit approval-gated task and preserve every unrelated setting.
- **Version validation flags the skill change** → Apply the established productivity minor bump and run `make check-versions` through `make all`.

## Migration Plan

1. Capture a clean baseline and active OpenCode inventory.
2. Obtain explicit approval for the exact `settings.json` permission removal.
3. Update canonical skill guidance and productivity metadata.
4. Remove OpenCode configuration, generation, MCP projection, JSONC validation, pre-commit hook, bootstrap paths, Make targets, and active documentation.
5. Delete the tracked and ignored repository-local `.opencode/` tree.
6. Regenerate Codex and Pi outputs using their source-driven sync scripts.
7. Run `make all`, an active-reference audit, and final diff/status inspection.

Rollback is a normal Git revert of the removal commit followed by `make sync-codex`, `make sync-opencode`, and `make sync-pi` from the restored revision. No external configuration migration is performed, so external rollback is out of scope.

## Open Questions

None. The safe defaults are repository-only cleanup, preservation of historical records, no replacement platform, and no repurposing of orphaned tooling.
