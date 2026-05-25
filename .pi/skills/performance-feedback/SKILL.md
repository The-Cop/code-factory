---
name: "performance-feedback"
description: "Use when the user wants to write performance feedback, a performance review, or review cycle input for a specific person. Also use when gathering evidence about someone's work for a review, or when preparing talking points for a calibration discussion. Triggers: \"write feedback for Sarah\", \"performance review for Nick\", \"perf review for Alex\", \"review cycle input for Jamie\", \"gather evidence for Sam's review\", \"prepare feedback for Michelle\", \"calibration notes for Alvaro\", \"write review for\", \"perf feedback\". Does NOT handle: personal brag documents (use `/brag`), 1:1 notes or career plans (use `/notes`), daily work journal (use `/daily`)."
---

# Performance Feedback

Announce: "I'm using the /performance-feedback skill to prepare a performance review."

You help the user write evidence-backed performance feedback for a specific person
by gathering data from multiple sources in their Obsidian vault and external tools,
then synthesizing it into a structured review.

## Vault & Path Structure

**Vault root:** `~/docs/`

Relevant directories:

```
~/docs/
├── People/<Person>/
│   ├── <Person>.md                  # overview, attributes
│   ├── <Person> - Achievements.md   # cumulative log
│   └── <Person> - Career Plan.md    # goals, growth plan
├── 1-1s/<Person>/
│   └── YYYY-MM-DD.md               # 1:1 session notes
├── Meetings/
│   └── YYYY-MM-DD-<slug>.md        # meeting notes
└── Daily/
    └── YYYY/MM/YYYY-MM-DD.md       # daily journal entries
```

## Step 1: Get Today's Date and Parse Arguments

```bash
TODAY=$(date +%Y-%m-%d)
YEAR=$(date +%Y)
```

Parse `$ARGUMENTS` for:

| Component | How to resolve |
|-----------|---------------|
| **Person name** | Required. First positional argument. |
| **Review period** | Optional `--period` flag. See table below. Defaults to last completed quarter. |

| Period argument | Date range |
|----------------|------------|
| `Q1` | Jan 1 – Mar 31 of current year |
| `Q2` | Apr 1 – Jun 30 of current year |
| `Q3` | Jul 1 – Sep 30 of current year |
| `Q4` | Oct 1 – Dec 31 of current year |
| `H1` | Jan 1 – Jun 30 of current year |
| `H2` | Jul 1 – Dec 31 of current year |
| `YYYY-MM-DD..YYYY-MM-DD` | Explicit start and end dates |
| (none) | Last completed quarter based on today's date |

Store `PERIOD_START` and `PERIOD_END` for all queries.

## Step 2: Resolve Person Name

Use the same 4-level name resolution as `/notes` and `/daily`:

1. Use `Glob(pattern="*/", path="~/docs/People")` to get the list of known people.
2. Match the input against existing directories:

| Priority | Rule | Example |
|----------|------|---------|
| 1 | **Exact match** — input matches a directory name exactly | "Nick Nakas" → `Nick Nakas/` |
| 2 | **First-name match** — input matches the first name of exactly one person | "Nick" → `Nick Nakas/` |
| 3 | **Accent-insensitive match** — strip accents before comparing | "Alvaro" → `Álvaro Mongil/` |
| 4 | **Substring match** — input is a clear substring of exactly one name | "Mongil" → `Álvaro Mongil/` |

- **Multiple matches**: use AskUserQuestion to present candidates.
- **No match**: ask for the full name using AskUserQuestion. Do not bootstrap a new People entry — the person must already exist in the vault to have meaningful feedback data.

After resolving, read the person's overview file (`People/<Person>/<Person>.md`)
to get their attributes (role, team, github username) for external queries.

## Step 3: Collect Evidence

Gather data from all available sources within `PERIOD_START` to `PERIOD_END`.
Run independent queries in parallel where possible.
Skip any source that isn't available — warn the user, continue with the rest.

### 3a: 1:1 Notes

```bash
ls ~/docs/1-1s/<Person>/ 2>/dev/null
```

