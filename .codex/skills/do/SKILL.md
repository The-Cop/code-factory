---
name: "do"
description: "Use when the user wants to implement a feature with full lifecycle management. Triggers: \"do\", \"implement feature\", \"build this\", \"create feature\", \"start new feature\", \"resume feature work\", or references to FEATURE.md state files."
---

# Feature Development Orchestrator

Announce: "I'm using the /do skill to orchestrate feature development with lifecycle tracking."

## Outer Loop Rules

These rules govern the SKILL.md outer loop.
Phase-level rules passed to every orchestrator dispatch live in [references/workflow-rules.md](references/workflow-rules.md).
Detailed phase behaviors live in [references/phase-flow.md](references/phase-flow.md).

- **Preferences before everything.** Step 1 runs IMMEDIATELY on invocation,
  before discovering runs, parsing arguments, or doing any phase work.
- **Never skip phases.** Every feature goes through REFINE → RESEARCH → PLAN_DRAFT → PLAN_REVIEW → EXECUTE → VALIDATE → DONE.
  "Simple" features are where unexamined assumptions cause the most rework.
  REFINE can be brief for well-specified descriptions, but phases themselves are non-negotiable.
- **State is sacred.** State lives in `~/docs/plans/do/<short-name>/`, never in the repo.
  Update FEATURE.md frontmatter after every phase transition — state files are the only handoff mechanism between phases.
- **Hard stop on blockers.** When encountering ambiguity or missing information, stop and report.
  Guessing creates cascading errors that multiply rework.
- **Discovered work must be filed, not disavowed.** Failures, broken tests, or out-of-scope issues surfaced in any phase
  MUST become a `discovered_from` bundle in `tasks/`. Deleting, disabling, or silently skipping a failing test is a
  workflow violation. See Discovery Capture Protocol in phase-flow.md.
- **Source isolation (worktree/workspace modes).** No code files written in the original source directory —
  the worktree or workspace is the only write target.
- **Subagent dispatch discipline.** Instruct subagents to keep final responses under 2000 characters (outcomes, not process).
  Never call TaskOutput twice for the same Task — if it times out, increase the timeout instead of re-reading.

## Interaction Modes

**Interactive (default):** User reviews and explicitly approves outputs at every phase transition before the outer loop proceeds.
Feedback can be provided at any checkpoint.

**Autonomous (`--auto` flag):** Proceed through all phases without interruption;
report at completion or on blockers.

Phase-transition checkpoints — interactive mode pauses and waits for approval at each:

| After Phase | What the user reviews |
|-|-|
| REFINE | Problem statement, chosen approach, scope, acceptance criteria |
| RESEARCH | Codebase map, research brief, assumptions, risks |
| PLAN_DRAFT | Milestones, task breakdown, validation strategy |
| PLAN_REVIEW | Review feedback, final plan readiness |
| EXECUTE (per batch) | Completed tasks, test status, discoveries |
| VALIDATE | Validation results, quality scorecard |
| DONE | PR creation, merge, keep branch, or discard |

## State Storage and Iteration

All state lives in `~/docs/plans/do/<short-name>/`, independent of the working directory.
`<short-name>` is kebab-case from the feature description (max 40 chars).
See [references/state-file-schema.md](references/state-file-schema.md) for the full file listing and schemas.

After Step 1 (preferences), analyze the user's query:

- **Fresh start** (new feature description) → Step 4 (new mode)
- **Resume** (references a state file or short-name) → Step 5a
- **Iterating** (feedback on current run) → address within the current phase
- **No arguments** → handle per Step 3

## Step 1: Ask Preferences (ALWAYS FIRST)

This step runs IMMEDIATELY on invocation, before discovering runs or doing any other work.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

### 1a: Parse Flags

Parse `$ARGUMENTS` for flags and strip them from the feature description:

- `--auto` → pre-select autonomous mode
- `--branch` → pre-select branch-only workdir mode
- `--budget <USD>` → validate positive number, store as `token_budget_usd` (invalid → warn and ignore)

Store the stripped feature description as `feature_description` — used for workspace dispatch.
If `--budget` is not present, `token_budget_usd` remains null (unlimited).

### 1b: Workspace and Automation Preferences

