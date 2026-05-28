---
name: "ai-cli"
description: "Use when the user wants to make a CLI AI-friendly, evaluate a CLI's agent readiness, improve CLI design for AI agents, or add machine-readable output, schema introspection, input hardening, or safety rails to a CLI. Also use when the user says \"ai-cli\", \"make this CLI work with AI\", \"agent-friendly CLI\", \"CLI for AI agents\", \"evaluate CLI agent readiness\", \"agent DX\", \"AXI\", \"agent experience interface\", \"token-efficient CLI\", \"TOON format\", or asks about designing CLIs that AI agents can use."
---

# AI-Friendly CLI Design

Announce: "I'm using the ai-cli skill to evaluate and improve CLI design for AI agent usage."

Guide CLI evaluation and improvement for AI agent consumption.
Human DX optimizes for discoverability and forgiveness;
Agent DX optimizes for predictability and defense-in-depth.
This skill aligns with the AXI (Agent eXperience Interface) framework's 10 principles,
organized into Efficiency, Robustness, Discoverability, and Help Access.

AXI benchmarks (985 runs, two domains) show the impact:
hint-rich CLI wrappers achieved 100% vs 86% task success, with 36% fewer turns and 39% fewer tokens.
Per-domain breakdown: browser automation (560 runs, 100%, $0.133/task, 4.6 turns);
GitHub operations (425 runs, 100%, $0.050/task, 3 turns).
Gains are largest on aggregate and multi-step tasks.

## Step 1: Discover the CLI

Parse the user's invocation prompt to identify the target CLI and mode.

| Argument | Mode |
|----------|------|
| CLI name or repo path | **Evaluate**: score the CLI, then recommend improvements |
| `--design <name>` | **Design**: guide building a new AI-first CLI from scratch |
| `--retrofit <area>` | **Retrofit**: jump to implementing a specific improvement area |
| No argument | Ask: which CLI to evaluate or design? |

### Evaluate / Retrofit: gather CLI context

1. Run `<cli> --help` to understand top-level commands
2. Find source code — look for command definitions, flag parsing, output formatting
3. Identify the underlying API or service the CLI wraps (if any)
4. Check for existing machine-readable flags (`--output json`, `--format`, `--fields`)
5. Check for agent context files (`CONTEXT.md`, `AGENTS.md`, skill files)

### Design: gather requirements

1. What API or service will the CLI wrap?
2. Who are the primary consumers — humans, agents, or both?
3. What language and framework? (e.g., Go + cobra, Python + click, Node + commander)

## Step 2: Score Against Agent DX Axes

> Skip this step in Design mode — go directly to Step 3.

Evaluate the CLI on 8 axes, scoring each 0-3.
Load the full scoring criteria from [references/scoring-rubric.md](references/scoring-rubric.md).

| Axis | Key question |
|------|-------------|
| Machine-readable output | Can agents parse output without heuristics? |
| Raw payload input | Can agents send full API payloads without flag translation? |
| Schema introspection | Can agents discover accepted inputs at runtime? |
| Context window discipline | Does the CLI help agents control response size? |
| Input hardening | Does the CLI defend against agent hallucination patterns? |
| Safety rails | Can agents validate before acting? |
| Agent knowledge packaging | Does the CLI ship agent-consumable knowledge files? |
| Efficiency & composition | Does the CLI minimize tokens and support shell pipelines? |

For each axis:

1. Run relevant CLI commands to test behavior
2. Read source code for the implementation
3. Assign a score (0-3) with evidence

### The One Question Diagnostic

After scoring, run this test on 3-5 representative commands.
For each command's output, ask:
**"What is the human caller implicitly expected to figure out here?"**

| If the answer is... | The fix is... |
|----------------------|---------------|
| "what format is this?" | Structured output default when piped |
| "how many total?" | `total_count` field |
| "what do I do next?" | Next-step hints |
| "which flag did I get wrong?" | Batch validation — all errors at once |
| "can I undo this?" | `undo_command` in mutation receipt |
| "should I retry?" | `retryable` flag on errors |
| "is it safe to proceed?" | `--yes` flag + non-interactive mode |
| "what state is the system in?" | Ambient context (session hooks showing state) |
| "can I pipe this somewhere?" | Shell-composable output (stdout = data, one record per line) |

If every answer is "nothing," the CLI is already agent-friendly.
Use gaps found here to prioritize recommendations in Step 3.

Present the scorecard:

```markdown
## Agent DX Scorecard: <CLI name>

| Axis | Score | Evidence |
|------|-------|----------|
| Machine-readable output | N/3 | <finding> |
| Raw payload input | N/3 | <finding> |
| Schema introspection | N/3 | <finding> |
| Context window discipline | N/3 | <finding> |
| Input hardening | N/3 | <finding> |
| Safety rails | N/3 | <finding> |
| Agent knowledge packaging | N/3 | <finding> |
| Efficiency & composition | N/3 | <finding> |
| **Total** | **N/24** | |

| Range | Rating |
|-------|--------|
| 0-6 | Human-only — agents will struggle |
| 7-12 | Agent-tolerant — works but wastes tokens and makes avoidable errors |
| 13-18 | Agent-ready — solid support, a few gaps |
| 19-24 | Agent-first — purpose-built for agents |
```

### Reference Implementations

Two AXI-compliant CLIs demonstrate these patterns in production:

- **gh-axi** (GitHub): combined list+filter, pre-computed totals, help[] blocks, TOON output.
  425 runs, 100% success, $0.050/task, 3 turns.
- **chrome-devtools-axi** (browser): combined navigate+snapshot, ambient context via session hooks,
  shell pipes for multi-step extraction. 560 runs, 100% success, $0.133/task, 4.6 turns.

For the full AXI principles mapping, see [references/axi-principles.md](references/axi-principles.md).

## Step 3: Recommend Improvements

Based on scores (or requirements in Design mode), generate a prioritized improvement plan.
Follow this implementation priority order — each item builds on the previous:

| Priority | Improvement | Prerequisite |
|----------|------------|--------------|
| 1 | Machine-readable output (`--output json`, structured errors) | None |
| 2 | Input validation, batch validation, reject/normalize | None |
| 3 | Exit code design and recovery paths in errors | JSON output |
| 4 | Schema introspection (`schema` or `--describe`) | JSON output |
| 5 | Field masks (`--fields`), pagination, pre-computed totals | JSON output |
| 6 | Token-efficient output (TOON option, minimal defaults) | JSON output |
| 7 | Non-interactive mode (`--yes`, headless auth, secret redaction) | None |
| 8 | Dry-run for mutations (`--dry-run`) | None |
| 9 | Follow-up reduction (help[] blocks, undo commands, truncation) | JSON output |
| 10 | Shell composition (pipe-safe output, combined operations) | JSON output |
| 11 | Agent context files (`CONTEXT.md`, skill files, ambient context) | None |
| 12 | MCP surface (JSON-RPC over stdio) | JSON output, schema |

### Quick Wins (highest ROI, start here)

1. JSON by default when output is piped or captured
2. No prompts in non-interactive mode (+ `--yes` flag)
3. Structured errors with recovery suggestions
4. Ship a focused `SKILL.md` with non-inferable invariants only
5. `--dry-run` on all mutating commands
6. Minimal default fields on list commands (3-4 fields, not 10+)

For each recommendation:

- What to implement (one sentence)
- Why it matters for agents
- Effort estimate: small (hours), medium (days), large (week+)
- Dependencies on other improvements

Present as an ordered checklist.
Ask the user which improvement to tackle first.

## Step 4: Implement

When the user selects an improvement,
load the relevant implementation patterns from [references/implementation-patterns.md](references/implementation-patterns.md)
and guide the implementation.
For a quick pass/fail assessment, consult the [references/agent-dx-checklist.md](references/agent-dx-checklist.md).

### Implementation workflow

1. Read the implementation pattern for the selected improvement
2. Find the relevant source files in the CLI codebase
3. Propose changes adapted to the CLI's language and framework
4. Implement changes with the user's approval
5. Verify: run the CLI to confirm the improvement works
6. Re-score the affected axis to show progress

### After implementing

Update the scorecard.
If the user wants to continue, return to Step 3 for the next improvement.

## Error Handling

| Error | Action |
|-------|--------|
| CLI not found or not installed | Ask for the path to the source code or binary |
| CLI has no `--help` | Fall back to source code analysis |
| Source code not accessible | Evaluate based on CLI behavior only (black-box assessment) |
| Language/framework not recognized | Provide language-agnostic patterns from the reference file |
| User wants to evaluate a CLI they don't own | Provide scorecard and recommendations as a report only |
| No argument provided | Ask: which CLI to evaluate, design, or retrofit? |
| Agent uses ToolSearch to find CLI tools | Warn: ToolSearch reduces success by ~15 points. Ship explicit SKILL.md with tool names instead. |
