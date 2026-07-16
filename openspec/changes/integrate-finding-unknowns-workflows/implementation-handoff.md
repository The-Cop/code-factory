# Implementation Handoff

## Outcome

The change integrates unknowns-aware behavior into the existing lifecycle skills without importing the upstream skill collection.
It adds a standalone read-only `/change-quiz` skill and preserves the existing ownership boundaries of `/review`, `/tour`, `/pr`, `/pr-fix`, `/do`, RFC, brainstorming, and OpenSpec workflows.

No agent definitions were changed.

## Capabilities Delivered

- Consequential blindspot reporting and explicit no-material-blindspots results in `/openspec-explore`.
- Semantics-first reference analysis, native translation gaps, and license handling in OpenSpec, `/do`, and RFC research.
- Disposable one-decision prototype rounds in `/brainstorm`, with three to five belief-labelled variants and learned requirements.
- Architecture, behavior, then polish question ordering with retrieve-before-ask and implementation-cheap stopping rules.
- Decision-first proposal and plan reviews sourced from canonical artifacts.
- Reversible deviation handling with canonical updates and validation evidence; safe pauses for behavior, scope, or irreversible changes.
- `/do` completion reporting for deviations, discoveries, unresolved review questions, consequential learning, and canonical locations.
- Medium and complex PR packaging with available demonstrations, chosen bets, expert questions, deviations, and non-goals; simple PRs remain concise.
- `/change-quiz` target/base resolution, behavioral reports, hidden criticality, one-question turns, strict grading, one retry, advisory results, and read-only pressure resistance.

## Behavioral Evidence

RED baselines showed missing blindspot/reference semantics, no prototype mode, incomplete decision summaries, weak OpenSpec deviation handling, incomplete `/do` completion reporting, partial PR packaging, and no deterministic comprehension workflow.
The skill-free change-quiz pressure run selected adjacent review behavior and had no dedicated source-backed grading contract.

GREEN application and pressure evaluations passed every defined assertion after refactoring two ambiguities:

1. `/do` now records focused validation evidence after plan amendments and before resuming.
2. `/change-quiz` now resolves current-branch PR bases, short remote base refs, explicit-base precedence, ref-correct content inspection, and hidden criticality without interim leakage.

The final current-model application run used `codex exec --json` and passed all seven change-quiz assertions.
It recorded 142,562 input tokens, 92,928 cached input tokens, 2,857 output tokens, and 1,538 reasoning tokens.
Observed wall time was approximately 43.6 seconds because the runner did not emit duration directly.

The collaboration evaluator exposed full responses but not token or duration metrics.
Multiple Claude model tiers were not available for the pressure matrix, so behavioral pressure testing is current-model only.

## Discoverability

The approved fixed set contained ten should-trigger and ten should-not-trigger prompts.
Tests loaded the source productivity and git plugins directly, exposed only skill selection, and used `claude-sonnet-5`.

- Initial description: 17/20 correct (85%).
- First trigger-phrase refinement: 17/20 correct (85%).
- Final ownership-boundary refinement: 18/20 correct (90%).
- Negative precision on the final run: 10/10.
- Positive recall on the final run: 8/10.

The two remaining false negatives were:

- `Explain PR #731's behavioral impact, then ask me one question per turn.`
- `I wrote PR #611; verify I understand its fallback behavior.`

In both cases Claude asked for inaccessible target context directly instead of loading `/change-quiz`, despite the description assigning missing-context handling to the skill.
The overall target was met, all adjacent negative intents stayed correctly routed, and further description expansion risked over-triggering ordinary review.

## Versions, Permissions, and Generation

- Productivity plugin: `0.49.0` to `0.50.0`.
- Git plugin: `0.9.0` to `0.9.1`.
- Added only `Skill(productivity:change-quiz)` to `settings.json` after explicit approval.
- Preserved the pre-existing model removal and `migrate-to-rapid@datadog-claude-plugins` addition.
- Generated OpenCode, Codex, and Pi mirrors through repository sync targets only.

## Validation

The implementation used:

```bash
make sync-opencode
make sync-codex
make sync-pi
make all
git diff --check
python3 -m json.tool settings.json
```

The final validation result and source/generated consistency check are recorded by the completed OpenSpec tasks.