**Fast-path — `--branch` + `--auto`:** skip all preference questions.
Set `workdir_mode: branch_only`, `base_branch: default`, `interaction_mode: autonomous`. Proceed to Step 2.

**Fast-path — `--branch` only:** skip the "Feature setup" question,
set `workdir_mode: branch_only`, and jump to the branch-and-automation question below.

**Otherwise, present ALL four options exactly as written. Never omit the Workspace option:**

```
AskUserQuestion(
  header: "Feature setup",
  question: "How should this feature be developed?",
  options: [
    "Worktree + branch (Recommended)" -- Isolated worktree with a feature branch. Source repo stays completely clean.,
    "Branch only" -- Feature branch in the current directory.,
    "Current branch" -- Work directly on the current branch.,
    "Workspace" -- Remote cloud dev environment. Spins up a remote CDE on EC2. Claude starts there with /do to create a branch and work.
  ]
)
```

**If `workdir_mode` is `workspace`:** skip the branch question.
No local branch — the remote `/do` session handles creation.
If `--auto` was not in arguments, ask automation mode only:

```
AskUserQuestion(
  header: "Automation mode",
  question: "Should the remote workspace session run autonomously?",
  options: [
    "Interactive (Recommended)" -- Review at each phase in the workspace,
    "Autonomous" -- Proceed without interruption in the workspace
  ]
)
```

Record: `workdir_mode: workspace`, `interaction_mode` from above, `base_branch: null`. Proceed to Step 2.

**If `workdir_mode` is `current_branch`:** skip the branch question; ask interaction mode only.

**Otherwise (worktree or branch_only):** detect the current and default branches,
then present a combined branch-and-automation question.

```bash
CURRENT_BRANCH=$(git symbolic-ref --short HEAD)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
# Fallback: main
```

**Replace `<name>` in option titles with the actual current branch. Use descriptions EXACTLY as written —
do NOT substitute branch names into descriptions.**

```
AskUserQuestion(
  header: "Branch and automation",
  question: "Configure the new feature branch:",
  options: [
    "Default branch, Interactive (Recommended)" -- Branch off the repo default. Review at each phase.,
    "Default branch, Autonomous" -- Branch off the repo default. Proceed without interruption.,
    "Current branch (<name>), Interactive" -- Branch off your current checkout. Review at each phase.,
    "Current branch (<name>), Autonomous" -- Branch off your current checkout. Proceed without interruption.
  ]
)
```

**If the current branch IS the default branch:** omit the "Current branch" options —
show only the two "Default branch" options and the free-text option.

If the user types a custom branch name, use it as the base and ask interaction mode separately.
**If `--auto` was in arguments:** skip the automation question — present only the base branch options.

Record:

- `workdir_mode`: `worktree` | `branch_only` | `current_branch` | `workspace`
- `base_branch`: `default` | `<current branch>` | `<user-typed branch>` (null for workspace)
- `interaction_mode`: `interactive` | `autonomous`

### 1c: Source Isolation Rule

| Workdir Mode | Code changes | State files | Source repo touched? |
|-|-|-|-|
| **Worktree + branch** | Worktree only | `~/docs/plans/do/<short-name>/` | **No** |
| **Branch only** | Current repo (on branch) | `~/docs/plans/do/<short-name>/` | Yes (code only, on branch) |
| **Current branch** | Current repo | `~/docs/plans/do/<short-name>/` | Yes (code only) |
| **Workspace** | Remote workspace | Remote (workspace `/do` session) | **No (locally)** |

State files always live in `~/docs/plans/do/`, never in the repo.

## Step 2: Discover Existing Runs

Run `Glob(pattern="*/FEATURE.md", path="~/docs/plans/do")` to find existing runs.
For each file, read it and treat runs without `current_phase: DONE` as active.
Parse active runs for: `short_name`, `current_phase`, `phase_status`, `branch`, `worktree_path`, `last_checkpoint`.

**Stale detection:** compute age from `last_checkpoint` — `<7d` active, `7-30d` stale, `>30d` abandoned.
Include age markers in the run list. Offer to archive stale/abandoned runs to `~/docs/plans/do/.archive/`.

## Step 3: Mode Selection

When arguments are a feature description, start the full workflow.
Do not implement directly, regardless of perceived simplicity.

Classify in priority order:

