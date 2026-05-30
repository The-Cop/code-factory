---
name: "doc"
description: "Use when the user wants to create, update, improve, maintain, or audit Markdown documentation. Triggers: \"create doc\", \"update docs\", \"improve documentation\", \"audit docs\", \"sync to confluence\", \"write runbook\", \"fix broken links\", or references to documentation files (.md)."
---

# Documentation Management

Announce: "I'm using the doc skill to manage Markdown documentation."

## Step 1: Parse Arguments

Parse `$ARGUMENTS` to determine intent and options:

```
/doc <intent> [options]
```

**Supported intents:**

| Intent | Description |
|--------|-------------|
| `create` | Create a new document from template |
| `update` | Apply specific edits to an existing document |
| `improve` | Rewrite for clarity and consistency without changing meaning |
| `maintain` | Fix links, update references, ensure consistent structure |
| `audit` | Find and report issues (broken links, style, completeness) |
| `sync` | Sync ddoc-annotated documents to Confluence |
| `status` | Show sync status of all ddoc-annotated documents |

**Options:**

| Option | Short | Description | Applies To |
|--------|-------|-------------|------------|
| `--path <path>` | `-p` | Target file or directory | All |
| `--format <format>` | `-f` | Document format (runbook, guide, reference, tutorial, adr) | create |
| `--title <title>` | `-t` | Document title | create |
| `--audience <audience>` | `-a` | Target audience (dev, sre, pm, support, all) | create, improve |
| `--tone <tone>` | | Writing tone (concise, neutral, friendly) | create, improve |
| `--depth <depth>` | `-d` | Detail level (overview, standard, deep) | create |
| `--owner <owner>` | | Document owner or team | create |
| `--refs <refs>` | | Related links (issues, PRs, slack threads) | create, update |
| `--dry-run` | `-n` | Preview changes without writing | All except audit |
| `--force` | | Skip confirmation prompts | sync |
| `--verbose` | `-v` | Show detailed output | All |

**Default behavior:**

- If no `--path`, use current directory for audit/maintain/sync, or prompt for create/update/improve
- If no `--format` for create, prompt user to select
- If intent is ambiguous, use ask_question to clarify

## Writing Style: Semantic Line Feeds

When writing or improving Markdown, format source text with semantic line breaks:

| Rule | Detail |
|------|--------|
| One sentence per line | Start each sentence on a new line |
| Break at clause boundaries | After commas, semicolons, colons, or em dashes separating substantial clauses |
| 120-character target | Lines exceeding this suggest a clause that needs breaking |
| No mid-clause breaks | Never split hyphenated words or break inside a clause |

Rendered output is unchanged — Markdown joins adjacent lines into paragraphs.
Apply to all intents that produce or modify Markdown: create, update, and improve.

## Step 2: Dispatch by Intent

### Intent: create

Create a new document from a template.

**Required:** `--path` (or prompt for it)

**Workflow:**

1. **Determine format** - If `--format` not provided:

```
ask_question(
  header: "Doc format",
  question: "What type of document are you creating?",
  options: [
    "runbook" -- Step-by-step operational procedures for incidents or tasks,
    "guide" -- How-to guide explaining a process or workflow,
    "reference" -- API or technical reference documentation,
    "tutorial" -- Learning-oriented walkthrough for beginners,
    "adr" -- Architecture Decision Record for significant decisions
  ]
)
```

2. **Determine location** - If `--path` not provided:

```
ask_question(
  header: "Doc location",
  question: "Where should I create this document?",
  options: [] // free-text response expected
)
```

3. **Load template** - Read the appropriate template from this skill's templates directory.

4. **Gather context** - If `--title` not provided, derive from path or ask. If `--audience` not provided, default to "dev".

5. **Generate document** - Populate the template with:
   - Title and metadata
   - Placeholder sections appropriate to the format
   - Audience-appropriate language
   - ddoc frontmatter if `--confluence-space` and `--confluence-parent` are provided

6. **Write file** - Create the file at the specified path. If `--dry-run`, show content without writing.

7. **Report** - Show the created file path and next steps.

Report the created file path. Suggest `/doc improve` and `/doc sync` as next steps.

---

### Intent: update

Apply specific edits to an existing document.

**Required:** `--path` (file must exist)

**Workflow:**

1. **Read document** - Load the existing document content.

2. **Identify changes** - Parse `$ARGUMENTS` for the requested change. If unclear:

