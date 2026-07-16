---
name: "brainstorm"
description: "Use when the user wants to brainstorm an idea, explore a problem space, think through a project proposal, develop an idea before implementing, or compare disposable prototypes to reveal a preference. Triggers: \"brainstorm\", \"I have an idea\", \"let me think through\", \"explore this idea\", \"what if we\", \"is this worth building\", \"new project idea\", \"problem statement\", \"prototype options\", \"show me variants\"."
---

# Brainstorm

Announce: "I'm using the /brainstorm skill to explore and sharpen this idea."

## Step 1: Initialize

```bash
TODAY=$(date +%Y-%m-%d)
```

```bash
mkdir -p ~/docs/brainstorms
```

## Step 2: Determine Mode

Parse and remove the optional `--prototype` flag, then determine new vs resume.
Without the flag, preserve the default problem-sharpening workflow.

| Signal | Mode |
|-|-|
| `--prototype` plus a new or existing brainstorm | **Prototype** — create disposable variants for one decision, after creating or loading its brainstorm file |
| Path to existing `~/docs/brainstorms/*.md` file | **Resume** — load and continue |
| Short name matching an existing brainstorm file | **Resume** — find and continue |
| Idea description (free text) | **New** — create brainstorm file |
| No arguments | **List** — show existing brainstorms and ask what to do |

### List mode

Use `Glob(pattern="*.md", path="~/docs/brainstorms")` to find existing brainstorm files.

For each file, read the frontmatter to extract `status` and the `# Title`. Display the list as a table (slug, title, status, date_modified) so the user can see what exists, then ask via `an interactive prompt`:

**Pause and ask the user. Wait for their answer before proceeding.**

> **Brainstorm** -- Which brainstorm do you want to work on?
>
> - **<slug-1>** -- <title-1> — <status-1>
> - **<slug-2>** -- <title-2> — <status-2>
> - **Start new** -- Create a new brainstorm — I'll ask for the idea

Cap the options at 3 existing brainstorms plus "Start new". If there are more than 3 brainstorms, prefer the most recently modified. The auto-injected "Other" option lets the user name a different brainstorm by hand.

If the user picks "Start new", ask a follow-up open question for the idea description, then continue with Step 3 (New brainstorm).

## Step 3: Create or Load Brainstorm File

### New brainstorm

Derive a slug from the idea description (kebab-case, max 40 chars).

Create `~/docs/brainstorms/<slug>.md`:

```markdown
---
date_created: <TODAY>
date_modified: <TODAY>
status: draft
tags: []
---

# <Title derived from idea>

## Overview

<Initial idea description — reframed around the problem, not the solution>

## Problem Statement

<To be sharpened through brainstorming>

## Evidence

<Concrete data supporting the problem — to be gathered>

## Stakeholders

<Who is affected — to be identified>

## Parked Solution Ideas

- <Solutions mentioned during brainstorming>

## Challenge Log

### Session: <TODAY>
```

Tell the user the file path.

### Resume

Read the existing brainstorm file.
Pass the full content to the brainstormer agent for continuation.

## Step 4: Run Prototype Mode

Skip this step unless `--prototype` was supplied.

Name the single decision being tested, such as layout, approach, name, or tone.
If the arguments contain multiple decisions, choose the highest-blast-radius decision and park the others in the brainstorm file.
Retrieve any answer available from the repository, references, or brainstorm file before asking the user.
If the decision is still unclear, ask exactly one question, ordered by architecture-changing, behavior-defining, then polish impact.

Create three to five materially different variants in one round.
Do not produce cosmetic variations of the same assumption.
For every variant, include:

- A short label.
- `Belief tested:` followed by the assumption the variant makes.
- The disposable artifact or compact example.
- The main trade-off the user should react to.

For visual decisions, create the directory and write one self-contained artifact containing all variants:

```bash
mkdir -p ~/docs/brainstorms/prototypes/<slug>
```

Write the artifact to `~/docs/brainstorms/prototypes/<slug>/index.html`.
Mark it `DISPOSABLE PROTOTYPE`, use fake data, avoid network or production dependencies, and never copy or wire it into the application.
For approach, naming, or tone decisions, write compact textual variants under a `## Prototype Round: <TODAY>` section in the brainstorm file.

