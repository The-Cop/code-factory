---
name: tour
description: >
  Use when user says "code tour", "give me a tour", "walk me through", "show me how X works",
  "explain the codebase", "guided tour", "teach me about", or asks to understand a service's
  architecture or code structure. Supports interactive (step-by-step) and written (full document) modes.
argument-hint: "[topic, service, or code area to tour]"
user-invocable: true
allowed-tools: Bash(git:*), Bash(gh:*), Bash(python3:*), Read, Grep, Glob, Task, Write, AskUserQuestion, mcp__atlassian__searchConfluenceUsingCql, mcp__atlassian__getConfluencePage
---

# Code Tour

Announce: "I'm using the tour skill to give a guided walkthrough of the codebase."

Walk through code to explain architecture, flows, or structure. Two modes: **interactive** (step-by-step with user) or **written** (complete document).

## Arguments

`$ARGUMENTS` - The topic, service, or code area to tour (e.g., "apm-services-api", "authentication flow", "src/handlers")

## Mode Selection

Pick mode based on user intent:

- **Interactive** (default): User said "tour", "walk me through", "show me". Step-by-step with pauses.
- **Written**: User said "write a tour", "document the architecture", "write up how X works", or added `--written`. Produces a complete markdown document.

If unclear, pick via `AskUserQuestion`:

```
AskUserQuestion(
  questions: [{
    header: "Tour mode",
    question: "How would you like the tour delivered?",
    options: [
      {label: "Interactive (Recommended)", description: "Step-by-step, one stop per message"},
      {label: "Written document", description: "Full markdown document I can read offline"}
    ],
    multiSelect: false
  }]
)
```

## Step 1: Discover Code Context

**Tool preferences**: Use Glob to find files and Grep to search content. Never use `find` or Bash for file discovery. For broad exploration across multiple directories, delegate to a subagent via `Task(subagent_type=Explore)`.

1. Use Glob/Grep to locate relevant source files for `$ARGUMENTS`
2. If Atlassian MCP tools are available, query for internal documentation and Confluence pages
3. Search the current repo and common code directories for relevant source files
4. **Pre-read ALL discovered files** using the Read tool before building the tour plan — full contextual awareness prevents backtracking during delivery

## Step 2: Build Tour Plan

Design **5-12 stops** in logical narrative order. Each stop specifies: file path, line number, and topic.

| Stop Type | What to show |
|-----------|-------------|
| **Overview** | High-level context from documentation |
| **Entry point** | `main()` or equivalent starting point |
| **Dependencies** | Initialization and dependency injection |
| **Core logic** | Key handlers, routes, or business logic |
| **Integration points** | Connections to other services |

Adapt stops to the topic — not every tour needs all five types. Order stops to tell a story: follow the code path a request or event takes through the system.

## Step 3: Deliver Tour

### Interactive Mode

Navigate to ONE stop per message. Wait for user confirmation before advancing.

#### How to Present Code

Present code as fenced blocks with file path and line numbers:

```
`path/to/file.go:42-68`
⟶ [code snippet]
```

| Snippet Type | Context to Show |
|-------------|----------------|
| Function/struct/class definitions | Start from the definition line, show full signature + key body (10-30 lines) |
| Code needing surrounding context | Include lines above and below the target (up to 30 lines) |
| Single statement or call | Minimal excerpt with enough context to understand the flow |

Use sub-agents (`Task(subagent_type=Explore)`) only during Step 1-2 setup research, not during interactive delivery — sub-agents break the conversational flow.

#### Pacing Rules

**CRITICAL**: ONE location per message maximum. You MUST wait for user confirmation between stops.

1. After explaining a stop, ALWAYS ask before moving on:
   - "Ready to see [next concept]?"
   - "Any questions before we move on?"
2. NEVER advance multiple stops without user acknowledgment.
3. Allow reading time — keep explanations focused, then pause.

#### Handling User Questions

When the user asks about specific code mid-tour:

1. Answer the question fully using pre-read file context from Step 1
2. If the question requires exploring code not yet read, use the Read tool (not a sub-agent)
3. After answering, offer to continue the tour from where you left off

#### Example Flow

```
[You] "Let me give you a tour of {service}. First, let me find the relevant code..."
[Read files, query docs]

[You] "This service does X. Here's the entry point:"
[Show code snippet from main()]
[Explain what it does]
"Ready to see how dependencies are wired up?"

[Wait for user: "yes"]

[Show next code snippet]
[Explain, then ask for confirmation again]

[User asks "what does this function do?"]
[Read the function, explain using pre-read context]
```

### Written Mode