1. **Analysis-only detection** — `$ARGUMENTS` contains analysis keywords
   ("analyze", "assess", "evaluate", "audit", "compare", "investigate") WITHOUT implementation keywords
   ("implement", "build", "create", "add", "fix"):
   - Route through REFINE → RESEARCH only (skip PLAN_DRAFT onward)
   - Do NOT create a feature branch or worktree — analysis writes to an output file, not the repo
   - Report findings as a standalone analysis document

2. **State file reference** — `$ARGUMENTS` contains `FEATURE.md` or is a path to an existing state file
   (NOT a URL starting with `http://` or `https://`):
   - Verify the file exists, parse phase status, route to **Resume Mode** (Step 5a)
   - Inherit `interaction_mode` from the state file unless overridden in Step 1

3. **Feature description, no active runs** → **New Mode** (Step 4)

4. **Feature description, active runs exist:**
   - **Autonomous mode:** auto-select "Start new feature"
   - **Interactive mode:**

```
AskUserQuestion(
  header: "Active runs found",
  question: "Found <N> active feature runs. What would you like to do?",
  options: [
    "Start new feature" -- Begin a fresh workflow for the new feature,
    "<short-name>: <feature-name> (phase: <phase>)" -- Resume this run
  ]
)
```

5. **No arguments:** list active runs (if any) and ask which to resume, or prompt for a new feature description.

## Step 4: Workdir Setup (New Mode)

Preferences were collected in Step 1 — execute the chosen setup.

### 4a: Execute Workdir Setup

**For `base_branch: default`** — use the `/worktree` and `/branch` skills (they auto-detect main/master):

| Choice | Actions |
|-|-|
| **Worktree + branch** | `Skill("worktree", "<slug>")` → `Skill("branch", "<slug>")` → `WORKDIR_PATH` = worktree path |
| **Branch only** | `Skill("branch", "<slug>")` → `WORKDIR_PATH` = `REPO_ROOT` |
| **Current branch** | Record current branch → `WORKDIR_PATH` = `REPO_ROOT` |
| **Workspace** | `workspaces create <ws-prefix>-<slug> --repo <repo> --branch <default> ...` (run_in_background). See 4a-workspace. |

**For custom `base_branch`** — `/worktree` and `/branch` auto-detect main, so use direct git commands:

| Choice | Actions |
|-|-|
| **Worktree + branch** | `git fetch origin <base>` → `git worktree add --detach <path> origin/<base>` → `cd <path>` → `git checkout -b <branch-name>` |
| **Branch only** | `git fetch origin <base>` → `git checkout -b <branch-name> origin/<base>` |

**Naming conventions:**

- Branch: `<prefix>/<slug>` where `prefix` = first token of `git config user.name`, lowercased
- Workspace: `<ws-prefix>-<slug>` where `ws-prefix` = `whoami | cut -d. -f1`

**Workspace creation flags:** `--region eu-west-3 --instance-type aws:m6gd.4xlarge --shell fish`

### 4a-workspace: Post-Creation Setup

When the background `workspaces create` completes:

1. **Construct the remote `/do` command** from stored `feature_description` + `--branch` +
   (`--auto` if autonomous) + (`--budget <X>` if set):
   `/do <feature_description> --branch [--auto] [--budget <X>]`

2. **SSH in, start tmux with Claude running `/do`:**

   ```bash
   REMOTE_CMD="/do <feature_description> --branch [--auto] [--budget <X>]"
   ssh -A workspace-<ws-name> "cd /workspaces/<repo> && tmux new-session -d -s main -c /workspaces/<repo> \"claude '$REMOTE_CMD'\""
   ```

   If SSH fails, run `workspaces ssh-config <ws-name>` then retry.
   Quoting matters — escape single quotes in the feature description before embedding.

3. **Report the join command and STOP:**

   ```
   Workspace "<ws-name>" is ready. Claude is running `/do` on the remote session.

   Join:        ssh -A workspace-<ws-name> -t "tmux new-session -A -s main"
   iTerm2 -CC:  ssh -A workspace-<ws-name> -t "tmux -CC new-session -A -s main"
   IDE:         workspaces connect <ws-name> --editor intellij
   Status:      workspaces list
   Delete:      workspaces delete <ws-name>
   ```

   **STOP here.** The remote Claude session handles branch creation and feature development.
   Do NOT proceed to Step 4b or any further step locally.

