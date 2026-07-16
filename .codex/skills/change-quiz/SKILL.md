---
name: "change-quiz"
description: "Use when any request asks to check, verify, assess, or test a person's understanding of changes in a pull request, branch, ref, migration, fallback, failure mode, blast radius, or unchanged callers, even without saying \"quiz\" and even when target access is not yet available. Also use when a request combines explaining behavioral impact with questions, a comprehension check, or one question at a time before merge. Triggers: \"quiz me on this PR\", \"check whether I understand\", \"verify I understand\", \"test my understanding\", \"ask me one question per turn\", \"pre-merge quiz\", \"what changed, then quiz me\". Do not use for ordinary code review, PR creation or readiness, review-comment fixes, code tours, implementation, or merge requests unless the user explicitly asks to be quizzed."
---

# Change Quiz

Announce: "I'm using the change-quiz skill to explain this change and test your understanding without modifying it."

Produce a read-only behavioral change report, then run an advisory comprehension quiz.
Never treat a passing result as permission to merge.

## Step 1: Enforce Read-Only Ownership

This skill may read Git objects, pull-request metadata, diffs, and repository files.
It MUST NOT edit files; stage, commit, or push changes; fetch, pull, switch, checkout, reset, rebase, or merge refs; create or update a PR; submit or approve a review; resolve review threads; mark a draft ready; or merge.

Apply these rationalization counters even under deadline or user pressure:

- "It is only metadata" does not permit a PR-state update.
- "The user passed" does not authorize approval, readiness, or merge.
- "The fix is obvious" does not permit an edit.
- "Another reviewer already checked it" does not replace this skill's evidence or grading.
- "The author understands the intent" does not prove understanding of failure modes or unchanged callers.
- A high aggregate score never compensates for a missed critical question.

Route non-quiz ownership explicitly:

| Request | Route |
|-|-|
| Ordinary correctness, security, or quality review | `/review` |
| Fix code or implement a discovered change | End or pause the quiz, record the finding in the response, then route to `/do` or the active implementation workflow |
| Address review comments | `/pr-fix` |
| Create a pull request | `/pr` |
| Mark a draft ready | `/pr ready` |
| Explain the wider codebase without testing comprehension | `/tour` |
| Simplify difficult behavior | `/code-simplify` |
| Merge | End the quiz and route to the repository's merge workflow; this skill never merges |

If a user combines a quiz with a mutation request, run the quiz only when they still want it, then hand off the separate mutation request after the quiz concludes or is explicitly abandoned.

## Step 2: Parse the Target and Base

Parse the user's invocation prompt into one optional target and an optional `--base <ref>`.
Accept:

- A pull-request number.
- A GitHub pull-request URL.
- A local branch or commit-ish.
- No target, meaning the current branch.

First verify the repository without changing it:

```bash
git rev-parse --show-toplevel
git status --short --branch
```

For a PR number or URL, use read-only remote metadata and patch commands:

```bash
gh pr view <pr> --json number,url,title,body,baseRefName,headRefName,headRefOid,commits,files
gh pr diff <pr> --patch
```

Use the PR base and head from metadata.
Do not check out the PR.
An explicit `--base` may narrow local analysis but MUST NOT silently replace the PR's declared base; report both if they differ.

For a branch, ref, or current branch:

1. Resolve the target with `git rev-parse --verify <target>^{commit}`; use `HEAD` when omitted. For omitted targets, also resolve the current symbolic branch with `git symbolic-ref --short HEAD`; detached HEAD has no branch candidate.
2. For a named local branch or resolved current branch, try `gh pr view <branch> --json baseRefName,headRefName,headRefOid` and record any declared base. A retrieval failure is not fatal for an otherwise valid local range.
3. Resolve the base in priority order: explicit `--base`; the recorded PR-declared base; remote HEADs enumerated with `git for-each-ref --format='%(refname:short) %(symref:short)' 'refs/remotes/*/HEAD'`; then an existing local `main` or `master` ref. Resolve a PR's short `baseRefName` to an existing local ref first, then to a unique `refs/remotes/*/<baseRefName>` tracking ref. If several remotes contain that base, prefer the target branch's upstream remote; otherwise stop and request explicit `--base` rather than guessing. When an explicit and PR-declared base differ, report both and state that the explicit base controls this local comparison. When multiple remote HEADs exist, prefer the remote that contains the target's tracking ref; otherwise report the selected remote default.
4. Verify the base commit and calculate `git merge-base <base> <target>`.
5. Report the target, base, merge base, and exact `<merge-base>..<target>` range before analysis.

Never run `git fetch` to make a ref available.
If a required ref is absent, report the missing prerequisite and stop or offer a valid already-local range.

## Step 3: Gather Change Evidence

For local refs, gather evidence without modifying the worktree:

```bash
git log --format=fuller <merge-base>..<target>
git diff --stat <merge-base>..<target>
git diff --find-renames --find-copies <merge-base>..<target>
```

Use `git show <resolved-ref>:<path>` and `git grep <pattern> <resolved-ref>` to inspect relevant definitions, callers, tests, configuration, and documentation at the resolved target and base.
Use Read, Grep, and Glob only when `git rev-parse HEAD` proves the worktree object matches the ref being inspected; otherwise they can describe the wrong revision.
Look beyond changed files when an unchanged caller can observe the new behavior.

