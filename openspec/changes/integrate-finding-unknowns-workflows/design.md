## Context

The repository owns Claude-source skill definitions under `productivity/skills/` and `git/skills/`.
OpenCode, Codex, and Pi copies are generated from those sources and must not be edited directly.

Existing workflows already contain much of the required machinery:

- `/do` records assumptions, decisions, discoveries, plan amendments, validation results, and retrospective outcomes.
- `/brainstorm` sharpens problem statements but deliberately parks solution ideas.
- `/rfc` researches, explores, plans, reviews, and writes technical documents.
- `/openspec-*` covers read-only exploration, artifact generation, task application, and archive.
- `/pr` analyzes changes and produces tiered PR descriptions.

The missing layer is consistent user-facing treatment of unknowns across those workflows and a dedicated way to verify that a user understands a change before merging it.

Constraints:

- Adapt upstream ideas rather than copying the eight external skills wholesale.
- Preserve each existing skill's primary responsibility and avoid overlapping new commands.
- Add `change-quiz` to the productivity plugin because it teaches change comprehension rather than mutating Git state.
- Obtain explicit approval before modifying `settings.json` and preserve its existing unrelated changes.
- Avoid agent-definition changes in the first implementation; express new behavior in skill instructions and dispatch prompts.
- Follow skill-workbench RED/GREEN testing and discoverability evaluation requirements.

## Goals / Non-Goals

**Goals:**

- Surface consequential unknowns before they become expensive implementation changes.
- Give users cheap artifacts to react to when preferences are difficult to state directly.
- Focus questions and review attention on decisions with the largest downstream effect.
- Keep implementation reality synchronized with canonical plans and specifications.
- Give users an honest, repeatable comprehension gate before merge.
- Preserve repository conventions, source ownership, generated sync, and validation guarantees.

**Non-Goals:**

- Import or install the upstream skill collection.
- Add standalone replacements for implementation planning, implementation notes, interviews, references, prototypes, or pitch packaging.
- Enforce GitHub merge protection or merge a pull request from `change-quiz`.
- Replace `/review`, `/tour`, `/pr`, or `/pr-fix`.
- Rewrite unrelated skill content or modify application runtime behavior.
- Change productivity agent definitions unless implementation proves skill-level dispatch instructions insufficient and the user separately approves that expansion.

## Decisions

### 1. Integrate practices by lifecycle stage

Each practice will live in the existing workflow that already owns its stage:

- `/openspec-explore` will provide a structured blindspot pass and semantics-first reference analysis when the request involves unfamiliar or reference-led territory.
- `/brainstorm` will gain an explicit prototype mode that explores one decision per round with three to five materially different disposable variants.
- `/do`, `/rfc`, and `/openspec-propose` will order unresolved questions by blast radius and present decision-first review summaries.
- `/openspec-apply-change` will distinguish reversible deviations from scope-changing decisions and keep affected artifacts current.
- `/do` will expose its existing deviations and discovered edge cases in completion reporting rather than introducing another notes file.
- `/pr` will add pitch-packaging elements only for medium or complex changes and only when supporting evidence exists.

Alternative considered: add each upstream workflow as a standalone skill.
This was rejected because it would duplicate existing lifecycle ownership, increase trigger conflicts, and expand maintenance without adding distinct capabilities.

### 2. Keep unknowns output structured and consequential

Blindspot-oriented output will prioritize information that can change scope, architecture, behavior, or review strategy.
The reusable structure is:

1. Landmines and likely failure modes.
2. Hidden constraints and decisions already embedded in the repository or domain.
3. Examples that calibrate what good looks like.
4. High-impact questions with evidence-backed provisional answers.
5. A revised request or decision summary that incorporates the findings.

If no material blindspots exist, the workflow will say so instead of inventing concerns.

### 3. Treat references as semantic specifications

When a user points at code, a repository, or another implementation as a reference, the workflow will summarize behaviors and guarantees before proposing target changes.
It will distinguish deliberate behavior from incidental syntax, identify translation gaps, and check licensing before copying any implementation text.

Alternative considered: copy or transliterate the reference implementation.
This was rejected because target-repository conventions define implementation style and licenses may prohibit source reuse.

### 4. Make prototype mode explicit and disposable

Prototype behavior will be an explicit `/brainstorm` mode rather than the default problem-sharpening path.
The skill will keep one decision in scope, generate three to five variants that test different beliefs, and summarize the preference revealed by the user's reactions.
Visual prototypes may use self-contained HTML with fake data; approach, naming, or tone prototypes may use compact textual artifacts.
No prototype may be wired into production code.

Alternative considered: modify the brainstormer agent to own both problem discovery and prototyping.
This was deferred because skill-level routing keeps the behaviors separable and avoids an agent-definition approval gate.

### 5. Make plans decision-first at review boundaries

Internal task plans may remain ordered for execution, but user-facing plan and proposal reviews will lead with:

- What is being built.
- The chosen approach.
- The riskiest assumption.
- Decisions the user is most likely to change, with one alternative and the cost of changing later.
- Known unknowns, the default response, and the signal that would trigger a pivot.
- Mechanical work in a compressed final section.

Questions will be ordered as architecture-changing, behavior-defining, then polish.
The workflow will stop questioning when remaining uncertainty is cheaper and safer to discover during implementation.

### 6. Keep deviations in canonical artifacts

`/openspec-apply-change` will not create a separate `implementation-notes.md`.
For a reversible deviation, it will select the easiest-to-reverse option, update affected design, spec, or task artifacts, record the rationale, and continue after focused validation.
For an irreversible, behavior-changing, or scope-expanding deviation, it will stop at a safe checkpoint and request user direction before continuing.