### 4b: Initialize State Directory

```bash
SHORT_NAME="<derived-slug>"   # kebab-case from feature description, max 40 chars
STATE_ROOT=~/docs/plans/do
mkdir -p "$STATE_ROOT/$SHORT_NAME"
```

Create `$STATE_ROOT/$SHORT_NAME/FEATURE.md` using the schema in state-file-schema.md,
with `current_phase: REFINE` and `phase_status: not_started`.

### 4c: Context Hydration

Deterministically extract and pre-fetch external references from the feature description.
This grounds downstream phases in actual content rather than link-only references.

| Source | Detection | Action |
|-|-|-|
| GitHub repos | `github.com/<owner>/<repo>` (no `/pull/`, `/issues/`, etc.) | `git clone --depth 1` to `/tmp/<repo>`, set as analysis target |
| URLs (http/https) | Non-repo URLs in feature description | `WebFetch` each, save summary to `CONTEXT/` |
| GitHub PRs/issues | `#NNN` or GitHub URL patterns | `gh pr view` or `gh issue view`, save to `CONTEXT/` |
| Ticket references | JIRA-NNN, PROJ-NNN patterns | CLI fetch if available, save to `CONTEXT/` |

Skip if no external references are found.
Pass hydrated content to the orchestrator via `<hydrated_context>` tags in the dispatch prompt.

### 4d: Brainstorm Option (Interactive Mode Only)

Skip entirely in autonomous mode.
Ask whether the user wants to brainstorm first:

```
AskUserQuestion(
  header: "Brainstorm?",
  question: "Would you like to brainstorm this idea before starting refinement?",
  options: [
    "Start refinement (Recommended)" -- Jump straight into refining the feature specification,
    "Brainstorm first" -- Explore and sharpen the idea with a thinking partner before committing to building it
  ]
)
```

**If "Start refinement":** proceed to Step 5.

**If "Brainstorm first":**

1. Create the brainstorm file:

   ```bash
   mkdir -p ~/docs/brainstorms
   TODAY=$(date +%Y-%m-%d)
   ```

   Derive a brainstorm slug (kebab-case, max 40 chars).
   Create `~/docs/brainstorms/<slug>.md` with the initial idea (same template as `/brainstorm`).

2. Dispatch the brainstormer agent using the Brainstormer template in
   [references/dispatch-templates.md](references/dispatch-templates.md).

3. After completion, read `~/docs/brainstorms/<slug>.md` and pass the content as
   `<brainstorm_context>` in the REFINE dispatch. Proceed to Step 5.

## Step 5: Phase Execution Loop

New and resume modes converge here.
The outer loop dispatches a **fresh, phase-scoped orchestrator** for each phase —
each gets only the context it needs, writes results to state files, and returns.
The outer loop reads state and dispatches the next phase.
This eliminates context exhaustion from a single long-running orchestrator.

### 5a: Resume Preamble (Resume Mode Only)

1. Read the state file → determine current phase, status, and workdir configuration.
2. **Reconcile git state:** if `worktree_path` is set, verify the worktree exists and `cd` into it.
   Check that the branch matches. Handle dirty tree per `uncommitted_policy` in state.
3. Set `WORKDIR_PATH` from state `worktree_path` (or `repo_root` if null).
4. **State-reality verification:** compare FEATURE.md Progress against `git log`.
   For each "complete" task with a commit SHA, verify the SHA exists in log.
   Check task bundle statuses against git reality.
   Check the next pending task's preconditions against current codebase state.
   Store discrepancies as `state_drift` for the next orchestrator dispatch.
5. **Pending-triage surfacing:** count discovered bundles with
   `Grep(pattern="^status: discovered$", path="tasks/", output_mode="count")`.
   If non-zero, include a one-line summary in the resume message:
   `N discovered bundle(s) pending triage (see SNAPSHOT.md Discovered Tasks; triaged at DONE).`
   Do not auto-triage on resume — the user decides fate at DONE.
6. **Regenerate SNAPSHOT.md** — the existing snapshot may be stale if the session crashed mid-task.
   Follow the Resume Snapshot Protocol in phase-flow.md.

