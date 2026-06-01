---
name: "openspec-propose"
description: "Use when the user wants to create an OpenSpec change proposal, generate OpenSpec artifacts, start an OPSX/spec-driven change, or turn a feature idea into proposal, design, specs, and tasks. Triggers include openspec propose, opsx propose, create openspec change, new OpenSpec proposal, and spec-driven proposal."
---

# OpenSpec Propose

Announce: "I'm using the openspec-propose skill to create an OpenSpec change proposal."

Create an OpenSpec change and generate every artifact required before implementation.

## Step 1: Resolve the Change

Parse `$ARGUMENTS` for a kebab-case change name or a feature description.

If no clear input was provided, ask the user what change they want to build.
Derive a kebab-case name from the answer.
Do not proceed until the requested change is understandable.

If `openspec/changes/<name>/` already exists, inspect it before writing anything.
Continue that change only when the user's intent clearly matches it; otherwise ask for a different name.

## Step 2: Create the Change

Run:

```bash
openspec new change "<name>"
```

Then inspect the workflow graph:

```bash
openspec status --change "<name>" --json
```

Use the JSON fields instead of assuming file names:

- `schemaName` identifies the active workflow.
- `applyRequires` lists the artifacts needed before implementation.
- `artifacts` lists each artifact, status, dependencies, and output path.

## Step 3: Generate Artifacts

Use `TodoWrite` to track artifacts from the current graph.

Loop until every artifact in `applyRequires` is complete:

1. Pick the next artifact whose dependencies are satisfied.
2. Run `openspec instructions <artifact-id> --change "<name>" --json`.
3. Read completed dependency files listed by the instruction output.
4. Write the artifact to the exact `outputPath` from the instruction output.
5. Use the returned template and instruction as the artifact contract.
6. Apply `context` and `rules` as constraints for writing, but do not copy those wrapper fields into the artifact.
7. Re-run `openspec status --change "<name>" --json` and continue.

If an artifact needs product or technical context that cannot be inferred from the repo or conversation, ask the user before writing it.

## Step 4: Verify Readiness

Run:

```bash
openspec status --change "<name>"
```

Report:

- Change name and location.
- Schema name.
- Artifacts created.
- Whether the change is ready for `openspec-apply-change`.

## Error Handling

| Failure | Resolution |
|-|-|
| `openspec` is missing | Tell the user to run this repo's `./init.sh`, or install `@fission-ai/openspec` with npm. |
| Existing change name conflicts | Inspect the existing change and ask whether to continue it or choose a new name. |
| Artifact instructions are blocked | Report missing dependencies from `openspec status --json` and create those first. |
| Required context is unclear | Ask one focused question, then continue artifact generation. |
| Validation fails | Show the failing artifact and fix the artifact before reporting readiness. |