```
ask_question(
  header: "Update type",
  question: "What would you like to update in this document?",
  options: [
    "Add section" -- Add a new section to the document,
    "Update section" -- Modify an existing section,
    "Add reference" -- Add links or references,
    "Fix content" -- Correct specific content
  ]
)
```

3. **Apply changes** - Make the requested edits while preserving:
   - Document structure and frontmatter
   - Existing content not being changed
   - Internal links and references

4. **Validate** - Check that the document still parses correctly as Markdown.

5. **Show diff** - Present a structured diff summary listing added, modified, and removed sections with line counts.

6. **Confirm and write** - If not `--dry-run`, write changes after confirmation.

**Guardrails:**

- Never remove WARNING, CAUTION, or NOTE admonitions without explicit confirmation
- Preserve all existing links unless explicitly asked to remove
- Keep diffs minimal - only change what was requested

---

### Intent: improve

Rewrite for clarity, correctness, and consistency without changing meaning.

**Required:** `--path` (file must exist)

**Workflow:**

1. **Read document** - Load the existing document content.

2. **Analyze issues** - Identify improvements across categories:

| Category | Examples |
|----------|----------|
| Clarity | Passive voice, jargon, complex sentences |
| Consistency | Heading hierarchy, list formatting, code fence languages |
| Completeness | Missing sections for the format type |
| Accuracy | Outdated commands, broken syntax |
| Style | Per the [style guide](references/style-guide.md) |

3. **Apply improvements** - Rewrite sections that need improvement while:
   - Preserving meaning and intent
   - Keeping technical accuracy (never change commands/code without verification)
   - Maintaining existing structure unless structure is broken

4. **Show diff summary** - Present improvements by category:

```markdown
## Improvements to <filename>

### Clarity (5 changes)
- Line 23: "The system will be configured" → "Configure the system"
- Line 45: Simplified nested conditional explanation

### Consistency (3 changes)
- Fixed heading hierarchy (H4 under H2 → H3 under H2)
- Standardized list formatting (mixed bullets → consistent dashes)

### Style (2 changes)
- Added language tag to code fence (line 67)
- Converted URL to descriptive link (line 89)
```

5. **Confirm and write** - If not `--dry-run`, write changes after confirmation.

**Guardrails:**

- Never fabricate commands, APIs, or technical content
- If unsure about accuracy, mark with `<!-- TODO: verify -->`
- Preserve all warnings, cautions, and security notes
- Keep original structure unless explicitly asked to restructure

---

### Intent: maintain

Keep documentation fresh: fix broken links, update references, ensure consistent structure.

**Required:** `--path` (file or directory)

**Workflow:**

1. **Discover documents** - If path is a directory, find all `.md` files.

2. **Check each document:**

| Check | Action |
|-------|--------|
| Broken internal links | Scan for `](./` or `](../` links, verify targets exist |
| Broken external links | Scan for `](http` links, verify with HEAD request |
| Outdated references | Look for version numbers, dates, deprecated terms |
| Structure consistency | Verify required sections exist for the format type |
| Frontmatter validity | Check YAML frontmatter parses correctly |
| Code fence languages | Ensure all code blocks have language tags |

3. **Generate maintenance report:**

```markdown
## Maintenance Report: <path>

### Files Checked: 12

### Issues Found: 7

#### Broken Links (3)
| File | Line | Link | Status |
|------|------|------|--------|
| docs/setup.md | 45 | ./install.md | File not found |
| docs/api.md | 23 | https://old.api.com | 404 Not Found |

#### Missing Sections (2)
| File | Format | Missing |
|------|--------|---------|
| docs/runbook.md | runbook | Prerequisites, Rollback |

#### Style Issues (2)
| File | Line | Issue |
|------|------|-------|
| docs/guide.md | 12 | Code fence without language |
```

4. **Offer fixes** - For each fixable issue, offer to apply the fix.

```
ask_question(
  header: "Apply fixes",
  question: "Found 5 auto-fixable issues. Apply fixes?",
  options: [
    "Fix all" -- Apply all automatic fixes,
    "Review each" -- Show each fix for approval,
    "Skip" -- Generate report only
  ]
)
```

---

### Intent: audit

Find and report documentation issues without making changes.

**Required:** `--path` (file or directory)

**Workflow:**

1. **Discover documents** - If path is a directory, find all `.md` files.

2. **Audit each document** across dimensions:

| Dimension | Checks |
|-----------|--------|
| **Completeness** | Required sections present, no empty sections, adequate detail |
| **Accuracy** | Commands runnable, links valid, versions current |
| **Clarity** | Readability score, jargon density, sentence complexity |
| **Consistency** | Heading hierarchy, formatting patterns, terminology |
| **Maintainability** | Last updated date, owner defined, no stale TODOs |

