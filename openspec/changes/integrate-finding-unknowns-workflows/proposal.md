## Why

The repository has strong feature, RFC, OpenSpec, brainstorming, and PR workflows, but their user-facing checkpoints do not consistently surface unknown unknowns, tacit preferences, high-impact decisions, or implementation deviations.
Integrating those practices into the existing skills and adding a focused comprehension quiz will reduce avoidable rework without importing overlapping skills wholesale.

## What Changes

- Add structured blindspot and semantics-first reference analysis to read-only exploration and research workflows.
- Add an optional divergent-prototype mode to `/brainstorm` for decisions users can evaluate more easily by reacting to examples.
- Order clarification questions by blast radius and stop asking when remaining uncertainty is cheaper to resolve during implementation.
- Present plans and proposals with tweakable decisions, alternatives, and the riskiest assumption before mechanical work.
- Keep deviations and discovered edge cases in canonical OpenSpec and `/do` artifacts instead of introducing a separate implementation-notes workflow.
- Improve complex PR packaging with available demos, expert-review questions, deviations, and explicit non-goals.
- Add a standalone, read-only `/change-quiz` skill that explains a branch or PR and tests the user's understanding before merge.
- Add behavioral RED/GREEN tests and discoverability evaluations for every modified or new skill behavior.
- Update source documentation, plugin metadata, and the explicit skill permission entry; preserve unrelated `settings.json` changes and obtain approval before editing that file.
- Refresh generated OpenCode, Codex, and Pi assets only through repository sync targets, then run `make all`.

## Capabilities

### New Capabilities

- `unknowns-aware-workflows`: Existing exploration, brainstorming, planning, implementation, and PR workflows surface consequential unknowns at the stage where they are cheapest to resolve.
- `change-quiz`: Users can request a read-only change report and graded comprehension quiz for a branch or pull request before deciding whether it is merge-ready.

### Modified Capabilities

None. This repository has no existing OpenSpec capability specifications.

## Impact

- Productivity skill sources under `productivity/skills/`, especially `brainstorm`, `do`, `rfc`, and the OpenSpec skills.
- Git skill source `git/skills/pr/SKILL.md` for complex PR packaging.
- New source skill `productivity/skills/change-quiz/SKILL.md`.
- `README.md`, `productivity/.claude-plugin/plugin.json`, `git/.claude-plugin/plugin.json`, and `settings.json`.
- Generated `.opencode/`, `.codex/`, and `.pi/` mirrors produced by the existing sync scripts.
- No runtime application APIs or external dependencies are changed.