Produce a complete tour as a single markdown document. No pausing — research everything upfront, then write.

#### Process

1. Complete Steps 1-2 (discover + plan)
2. Use sub-agents (`Task(subagent_type=Explore)`) in parallel to research each stop — sub-agents are appropriate here since there is no interactive flow to interrupt
3. Write the full tour document

#### Output Format

Write the tour to a file (default: `/tmp/tour-{topic}.md`) or print inline if short.

<output-format name="written-tour">
# Code Tour: {Topic}

{1-2 sentence overview of what this component/service does}

---

## Stop 1: {Title}

📍 `path/to/file.go:42-68`

{Explanation of what this code does and why it matters}

    go
    // relevant code excerpt

---

## Stop 2: {Title}

📍 `path/to/file.go:120-145`

{Explanation}

    go
    // relevant code excerpt

---

## Data Flow

    component A → component B → component C
</output-format>

#### Writing Style: Semantic Line Feeds

Format the tour document source with semantic line breaks:
- One sentence per line.
- Break after commas, semicolons, colons, or em dashes separating substantial clauses.
- Target 120 characters per line.
- Never split hyphenated words or break inside a clause.

Rendered output is unchanged — Markdown joins adjacent lines into paragraphs.
Cleaner diffs, per-sentence review, natural editing units.

#### Guidelines

- Each stop covers one logical area (a type, a handler, an integration point)
- Include inline code snippets showing the key lines
- End with a data flow summary showing how pieces connect
- Reference actual file paths and line numbers so the reader can navigate

### PR Comment Mode

When the user asks to post a code tour as a comment on a PR (e.g., "post this tour as a PR comment", "write a code tour comment on PR #123"), generate a single PR comment containing the full tour.

#### Gathering context

1. Fetch the PR metadata and diff:
   ```bash
   gh pr view {PR_NUMBER} --json title,body,files,commits
   gh pr diff {PR_NUMBER}
   ```
2. Read the changed files in full context (not only the diff hunks).

#### Building diff links

GitHub diff links use SHA-256 hashes of file paths as anchors. Compute them with:

```bash
python3 -c "
import hashlib
files = ['path/to/file.go', ...]
for f in files:
    h = hashlib.sha256(f.encode()).hexdigest()
    print(f'{f} -> {h}')
"
```

Link format: `https://github.com/{owner}/{repo}/pull/{number}/files#diff-{sha256_hash}R{line_number}`
- `R{line}` for right side (new code), `L{line}` for left side (old code)
- For line ranges: `R{start}-R{end}`

**IMPORTANT**: Use HTML `<a>` tags with `target="_blank"` so links open in a new tab:
```html
<a href="https://github.com/.../pull/123/files#diff-{hash}R{line}" target="_blank"><code>file.go</code> — description</a>
```

#### Comment structure

Use collapsible `<details>` sections for each "stop" on the tour:

<output-format name="pr-comment-tour">
## Code Tour

A guided walkthrough of the changes in this PR. Each stop covers one logical area — expand to read.

---

<details>
<summary><strong>Stop 1: Title</strong> — brief subtitle</summary>

📍 <a href="https://github.com/.../pull/123/files#diff-{hash}R{line}-R{line}" target="_blank"><code>file.go</code> — description</a>

Explanation with inline code snippets:

    go
    // relevant code excerpt

</details>

<details>
<summary><strong>Stop 2: Title</strong> — brief subtitle</summary>
...
</details>

---

### Data flow summary

    component A → component B → component C
</output-format>

#### Guidelines

- Each stop should cover one logical area of the change (a new type, a caller, an integration point, etc.)
- Include inline code snippets showing the key lines — don't make the reader expand every diff
- Link to specific diff regions so readers can click through to full context
- End with a data flow summary showing how the pieces connect
- Write the comment to a temp file and post with `gh pr comment {number} --body-file /tmp/file.md`

#### When to use this mode

- User explicitly asks to post the tour as a PR comment
- User provides a PR URL and asks for a written tour
- After an interactive tour, user asks to capture it as a PR comment

## Error Handling

| Error | Action |
|-------|--------|
| No topic provided | Ask the user what they want a tour of |
| No relevant files found | Report that no matching code was found, suggest alternative search terms |
| Atlassian MCP not available | Skip Confluence search, proceed with local codebase only |
| `gh` not available (PR comment mode) | Inform user that `gh` CLI is required for posting PR comments. Stop. |
| PR not found (PR comment mode) | Report error. List recent PRs with `gh pr list --limit 5`. |
| File too large to display | Show key sections only, link to full file path for reference |