`/do` will retain its existing event log, plan-amendment, discovery-bundle, and snapshot mechanisms.
Its completion report will summarize deviation count, discovered edge cases, unresolved review questions, and the most consequential learning.

### 7. Add `change-quiz` as a read-only productivity skill

`change-quiz` will accept a PR number or URL, a branch or ref, or default to the current branch against its resolved base.
It will gather commits and diffs without modifying the worktree, Git state, PR state, or remote state.

The report will contain:

- Context and intended outcome.
- Changes grouped by intent rather than file.
- Interactions with existing code paths and blast radius.
- The key mental-model updates a maintainer needs.

The quiz will ask five to eight questions one at a time.
It will mix recall with behavioral prediction and emphasize deviations, failure modes, and interaction effects.
Questions will be classified internally as critical or non-critical before they are asked.

Passing requires every critical question to be answered correctly and at least 80 percent overall accuracy.
A miss will receive the correct explanation and be identified as either a user-model gap or evidence that the change is too difficult to reason about.
One fresh retry round is allowed.
After two failed rounds, the skill will recommend `/tour`, simplifying the change, or splitting it instead of continuing to quiz indefinitely.

The merge-ready result is advisory.
The skill will never merge, approve, mark ready, push, commit, edit code, or resolve review threads.

Alternative considered: add quiz mode to `/review` or `/pr`.
This was rejected because reviewing code quality and testing maintainer comprehension are distinct user intents with different interaction patterns.

### 8. Apply PR pitch packaging proportionally

For medium and complex PRs, `/pr` will use available user-facing demonstrations first, then explain the problem and chosen bet, identify expert-review questions, summarize known deviations, and fence out-of-scope work.
Missing screenshots, recordings, or implementation notes will be reported as unavailable rather than fabricated.
Simple PRs will retain their concise path.

### 9. Test skills behavior before deployment

Implementation will snapshot each existing skill before changing it and create realistic application scenarios for the new behavior.
With-skill and baseline runs will use the same prompt and capture outputs, transcripts, token counts, and durations.

Test groups will cover:

- Blindspot and reference-semantics recognition.
- Divergent prototype generation and learning extraction.
- Blast-radius question ordering and decision-first plan review.
- Reversible versus scope-changing deviation handling.
- Proportional PR packaging.
- `change-quiz` reporting, grading, read-only discipline, and pressure resistance.

The `change-quiz` description will also receive should-trigger and should-not-trigger evaluation, with user review of queries before execution as required by skill-workbench.
Temporary evaluation artifacts will be removed after results are recorded in the implementation handoff.

### 10. Version, document, and generate from sources

The productivity plugin will receive a minor version bump because it gains a new skill.
The git plugin will receive a patch bump because `/pr` behavior changes compatibly.
`README.md` will document the new skill and updated workflows.

After explicit approval, the implementation will add only `Skill(productivity:change-quiz)` to `settings.json` and preserve the existing model/plugin edits already present in the worktree.

Generated mirrors will be refreshed through:

```bash
make sync-opencode
make sync-codex
make sync-pi
make all
```

No generated skill file will be edited directly.

### 11. Attribute inspiration without copying wholesale

The implementation will adapt behavior from the MIT-licensed `finding-unknowns-skills` project and retain a concise source attribution in repository documentation or the relevant skill reference material.
Substantial upstream instruction text will not be copied verbatim.

## Risks / Trade-offs

- Trigger overlap between `change-quiz`, `/review`, `/tour`, and `/pr` could select the wrong skill. → Use explicit positive and negative triggers and test discoverability with near-miss prompts.
- Adding unknowns analysis everywhere could make lightweight tasks verbose. → Gate detailed output on unfamiliarity, consequential ambiguity, explicit invocation, or medium/complex change tiers.
- Prototype mode could blur into production implementation. → Mark artifacts disposable, restrict scope to one decision, and forbid wiring prototypes into real code.
- Decision-first summaries could diverge from execution plans. → Generate summaries from the same canonical artifacts and update both when decisions change.
- Deviation handling could silently expand behavior. → Continue only for reversible choices that preserve intended behavior; stop for behavior or scope changes.
- A quiz could create false confidence. → Require all critical answers, include prediction questions, explain misses, and keep merge readiness advisory.
- Existing `settings.json` changes could be overwritten. → Inspect the live diff and use a minimal patch after explicit approval.
- Cross-plugin edits increase release coordination. → Version productivity and git independently and run repository-wide sync and validation.

## Migration Plan

1. Create behavioral baselines and snapshots for each affected skill before edits.
2. Update productivity source skills and add the new `change-quiz` source skill.
3. Update `/pr` source behavior in the git plugin.
4. Run with-skill behavioral tests and refactor instructions until the scenarios pass.
5. Review and execute discoverability queries for `change-quiz`.
6. Update README and plugin versions.
7. Request explicit approval, then minimally add the `settings.json` permission while preserving existing edits.
8. Run source-to-generated sync targets and `make all`.
9. Review the final diff for source/generated consistency and unrelated modifications.

Rollback consists of reverting the source skill and metadata changes, removing the new permission and skill, regenerating all mirrors, and rerunning `make all`.

## Open Questions

- Will the user approve the required `settings.json` permission edit during implementation? The apply workflow must pause before that task until approval is explicit.
- Are multiple Claude model tiers available for `change-quiz` pressure testing? If not, record the limitation and complete current-model behavioral testing rather than silently claiming cross-model coverage.