Read each 1:1 note file within the date range.
Extract: recurring themes, growth signals, blockers raised, commitments made, feedback given/received.

### 3b: Person's Achievements File

Read `~/docs/People/<Person>/<Person> - Achievements.md` if it exists.
Filter entries within the review period by date prefix (`- YYYY-MM-DD: ...`).

### 3c: Career Plan

Read `~/docs/People/<Person>/<Person> - Career Plan.md` if it exists.
Note current goals and milestones — compare against achievements to assess progress.

### 3d: Daily Notes Mentions

Search the person's People file for `## Referenced In` backlinks.
Filter backlinks pointing to `Daily/` entries within the date range.
Read each referenced daily note and extract the relevant context about this person.

### 3e: Meeting Notes Mentions

Grep meeting notes for the person's name within the date range:

```bash
ls ~/docs/Meetings/YYYY-MM-DD-*.md 2>/dev/null  # for each month in range
```

Read matching files and extract entries involving the person.

### 3f: Brag Document Mentions

Search brag docs for mentions of the person:

```bash
ls ~/log/YYYY-MM/brag.md 2>/dev/null  # for each month in range
```

Grep for the person's name — these are accomplishments the user already tagged as notable.

### 3g: GitHub PRs

If the person's `github` attribute is known from their People file:

```bash
gh search prs --author={github_username} --created={PERIOD_START}..{PERIOD_END} \
  --json title,url,state,repository,mergedAt,additions,deletions --limit 50
gh search prs --author={github_username} --merged={PERIOD_START}..{PERIOD_END} \
  --json title,url,state,repository,mergedAt,additions,deletions --limit 50
```

Deduplicate by URL. Also search for PR reviews they gave:

```bash
gh search prs --reviewed-by={github_username} --created={PERIOD_START}..{PERIOD_END} \
  --json title,url,repository --limit 30
```

### 3h: Jira Tickets

```
atlassian_searchJiraIssuesUsingJql(
  jql = "assignee = '<jira_display_name_or_email>' AND updated >= 'PERIOD_START' AND updated <= 'PERIOD_END' ORDER BY updated DESC",
  limit = 50
)
```

Note tickets completed (Done/Resolved), in progress, and any blockers.

### 3i: Confluence Pages

```
atlassian_searchConfluenceUsingCql(
  cql = "contributor = '<email>' AND lastmodified >= 'PERIOD_START' AND lastmodified <= 'PERIOD_END' AND type = page",
  limit = 20
)
```

## Step 4: Ask for Context

After automated collection, ask the user for context that can't be discovered:

```
AskUserQuestion(
  header: "Additional context for <Person>'s review",
  question: "I've gathered evidence from your notes, GitHub, Jira, and Confluence.
Before I synthesize, is there anything I should know that isn't in these sources?
For example: informal feedback from others, cross-team impact, leadership moments,
areas for growth, or specific incidents worth highlighting.",
  options: [
    "Yes, I have additional context" -- Let me add more details,
    "No, proceed with what you have" -- Synthesize from collected evidence
  ]
)
```

If the user provides additional context, incorporate it into the synthesis.

## Step 5: Synthesize

Organize the collected evidence into review dimensions.
Each dimension should have **specific examples with dates and links** — not vague statements.

| Dimension | What to look for |
|-----------|-----------------|
| **Impact & Delivery** | Shipped features, resolved tickets, PRs merged, projects completed. Quantity and quality of output. |
| **Technical Quality** | Code review feedback, architecture decisions, bug fix patterns, documentation. PR size and review quality. |
| **Collaboration** | Cross-team work, PR reviews given, pair programming mentions, meeting contributions. |
| **Growth & Development** | Progress against career plan goals, new skills demonstrated, stretch projects taken on. |
| **Communication** | Quality of docs/RFCs authored, meeting facilitation, clarity in 1:1 discussions. |
| **Areas for Growth** | Recurring themes from 1:1s, gaps between career plan and execution, skills to develop. |

**Writing guidelines:**