Show the variants together, then collect one reaction at a time.
Ask what the user would keep, reject, or combine and why; do not ask them to design the answer from scratch.
If all variants are rejected for the same reason, restate the shared failed assumption and reframe the decision space before generating another round.
Do not generate more variants from the same beliefs.

Finish the round by appending a `## Prototype Learning: <TODAY>` section to the brainstorm file containing:

- `Learned requirement:` the constraint or preference revealed by the reactions.
- The selected direction, if any.
- Remaining uncertainty and whether it is cheaper and safe to resolve during implementation.
- The disposable artifact path, when one was created.

Stop questioning once the remaining uncertainty is implementation-cheap and safe.
Report the learned requirement and exit without dispatching the default brainstormer.

## Step 5: Dispatch Brainstormer

Dispatch the brainstormer agent to drive the conversation.
The brainstormer is a problem-focused thinking partner that sharpens vague ideas into clear problem statements through iterative diagnostic questions.
It asks one question at a time, pushes back on solution-shaped thinking, and updates the brainstorm file after each exchange.

```
Task(
  subagent = "brainstormer",
  description = "<new|resume> brainstorm: <slug>",
  prompt = "
<brainstorm_file>
<path>~/docs/brainstorms/<slug>.md</path>
<content>
<full file content>
</content>
</brainstorm_file>

<idea>
<the user's idea description, or 'resume' if continuing>
</idea>

<today><TODAY></today>

<task>
<For new>: Start a new brainstorm. The file has been created with the initial idea.
Analyze whether the idea is problem-shaped or solution-shaped, then begin the diagnostic progression.
Ask one question at a time. Update the brainstorm file after each exchange.
<For resume>: Resume an existing brainstorm. Read the file, summarize where things stand,
and continue from where the last session left off.

Before asking, retrieve any answer discoverable from the brainstorm file, repository, or supplied references.
Order unresolved questions by architecture-changing, behavior-defining, then polish impact.
Provide concrete options and a recommendation for consequential choices.
Stop questioning when remaining uncertainty is cheaper and safe to resolve during implementation.
</task>
"
)
```

## Step 6: Report

After the brainstormer agent completes, read the brainstorm file and report:

| Field | Value |
|-|-|
| **File** | `~/docs/brainstorms/<slug>.md` |
| **Status** | `draft` / `developing` / `sharp` / `parked` |
| **Problem sharp?** | Yes/No — apply the Sharp Problem Test: Can you state WHO has the problem, WHAT the problem is, and WHY it matters in one sentence each? If any answer is vague ("users", "it's slow", "it would be nice"), the problem is not sharp yet. |
| **Next steps** | Suggested actions based on status |

Suggested next steps by status:

| Status | Suggestion |
|-|-|
| `draft` | "Run `/brainstorm <slug>` to continue sharpening." |
| `developing` | "Run `/brainstorm <slug>` to continue. Focus on: <open question>." |
| `sharp` | "Problem is well-defined. Ready for `/do` or `/rfc`." |
| `parked` | "Brainstorm is parked. Resume anytime with `/brainstorm <slug>`." |

## Error Handling

| Error | Action |
|-|-|
| `~/docs/brainstorms/` not writable | Report error and exit |
| No arguments and no existing brainstorms | Ask for an idea description via a plain open-ended prompt (no `an interactive prompt` — the answer is free-form) |
| Slug conflicts with existing file | Append a number suffix (e.g., `my-idea-2.md`) |
| Brainstormer agent fails | Save current file state, report error, suggest manual resume |
| Brainstorm file corrupted or unreadable | Re-create the file with the last known content from conversation history. |
| User wants to stop mid-conversation | Update file with current state, set status to `developing` or `parked` |
| Prototype decision is too broad | Select the highest-blast-radius decision, park the rest, and state the narrowed scope. |
| Visual prototype could affect production | Stop, move it to the disposable prototype directory with fake data, and remove all production integration. |
| Variants test the same belief | Discard the redundant variants and regenerate materially different assumptions before asking for reactions. |
