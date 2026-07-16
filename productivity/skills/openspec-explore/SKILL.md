---
name: openspec-explore
description: Use when the user wants to explore an idea, investigate a problem, inspect an existing OpenSpec change, or think through requirements before or during spec-driven work. Triggers include openspec explore, opsx explore, explore OpenSpec change, think through OpenSpec, and investigate before proposal.
argument-hint: "[idea, problem, or change name]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(openspec:list*), Bash(openspec:show*), Bash(openspec:status*), Bash(git log:*), Bash(git show:*), Bash(git blame:*), WebFetch, WebSearch, AskUserQuestion
---

# OpenSpec Explore

Announce: "I'm using the openspec-explore skill to explore OpenSpec context without implementing."

Explore ideas and existing OpenSpec artifacts without changing code.

## Step 1: Establish Context

Run when available:

```bash
openspec list --json
```

Use the result to identify active changes and specs.
If `$ARGUMENTS` names a change, inspect its status:

```bash
openspec status --change "<name>" --json
```

Read relevant artifacts under `openspec/changes/<name>/` or `openspec/specs/`.

## Step 2: Explore Without Implementing

Use read-only investigation only.
You may search the repo, read files, compare artifacts, and ask clarifying questions.
Do not edit code, mark tasks complete, archive changes, or run mutating OpenSpec commands.

When the user asks for implementation, explain that implementation should use `openspec-apply-change`.
When the user asks to create a new change, use `openspec-propose`.

Run a blindspot pass when the request crosses an unfamiliar area or when missing context could change scope, architecture, behavior, or review strategy.
Ground each finding in repository, OpenSpec, domain, or reference evidence.
Report only consequential findings under this structure:

1. **Landmines**: likely failure modes and their evidence.
2. **Hidden constraints**: conventions, history, or decisions already embedded in the repository or domain.
3. **Quality examples**: examples that calibrate what good looks like.
4. **High-impact questions**: unresolved questions in architecture, behavior, then polish order, with evidence-backed provisional answers when possible.
5. **Revised request**: a concise request or decision summary incorporating the findings.

Retrieve answers available from code, documentation, history, OpenSpec artifacts, or supplied references instead of asking the user.
Ask one question at a time only when the answer materially changes the direction.
Stop asking when the remaining uncertainty is cheaper and safe to resolve during implementation.
If the evidence shows the area is straightforward, state `No significant blindspots found` and do not pad the result with trivia.

## Step 3: Analyze References by Semantics

When the user supplies code, a repository, documentation, or another implementation as a reference, treat it as a behavioral specification rather than source to transliterate.

Before recommending target changes, report:

- Behaviors and guarantees the reference provides.
- Decisions that appear deliberate and the evidence for that interpretation.
- Incidental details tied to the reference language, framework, or repository.
- Native equivalents under the target repository's conventions.
- Translation gaps where the target environment cannot preserve the same semantics directly.
- The reference license and whether implementation text may be reused.

Use target-repository conventions to determine implementation shape.
When the license is missing or unclear, restrict the work to behavioral analysis, label the uncertainty, and do not copy implementation text.
When the reference is unavailable, separate verified facts from assumptions and ask for an accessible source only if its semantics are decision-critical.

## Step 4: Capture Decisions When Asked

If the user asks to capture an explored decision into OpenSpec artifacts, update only the relevant proposal, design, spec, or task artifact.
Treat that as documentation of the exploration, not implementation.

Before writing, state which artifact will change and why.

## Step 5: Summarize Findings

Summarize:

- Current OpenSpec state.
- Relevant existing artifacts or specs.
- Options and trade-offs discussed.
- Open questions.
- Recommended next skill, if the user is ready to proceed.

## Error Handling

| Failure | Resolution |
|-|-|
| `openspec` is missing | Continue with repo file inspection and tell the user to run `./init.sh` to install the CLI. |
| No OpenSpec directory exists | Explore the idea normally and suggest `openspec-propose` when ready. |
| Multiple changes match | Ask which change the user wants to inspect. |
| User requests implementation | Stop exploration and route to `openspec-apply-change`. |
| Artifact write is requested but unclear | Ask what decision should be captured and where. |
| Reference source is unavailable | Report what could not be verified, continue only with independently supported semantics, and request an accessible source if the missing evidence changes the decision. |
| Reference license is unclear | Limit the result to behavioral analysis and do not copy source or instruction text. |
| Evidence is insufficient for a blindspot claim | Label it as an open question or omit it; never promote speculation to a landmine or hidden constraint. |