- Lead with evidence, not opinion. "Merged 12 PRs including the auth refactor (DATA-4521)" not "did great work."
- Use the Situation, Behavior, Impact pattern for specific examples.
- Balance strengths and growth areas. Pure praise is unhelpful.
- Quote directly from 1:1 notes or daily logs where relevant (with dates).
- Group related items into themes rather than listing chronologically.
- If evidence is thin for a dimension, note it explicitly rather than speculating.
- Follow the full prose rules in `references/prose-guardrails.md`:
  - Banned vocabulary (delve, crucial, robust, seamless, leverage, comprehensive, empower, "stands as a testament", "strong communicator" without example, etc.).
  - No em dashes or en dashes. No curly quotes. No mid-sentence styling.
  - No rule-of-three padding, no trailing `-ing` clauses, no motivational transitions, no closing pep talks.
  - Smell tests: landing-page, read-aloud, signature. Run all three on every paragraph.
  - Density rule: five AI-slop words in two paragraphs means rewrite the passage.
  - Signature test matters most here. The reviewee should hear the manager's voice, not an HR template.

## Step 6: Generate Output

Create the feedback document at:
`~/docs/People/<Person>/<Person> - Performance Feedback {PERIOD_LABEL}.md`

Where `PERIOD_LABEL` is e.g., `2026 Q1`, `2026 H1`, or `2026-01..2026-03`.

```markdown
---
date_created: TODAY
date_modified: TODAY
category: performance-feedback
person: <Full Name>
period_start: PERIOD_START
period_end: PERIOD_END
tags: [performance-feedback, period-label-slug, fullname-slug]
---

# Performance Feedback: <Full Name> ({PERIOD_LABEL})

## Summary
2-3 sentence overview of the person's performance during this period.

## Impact & Delivery
- Evidence-backed bullet points with links to PRs, tickets, docs

## Technical Quality
- Evidence-backed bullet points

## Collaboration
- Evidence-backed bullet points

## Growth & Development
- Progress against career plan goals, new skills

## Communication
- Docs authored, meeting contributions, clarity

## Areas for Growth
- Specific, actionable growth areas with examples

## Key Metrics
- PRs: X merged, Y reviewed
- Jira: X tickets completed
- Docs: X Confluence pages created/updated

## Data Sources
- 1:1 notes: N sessions reviewed
- Daily notes: N entries with mentions
- GitHub: N PRs found
- Jira: N tickets found
- Confluence: N pages found
- Brag docs: N mentions found
```

## Step 7: Save and Present

1. Run `mkdir -p ~/docs/People/<Person>/`
2. Write the feedback document
3. Update the person's People overview file — append a backlink under `## Referenced In`:
   ```
   - `People/<Person>/<Person> - Performance Feedback {PERIOD_LABEL}` - Performance review feedback
   ```
4. Present a summary to the user:
   - Strongest evidence areas (which dimensions had the most data)
   - Data gaps (which sources had no results)
   - The file path
5. Ask if they want to refine any section

## Error Handling

| Error | Action |
|-------|--------|
| Person not found in `~/docs/People/` | Ask for full name. Do not create a new entry — insufficient data for feedback. |
| No 1:1 notes found for the period | Warn the user — 1:1s are the richest evidence source. Continue with other sources. |
| Person's GitHub username not in People file | Skip GitHub collection, warn user, suggest updating via `/notes` |
| `gh` CLI not installed or not authenticated | Skip GitHub collection, warn user, continue |
| Atlassian MCP tools not available | Skip Jira/Confluence collection, warn user, continue |
| No evidence found in any source | Report "insufficient data for meaningful feedback" and list which sources were checked. |
| Career plan file doesn't exist | Skip Growth & Development career plan comparison, note the gap |
| Achievements file doesn't exist | Skip, note the gap |
| Review period is in the future | Warn user and adjust to today as end date |
| Feedback file already exists for this period | Read it, then use `AskUserQuestion` with options "Overwrite" / "Append" / "Cancel" so the user picks without typing |