3. **Score each document** (0-100):

| Score | Rating |
|-------|--------|
| 90-100 | Excellent |
| 70-89 | Good |
| 50-69 | Needs improvement |
| 0-49 | Poor |

4. **Generate audit report:**

```markdown
## Documentation Audit: <path>

### Summary

| Metric | Value |
|--------|-------|
| Documents audited | 15 |
| Average score | 72/100 |
| Critical issues | 3 |
| Warnings | 12 |
| Suggestions | 25 |

### Scores by Document

| Document | Score | Rating | Top Issue |
|----------|-------|--------|-----------|
| docs/setup.md | 85 | Good | Missing prerequisites |
| docs/api.md | 45 | Poor | 5 broken links |

### Critical Issues (fix immediately)

| Severity | Document | Issue | Suggested Fix |
|----------|----------|-------|---------------|
| Critical | api.md | Endpoint /v1/users returns 404 example | Update to current API |

### Warnings (should fix)

| Document | Issue | Suggested Fix |
|----------|-------|---------------|
| setup.md | Command `npm install` may fail on Node < 18 | Add Node version prerequisite |

### Suggestions (nice to have)

| Document | Suggestion |
|----------|------------|
| guide.md | Add troubleshooting section |
```

---

### Intent: sync

Sync ddoc-annotated documents to Confluence.

**Requires:** `ddoc` CLI installed, Confluence credentials configured

**Workflow:**

1. **Verify prerequisites:**
   - Check `ddoc` is installed: `command -v ddoc`
   - Check credentials: `$CONFLUENCE_API_TOKEN`, `$CONFLUENCE_EMAIL` are set

2. **If prerequisites fail:**

```markdown
## ddoc Setup Required

ddoc is not configured. To set up:

1. Install ddoc: `uv tool install ddoc` or `pip install ddoc`
2. Set environment variables:
   ```bash
   export CONFLUENCE_API_TOKEN='your-token'
   export CONFLUENCE_EMAIL='your-email@example.com'
   export CONFLUENCE_URL='https://your-instance.atlassian.net'
   ```
3. Get an API token: https://id.atlassian.com/manage-profile/security/api-tokens
```

3. **Check status first:**

```bash
ddoc status --root <path>
```

4. **Show status and confirm:**

```
ask_question(
  header: "Confirm sync",
  question: "Ready to sync <N> documents to Confluence. Proceed?",
  options: [
    "Sync all" -- Sync all modified documents,
    "Select" -- Open interactive selection (ddoc sync),
    "Dry run" -- Preview without syncing,
    "Cancel" -- Do not sync
  ]
)
```

5. **Execute sync:**

```bash
# If "Sync all" or --force
ddoc sync --force --root <path>

# If "Select"
ddoc sync --root <path>

# If "Dry run"
ddoc sync --dry-run --root <path>
```

6. **Report results:**

```markdown
## Sync Complete

| Document | Status | Confluence URL |
|----------|--------|----------------|
| docs/setup.md | Updated | https://... |
| docs/api.md | Created | https://... |
```

---

### Intent: status

Show sync status of all ddoc-annotated documents.

**Workflow:**

```bash
ddoc status --root <path>
```

Report the status tree as returned by ddoc.

---

## Reference Documents

| Reference | When to load |
|-----------|-------------|
| [style-guide.md](references/style-guide.md) | Creating or improving documents — follow these conventions |
| [examples.md](references/examples.md) | Need usage examples for `/doc` commands |
| [definition-of-done.md](references/definition-of-done.md) | Verifying document completeness |

---

## Templates

Templates are stored in the `templates/` directory of this skill:

| Template | File | Use For |
|----------|------|---------|
| Runbook | `runbook.md` | Operational procedures, incident response |
| Guide | `guide.md` | How-to guides, workflows, processes |
| Reference | `reference.md` | API docs, CLI references, configuration |
| Tutorial | `tutorial.md` | Learning-oriented walkthroughs |
| ADR | `adr.md` | Architecture Decision Records |

## Error Handling

| Error | Action |
|-------|--------|
| Path not found | Report error, suggest similar paths if available |
| ddoc not installed | Show setup instructions |
| Confluence auth failed | Guide user to check credentials and token |
| Invalid Markdown | Report parse errors with line numbers |
| Network error (link check) | Mark link as "unable to verify", continue |