### 5b: Phase Loop

Read [references/workflow-rules.md](references/workflow-rules.md) once
and store as `WORKFLOW_RULES` for all dispatches.

Read FEATURE.md frontmatter → extract `current_phase`, `phase_status`, `interaction_mode`, `analysis_only`.

```
while current_phase not in [DONE, ANALYSIS_COMPLETE]:
  1. Load phase context per the Context Payloads table in phase-flow.md
  2. Dispatch the phase orchestrator per Step 5c (or the milestone orchestrator per 5d for EXECUTE)
  3. Read updated state per the Return Contract table in phase-flow.md
  4. If interactive: present a phase summary and AskUserQuestion at every transition.
     Do NOT proceed until explicit approval. Apply user feedback (adjust, refine further, re-dispatch).
  5. Apply phase transitions:
     - REFINE approved        → RESEARCH
     - RESEARCH approved      → PLAN_DRAFT (or DONE if analysis_only)
     - PLAN_DRAFT approved    → PLAN_REVIEW
     - PLAN_REVIEW approved   → BUNDLE_GENERATION (5e, if tasks/ absent) → EXECUTE
     - PLAN_REVIEW blocked    → PLAN_DRAFT (max 3 loops)
     - EXECUTE all done       → VALIDATE
     - VALIDATE approved      → DONE
     - VALIDATE blocked       → EXECUTE with fix tasks (max 2 loops)
  6. Update FEATURE.md frontmatter: current_phase, last_checkpoint
  7. Regenerate SNAPSHOT.md per the Resume Snapshot Protocol in phase-flow.md
```

**EXECUTE sub-loop:** read PLAN.md and task bundles, build the milestone dependency graph.
Identify ready milestones (all dependencies complete, status != complete).
Group by file overlap per the File Impact Map — no overlap → dispatch in parallel
(multiple Task calls in one message); shared files → sequential.
Initialize `events.jsonl` on first EXECUTE entry (append `SESSION_START`).
After all milestones complete, advance to VALIDATE.

### 5c: Dispatch Templates

All phase, milestone, and bundle-generation dispatches use the templates in
[references/dispatch-templates.md](references/dispatch-templates.md).

| Phase path | Template |
|-|-|
| REFINE, RESEARCH, PLAN_DRAFT, PLAN_REVIEW, VALIDATE, DONE | Phase Orchestrator |
| EXECUTE (per ready milestone or parallel group) | Milestone Orchestrator |
| PLAN_REVIEW approval → EXECUTE (once) | Bundle Generation (skip if `tasks/` exists) |
| Step 4d brainstorm option | Brainstormer |
| Step 6 status request | Status Mode (read-only) |

**Parallel milestone dispatch:** when multiple ready milestones have no file overlap,
send one message with multiple Task calls.
After all return, read updated state and proceed to the next group.

After BUNDLE_GENERATION, verify the task file count matches the task count in PLAN.md.

## Step 6: Status Mode

If the user asks for status without resuming, dispatch the orchestrator read-only using the
Status Mode template in [references/dispatch-templates.md](references/dispatch-templates.md).
The orchestrator must not modify state or code.

## Error Handling

| Error | Action |
|-|-|
| State file not found | List discovered runs or prompt for new feature |
| Git branch conflict | Report and offer resolution options |
| Phase failure | Mark phase as `blocked` in FEATURE.md, record blocker, offer manual intervention |
| Subagent failure | Log failure, mark phase `blocked`, re-dispatch on next loop iteration |
| Phase loop stuck | Track PLAN_REVIEW→PLAN_DRAFT and VALIDATE→EXECUTE counts; max 3 each before escalating |
| Resume after crash | Read FEATURE.md current_phase, regenerate SNAPSHOT.md, re-enter the loop; task bundles enable task-level resume within EXECUTE |
| Plan deviation during EXECUTE | Follow the Plan Amendment Protocol in phase-flow.md (update PLAN.md task contracts and downstream preconditions) |

Phase-level behaviors, adversarial protocols, EXECUTE batch loops, DONE finalization, Discovery Capture Protocol,
and Plan Amendment Protocol are defined in [references/phase-flow.md](references/phase-flow.md).
State file schemas are in [references/state-file-schema.md](references/state-file-schema.md).
