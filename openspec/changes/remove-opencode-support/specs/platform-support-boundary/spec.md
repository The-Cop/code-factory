## ADDED Requirements

### Requirement: Supported platform boundary is explicit
The repository SHALL actively support Claude Code, Codex, and Pi, and MUST NOT expose OpenCode as a supported generation, configuration, installation, validation, or authoring target. Active repository files are tracked files outside `openspec/changes/**`; completed and current change artifacts are historical and planning evidence rather than supported runtime surfaces.

#### Scenario: Active platform inventory after removal
- **WHEN** a maintainer inventories active source, configuration, scripts, generated assets, and documentation
- **THEN** Claude Code, Codex, and Pi support remains present and no active OpenCode support surface is found

#### Scenario: Historical evidence remains intelligible
- **WHEN** a completed or current OpenSpec change records past OpenCode behavior or the rationale for its removal
- **THEN** that evidence remains intact and is excluded from the active-support absence check

### Requirement: Repository-local OpenCode assets are removed
The repository MUST remove the complete `.opencode/` tree, including tracked generated content, hand-written plugins, and ignored package artifacts. It MUST also remove the root OpenCode configuration, generator, OpenCode MCP projection, and tooling whose only remaining consumer was OpenCode.

#### Scenario: Repository cleanup is complete
- **WHEN** removal implementation finishes
- **THEN** `.opencode/`, `opencode.jsonc`, `sync-opencode.sh`, `sync-mcp.sh`, and the unused JSONC validator do not exist in the working tree or tracked file set

#### Scenario: No dormant OpenCode implementation remains
- **WHEN** a maintainer searches active scripts and configuration for OpenCode generation or projection logic
- **THEN** no disabled, commented-out, or otherwise dormant implementation is present

### Requirement: Bootstrap and validation exclude OpenCode
Bootstrap and repository validation MUST NOT generate, link, configure, validate, or require OpenCode assets. Removal of those paths SHALL preserve direct MCP installation for Claude Code and Codex, Pi MCP generation, and all existing checks for the supported platforms.

#### Scenario: Bootstrap contains only supported platform paths
- **WHEN** `init.sh` is inspected after removal
- **THEN** it contains no OpenCode source, destination, generation, manifest, or global-link lifecycle while retaining Claude Code, Codex, and Pi setup

#### Scenario: Full validation passes
- **WHEN** `make all` runs after supported mirrors are regenerated
- **THEN** it passes without OpenCode sync or MCP projection targets and still verifies Codex, Pi, plugin, configuration, and shared MCP behavior

### Requirement: Active authoring guidance excludes OpenCode
Canonical skills, generated supported-platform mirrors, repository guidance, documentation, and permissions MUST NOT instruct agents or users to create, edit, synchronize, fetch documentation for, or install OpenCode assets.

#### Scenario: Skill authoring no longer emits OpenCode commands
- **WHEN** `/skill-workbench` creates or improves a skill
- **THEN** its workflow covers canonical sources and supported generated mirrors without creating `.opencode/commands` or resolving paths into OpenCode configuration

#### Scenario: Documentation and settings match support policy
- **WHEN** a maintainer reads README, AGENTS guidance, plugin metadata, and `settings.json`
- **THEN** they describe only supported platforms and contain no OpenCode-specific permission or workflow instruction

### Requirement: Remaining generated surfaces stay source-driven
Codex and Pi outputs SHALL be regenerated only from canonical plugin sources and MUST be fresh after OpenCode guidance is removed. The productivity plugin version MUST advance from `0.50.0` to `0.51.0` to advertise the functional authoring-workflow change.

#### Scenario: Supported mirrors are synchronized
- **WHEN** the Codex and Pi sync targets run after canonical edits
- **THEN** their generated skill-workbench copies contain no OpenCode guidance and their freshness checks pass

#### Scenario: Plugin metadata records the change
- **WHEN** repository version checks inspect the modified productivity skill
- **THEN** productivity metadata reports version `0.51.0` and validation accepts the bump

### Requirement: External and unrelated state is preserved
The removal MUST NOT delete or rewrite user-owned `~/.config/opencode` state, completed OpenSpec evidence, unrelated settings, shared MCP definitions, or behavior belonging to Claude Code, Codex, and Pi.

#### Scenario: External OpenCode state is untouched
- **WHEN** the repository change is applied or `init.sh` subsequently runs
- **THEN** no command attempts to enumerate, rewrite, or delete files under `~/.config/opencode`

#### Scenario: Protected settings edit is minimal
- **WHEN** the user approves the settings change
- **THEN** implementation removes only `WebFetch(domain:opencode.ai)` and preserves every unrelated `settings.json` entry

#### Scenario: Approval is unavailable
- **WHEN** explicit approval to modify `settings.json` has not been obtained
- **THEN** implementation pauses before editing that file and does not mark the protected task complete
