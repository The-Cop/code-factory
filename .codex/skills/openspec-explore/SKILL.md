---
name: "openspec-explore"
description: "Use when the user wants to explore an idea, investigate a problem, inspect an existing OpenSpec change, or think through requirements before or during spec-driven work. Triggers include openspec explore, opsx explore, explore OpenSpec change, think through OpenSpec, and investigate before proposal."
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
If the user's invocation prompt names a change, inspect its status:

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

## Step 3: Capture Decisions When Asked

If the user asks to capture an explored decision into OpenSpec artifacts, update only the relevant proposal, design, spec, or task artifact.
Treat that as documentation of the exploration, not implementation.

Before writing, state which artifact will change and why.

## Step 4: Summarize Findings

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