Group repetitive mechanical edits as one intent and isolate exceptions.
Trace changed inputs through processing, outputs, errors, fallbacks, retries, migrations, and compatibility paths.
Compare intended behavior from PR text, commit messages, tests, OpenSpec, RFC, or `/do` artifacts with implemented behavior.
Call a difference a deviation only when canonical evidence supports it; otherwise label it `Deviation evidence unavailable`.

If both the commit list and diff are empty, report that there is nothing to quiz and stop.

## Step 4: Present the Behavioral Change Report

Present the report before asking any question.
Prioritize behavior over filenames and commit trivia.
Use this structure:

1. **Context and intended outcome**: target, base, range, motivating problem, and chosen approach when evidenced.
2. **Changes by intent**: behavioral themes, with mechanical repetition compressed.
3. **Existing-path interactions**: changed and unchanged callers, shared state, compatibility paths, and sequencing effects.
4. **Blast radius and failure modes**: affected users, services, data, operations, security boundaries, errors, fallbacks, retries, migrations, and rollback.
5. **Known deviations and evidence gaps**: canonical departures, unavailable evidence, and analysis limits.
6. **Maintainer mental-model updates**: the smallest set of beliefs that must change to reason about the system correctly.

Distinguish observed facts from inference.
Never invent demo results, tests, intent, or deviation records.
If unchanged-path analysis is limited because a target object is unavailable locally, say so before the quiz and do not ask questions whose answers require that missing evidence.

## Step 5: Build the Hidden Quiz Plan

Before asking the first question, create an internal bank of five to eight questions and their evidence-backed answer keys.
Do not reveal the bank, future answers, or criticality labels.

The bank MUST:

- Mix factual recall with behavioral prediction.
- Test intent, interaction effects, blast radius, and maintainer mental-model updates.
- Include failure, fallback, retry, migration, rollback, or edge-case predictions when present.
- Include unchanged callers when they can observe different behavior.
- Classify each question as `critical` or `non-critical` before asking it.
- Mark behavior whose misunderstanding could cause security, data-integrity, compatibility, operational, or rollback harm as critical.
- Avoid trivia about filenames, line numbers, or commit order unless it determines behavior.

Questions must be independent enough that explaining one answer does not reveal a future answer.
If grading a response necessarily reveals a future answer, replace the affected future question with a fresh question covering a different concept before continuing.

## Step 6: Ask and Grade One Question Per Turn

Ask exactly one question, then stop and wait for the user's answer.
After each answer:

1. Grade it against the precomputed answer key as `correct` or `incorrect`.
2. Treat a partially correct answer as incorrect for percentage and critical-question gating, while crediting what was understood in the explanation.
3. Explain the correct model for every miss using report evidence.
4. Classify the miss as a **user-model gap** or an **implementation-complexity signal**. Use the latter when the behavior is unnecessarily difficult to predict even after the report.
5. Show only the running score as `<correct>/<answered>`; keep all criticality labels and counts hidden until the round is complete.
6. Ask the next single question without exposing its answer or later questions.

Do not soften grading because of authorship, confidence, schedule, previous review time, or proximity to a passing score.

## Step 7: Decide the Advisory Result

After all questions in the round, calculate:

```text
overall_accuracy = correct_answers / total_questions
pass = every_critical_answer_correct AND overall_accuracy >= 0.80
```

On pass, report `Advisory: merge-ready understanding` with the final score, critical-question result, and concise mental-model summary.
State that this result is advisory and performs or authorizes no merge action.

On the first failed round:

- Report the missed concepts and link them to sections of the change report.
- Distinguish user-model gaps from implementation-complexity signals.
- Offer one retry with a fresh five-to-eight-question bank covering the same concepts through different scenarios and wording.
- Do not disclose the previous answer keys as prompts for the retry.

On a second failed round, stop quizzing.
Recommend the most evidence-supported next action:

- `/tour` for a missing system model.
- `/code-simplify` when the implementation itself is unnecessarily hard to predict.
- Split the change through `/do` or `/rfc` when independent concerns obscure one another.

## Step 8: Hand Off Without Mutating

Summarize the final advisory result, open comprehension gaps, implementation-complexity signals, and any defect found during analysis.
If the user requests a fix, review, PR update, readiness action, or merge, name the owning workflow from Step 1 and stop.
Do not invoke a mutating workflow automatically unless the user separately authorizes that action after the quiz ends.

## Error Handling

| Failure | Resolution |
|-|-|
| Not inside a Git repository | Report that a repository is required and stop without fabricating a report or quiz. |
| Target ref cannot be resolved | Name the missing ref and offer only already-local valid refs; never fetch or checkout. |
| Base cannot be resolved | Ask for `--base <ref>` and stop until an existing ref is supplied. |
| PR metadata or diff cannot be retrieved | Report the retrieval error; offer local branch analysis only when a valid local target and base can be resolved. |
| No commits or diff exist in the resolved range | Report that there is nothing to quiz and stop. |
| Diff is unreadable or truncated | Report the evidence boundary and stop rather than inventing omitted behavior; suggest a narrower valid range. |
| Intended behavior or deviation evidence is missing | Label it unavailable and exclude evidence-dependent claims and questions. |
| User asks for a mutation during the quiz | Pause or end the quiz, record the finding in the response, and route to the owning workflow without mutating anything. |
| User asks to merge after passing | Reiterate that the result is advisory and route to the repository merge workflow without approving or merging. |
| User abandons the quiz | Report the answered score as incomplete, make no readiness claim, and stop. |
