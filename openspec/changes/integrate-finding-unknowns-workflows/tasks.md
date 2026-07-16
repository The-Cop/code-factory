## 1. Behavioral Baselines

- [x] 1.1 Create a temporary evaluation workspace outside managed/generated directories and snapshot every affected source skill before editing it.
- [x] 1.2 Define application assertions for blindspot analysis, reference semantics, prototype divergence, question ordering, decision-first review, deviation handling, completion reporting, and proportional PR packaging.
- [x] 1.3 Define pressure and application assertions for `change-quiz`, including honest grading, critical-question gating, retry limits, and refusal to mutate code or PR state.
- [x] 1.4 Run RED baseline evaluations against the existing-skill snapshots and without `change-quiz`; save outputs, full transcripts, token counts, durations, and observed failures.
- [x] 1.5 Draft ten should-trigger and ten should-not-trigger queries for `change-quiz` and obtain user approval before discoverability testing.

## 2. Exploration and Reference Semantics

- [x] 2.1 Update `productivity/skills/openspec-explore/SKILL.md` to produce the structured blindspot output, revised request, and explicit no-material-blindspots result required by the spec.
- [x] 2.2 Add semantics-first reference analysis, translation-gap reporting, and license handling to the relevant `/openspec-explore`, `/do`, and `/rfc` research instructions without copying upstream instruction text.
- [x] 2.3 Add focused error-handling cases for unavailable reference source, unclear license, and insufficient evidence.

## 3. Brainstorming and Clarification

- [x] 3.1 Add an explicit prototype mode and argument hint to `productivity/skills/brainstorm/SKILL.md` while preserving the default problem-sharpening workflow.
- [x] 3.2 Implement one-decision scope, three-to-five divergent variants, belief labels, disposable visual/text artifacts, reaction collection, and learned-requirement reporting in prototype mode.
- [x] 3.3 Update `/brainstorm`, `/do`, and `/rfc` dispatch instructions to order questions by architecture, behavior, then polish; retrieve discoverable answers; and stop when remaining uncertainty is cheaper to resolve during implementation.

## 4. Decision-First Planning and Canonical Deviations

- [x] 4.1 Update `productivity/skills/openspec-propose/SKILL.md` to present tweakable decisions, alternatives, the riskiest assumption, and known-unknown pivot signals before mechanical artifacts.
- [x] 4.2 Update `/do` and `/rfc` plan-review instructions to generate decision-first user summaries from their canonical artifacts without changing execution dependency order.
- [x] 4.3 Update `productivity/skills/openspec-apply-change/SKILL.md` to classify deviations, update canonical artifacts for reversible choices, validate before continuing, and pause for behavior, scope, or irreversible changes.
- [x] 4.4 Update `/do` completion reporting to summarize deviations, discovered edge cases, unresolved review questions, the most consequential learning, and canonical artifact locations without creating a second notes file.

## 5. Proportional PR Packaging

- [x] 5.1 Update `git/skills/pr/SKILL.md` so medium and complex PR descriptions use available demonstrations, the problem and chosen bet, expert-review questions, known deviations, and explicit non-goals.
- [x] 5.2 Preserve the existing concise simple-PR path and make missing demonstrations or deviation evidence explicit instead of fabricating content.

## 6. Change Quiz Skill

- [x] 6.1 Create `productivity/skills/change-quiz/SKILL.md` with valid local frontmatter, precise positive and negative triggers, an announce line, numbered steps, read-only tool boundaries, and complete error handling.
- [x] 6.2 Implement target and base resolution for PRs, branches, refs, and the current branch without checkout or state mutation.
- [x] 6.3 Implement the behavioral change report grouped by intent, existing-path interactions, blast radius, deviations, and maintainer mental-model updates.
- [x] 6.4 Implement five-to-eight one-at-a-time recall and prediction questions with hidden criticality classification, running score, honest explanations, and no future-answer leakage.
- [x] 6.5 Implement pass criteria requiring every critical answer plus 80 percent overall accuracy, one fresh retry, and guided-tour/simplify/split recommendations after a second failure.
- [x] 6.6 Add bright-line read-only rules, rationalization counters, and routing for fix, review, PR, ready, and merge requests that fall outside `change-quiz` ownership.

## 7. Behavioral and Discoverability Validation

- [x] 7.1 Run GREEN evaluations using the same prompts and assertions as the RED baselines; save outputs, full transcripts, timing data, and comparisons.
- [x] 7.2 Refactor generalized skill instructions and rerun failing evaluations until the defined assertions pass or results plateau with documented limitations.
- [x] 7.3 Run the user-approved `change-quiz` discoverability queries, target at least 90 percent correct triggering, and iterate the description no more than three times.
- [x] 7.4 Apply the skill-quality checklist to every changed skill, including structure, description boundaries, filler scan, token efficiency, and first-read clarity.
- [x] 7.5 Remove temporary evaluation workspaces after recording the final evidence in the implementation handoff.

## 8. Documentation, Permissions, and Versions

- [x] 8.1 Update `README.md` quick reference and detailed workflow documentation for `change-quiz` and the integrated unknowns-aware behaviors, including concise upstream inspiration attribution.
- [x] 8.2 Bump `productivity/.claude-plugin/plugin.json` from `0.49.0` to `0.50.0` and update its description for the new skill.
- [x] 8.3 Bump `git/.claude-plugin/plugin.json` from `0.9.0` to `0.9.1` for the compatible `/pr` enhancement.
- [x] 8.4 Request explicit user approval to modify `settings.json`; after approval, add only `Skill(productivity:change-quiz)` while preserving the existing model removal and `migrate-to-rapid` plugin addition.

## 9. Generation and Repository Validation

- [x] 9.1 Run `make sync-opencode`, `make sync-codex`, and `make sync-pi` so generated mirrors contain the source changes without direct generated-file edits.
- [x] 9.2 Run `make all` and fix any frontmatter, structure, reference, version, sync, or lint failure before completion.
- [x] 9.3 Inspect the final diff and status to verify source/generated consistency, intended version and permission changes, preserved pre-existing edits, and no unrelated files.
- [x] 9.4 Report changed capabilities, behavioral evidence, discoverability results, validation commands, approval-dependent decisions, and any remaining limitations.
