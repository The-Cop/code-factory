---
name: "brag"
description: "Use when the user wants to update their brag document, log accomplishments, reflect on recent work, or prepare for performance reviews. Triggers: \"brag\", \"update brag doc\", \"log accomplishments\", \"what did I do today\", \"update my doc\", \"brag doc\", \"end of day\", \"weekly update\"."
---

# Brag Document Updater

Announce: "I'm using the /brag skill to update your brag document with recent accomplishments."

## Overview

Maintains a persistent brag document (`~/docs/log/doc.md`) by scanning multiple sources
(Slack, Confluence, GitHub, Jira, git, daily logs, Google Drive)
and asking targeted questions for undiscoverable work.
Tracks mentees, recurring meetings, and ongoing projects in a state file (`~/docs/log/brag-state.md`).

## File Locations

| File | Purpose |
|------|---------|
| `~/docs/log/doc.md` | Persistent brag document — single file, organized by section |
| `~/docs/log/brag-state.md` | State file — mentees, meetings, interview types, last run date |
| `~/.claude/projects/` | Session logs for automated scanning |
| `~/docs/Daily/` | Obsidian daily notes (from `/daily` skill) |
| `~/docs/People/` | Obsidian People directory — name resolution and backlinks |
| `~/google-drive/` | Google Workspace stub files |

## Step 1: Initialize

### 1a: Determine Mode

Parse `$ARGUMENTS`:

| Argument | Mode |
|----------|------|
| (none) | **Auto** — scan since `last_run` in state file |
| `--today` | Scan today only |
| `--week` | Last 7 days |
| `--month` | Current calendar month |
| `--since YYYY-MM-DD` | From that date to today |
| `--comprehensive` | Go as far back as possible — all sources, no date filter. Use for first-time setup or catching up. |
| `--add` | Skip automated collection, go straight to interactive questions |
| `--review` | Read brag doc, summarize, identify gaps |
| `--prep-review` | Generate a summary organized by career dimensions for perf review |

**Natural language detection**: if arguments contain phrases like "go as far back as possible",
"first time", "never updated", "collect everything", or "all sources" — treat as `--comprehensive`.

```bash
TODAY=$(date +%Y-%m-%d)
```

### 1b: Read State

Read `~/docs/log/brag-state.md`.
If missing, run first-time setup (Step 1c).

The state file is **markdown** (Obsidian-compatible) with these sections:

| Section | Purpose |
|---------|---------|
| `## Last Run` | ISO date of last run — determines default date range |
| `## GitHub` | GitHub username and repos to search |
| `## Mentees` | Current and past mentees with name, since date, and context |
| `## Recurring Meetings` | Regular syncs with name, cadence, and role |
| `## Interview Types` | Interview types conducted |
| `## Guilds & Groups` | Community groups and ERGs |

### 1c: First-Time Setup

If no state file exists:

```bash
mkdir -p ~/docs/log
GH_USER=$(gh api user --jq .login 2>/dev/null || echo "unknown")
GH_REPOS=$(gh api "user/repos?sort=pushed&per_page=10&type=owner" --jq '.[].full_name' 2>/dev/null || echo "")
CURRENT_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
```

Create `~/docs/log/brag-state.md` with discovered defaults and present to user for confirmation.
Ask about mentees, guilds, and meetings — these can't be auto-detected.

### 1d: Read Brag Doc

Read `~/docs/log/doc.md` to understand what's already documented.
If missing, create from [template](references/template.md).
This enables deduplication in Step 3.

## Step 2: Automated Collection

Gather accomplishments from multiple sources.
Only collect items within `START_DATE` to `END_DATE` (unless `--comprehensive`).
**Run independent queries in parallel where possible.**

### 2a: Slack Messages

Search Slack using the MCP tool for messages from the user.
The user's Slack user ID is available from the tool description.

Run these searches **in parallel**:

| Search | Purpose |
|--------|---------|
| `from:<@USER_ID> is:thread` | Threaded discussions — consulting, help, technical guidance |
| `to:<@USER_ID> thanks` | Recognition from others |
| `from:<@USER_ID> help` | Help provided to others |
| `from:<@USER_ID> RFC design doc` | Documents shared |
| `from:<@USER_ID> merged shipped deployed` | Work completed |
| `from:<@USER_ID> review PR` | Code reviews |
| `from:<@USER_ID> presentation talk demo` | Talks and demos |
| `from:<@USER_ID> interview` | Interviews conducted |
| `from:<@USER_ID> migrate migration` | Migration work |

For each relevant channel the user is active in (discovered from initial results),
search `from:<@USER_ID> in:#channel-name` sorted by timestamp ascending to get the full history.

**Pagination**: use the `cursor` parameter to paginate through all results.
Process results concisely — extract the brag-worthy signal, not every message.

**Capture proof**: For each brag-worthy Slack message, save the message date, permalink, and a 1-2 sentence quote.
Slack links require authentication and messages can be edited or deleted —
the quote serves as durable proof of the accomplishment.

**Classify Slack signals**:

| Signal | Brag Section |
|--------|-------------|
| Helping someone with debugging/setup | Consulting |
| Sharing docs or guides | Docs & Talks |
| Recognition/thanks from others | Direct Impact or Consulting |
| Cross-team coordination | Consulting |
| Interview mentions | Interviewing |
| Technical guidance in public channels | Engineering Culture |

### 2b: Confluence Pages

Search for pages the user created or contributed to:

```
mcp({
  tool: "atlassian_searchConfluenceUsingCql",
  args: "{\"cloudId\":\"<from getAccessibleAtlassianResources>\",\"cql\":\"contributor = currentUser() AND type = page ORDER BY lastModified DESC\",\"limit\":250}"
})
```

**Results will be large.** Extract only: page ID, title, created_by, last_modified.
Use a script to parse the JSON rather than reading the raw output.

Separate pages into:
- **Created by user** → strong signal (Docs & Talks or Direct Impact)
- **Contributed to** → weaker signal, skip unless title suggests significant contribution

### 2c: GitHub PRs Authored

For each repo in `state.repos`:

```bash
gh pr list --author @me --repo <repo> --state all \
  --search "created:>=<START_DATE>" \
  --json number,title,url,state,createdAt,mergedAt --limit 100
```

### 2d: GitHub PR Reviews Given

```bash
gh api "search/issues?q=reviewed-by:<github_user>+type:pr+created:>=<START_DATE>+org:DataDog&per_page=50" \
  --jq '.items[] | {number: .number, title: .title, url: .html_url, repo: .repository_url}'
```

### 2e: Jira Tickets

```
mcp({
  tool: "atlassian_searchJiraIssuesUsingJql",
  args: "{\"jql\":\"assignee = currentUser() AND updated >= '<START_DATE>' ORDER BY updated DESC\",\"limit\":50}"
})
```

### 2f: Git History (Background Agent)

Launch a background agent to scan git history across working directories:

```
subagent(
  agent = "explorer",
  run_in_background = true,
  task = "Scan git log --author=<user> --since=<START_DATE> across <repo dirs>.
            Summarize: features shipped, tools created, docs added, tests improved.
            Bullet points per repo. Research only — do not edit files."
)
```

### 2g: Session Logs (Background Agent)

Launch a background agent to scan Claude Code session history:

```
subagent(
  agent = "explorer",
  run_in_background = true,
  task = "Scan ~/.claude/projects/ for accomplished work.
            Identify: skills created, services migrated, bugs fixed, tools built.
            Bullet points. Research only — do not edit files."
)
```

### 2h: Daily Log Entries

Scan `~/docs/Daily/` for notes in the date range.
Extract items from Work, Achievements, and Kudos sections.
Skip items too generic to be meaningful.

### 2i: Google Drive Documents

Scan `~/google-drive/` for files created or modified within the date range.
Classify by filename pattern (see [references/questions.md](references/questions.md) for patterns).

## Step 3: Deduplicate, Categorize, and Present

### 3a: Deduplicate

For each collected item, search the existing brag doc for:
- URL matches (exact)
- PR/ticket number matches
- Title keyword overlap (fuzzy — use judgment)

Skip items already present.

### 3b: Categorize

Assign each new item to a brag doc section:

| Signal | Section |
|--------|---------|
| PR authored or merged | Direct Impact |
| Jira ticket resolved | Direct Impact |
| PR review given (cross-team) | Consulting |
| Confluence page created | Docs & Talks |
| Slack help/consulting | Consulting |
| Slack recognition received | Direct Impact or Consulting |
| Presentation or talk | Docs & Talks |
| Interview conducted | Interviewing |
| Google Drive presentation | Docs & Talks |

Items that don't fit go in `## Uncategorized`.

### 3c: Resolve People Names

When collected entries mention people by name,
resolve them to full names using the People directory in the vault.

Use `Glob(pattern="*/", path="~/docs/People")` to get the list of known people.

Match each name against existing directories using this priority order:

| Priority | Rule | Example |
|----------|------|---------|
| 1 | **Exact match** — input matches a directory name exactly | "Nick Nakas" → `Nick Nakas/` |
| 2 | **First-name match** — input matches the first name of exactly one person | "Nick" → `Nick Nakas/` |
| 3 | **Accent-insensitive match** — strip accents before comparing | "Alvaro" → `Álvaro Mongil/` |
| 4 | **Substring match** — input is a clear substring of exactly one name | "Mongil" → `Álvaro Mongil/` |

- **Unique match at any priority**: use the full name exactly as it appears (preserving accents/diacritics).
- **Multiple matches**: use `ask_question` to present candidates and let the user pick.
- **No match**: bootstrap a new People entry.
  Create `~/docs/People/<Full Name>/<Full Name>.md` with minimal frontmatter
  and an Overview section capturing what you know from context.
  Use the same format as existing People files:

```markdown
---
date_created: YYYY-MM-DD
date_modified: YYYY-MM-DD
category: overview
person: Full Name
tags: [overview, fullname-slug, relationship]
---

# Full Name

## Overview
Brief context from the brag entry.
```

For the relationship tag, use your best guess from context:
`collaborator`, `peer`, `mentee`, `external`, etc.
If only a first name is available and you can't infer the full name, ask using `ask_question`.

Use full names wrapped in Obsidian wikilinks in brag doc entries
so they are searchable and linkable in the Obsidian graph.
For example, "Helped Platform team with debugging" becomes
"Helped [[Sarah Chen]] from Platform team with debugging".

### 3d: Format Entries

Every entry requires a **date** and at least one **reference link** when available.
For ephemeral sources (Slack messages, temporary docs),
capture a brief **quote** as proof since the link may not be accessible later.

**Entry format:**

```
* (YYYY-MM-DD) Brief description mentioning [[Person Name]] — why it matters or what impact it had
  [PR #1234](url) | [Confluence: Page Title](url) | [Slack thread](url): "relevant quote"
```

**Examples:**

```markdown
* (2026-03-15) Fix flaky test timeout in auth module — reduced CI flakiness by 40% for the auth team
  [PR #1234](https://github.com/DataDog/dd-go/pull/1234)

* (2026-03-10) Led cross-team design review for new ingestion pipeline — aligned 3 teams on schema format
  [RFC: Ingestion Pipeline v2](https://datadoghq.atlassian.net/wiki/spaces/ENG/pages/123)
  [Slack thread](https://datadoghq.slack.com/archives/C123/p456): "Thanks @rodrigo, this saved us weeks of back-and-forth"

* (2026-02-28) Helped [[Sarah Chen]] from Platform team debug memory leak in trace-agent — root-caused to unbounded cache
  [Slack DM](https://datadoghq.slack.com/archives/D789/p012): "You were right, the LRU eviction was disabled in prod config"
```

**Link types to capture:**

| Source | Link Format |
|--------|------------|
| GitHub PR | `[PR #N](url)` |
| GitHub Issue | `[Issue #N](url)` |
| Confluence | `[Confluence: Title](url)` |
| Jira | `[PROJ-N](url)` |
| Slack thread | `[Slack thread](url): "key quote"` |
| Slack DM | `[Slack DM](url): "key quote"` |
| Google Doc | `[GDoc: Title](url)` |
| Google Slides | `[GSlides: Title](url)` |
| Presentation | `[Talk: Title](event/url)` |

**Ephemeral source rule**: Slack messages and temporary shared docs may become inaccessible.
Always capture a brief quote (1-2 sentences) that proves the accomplishment.
This applies to: Slack messages, Slack threads, DMs, and any link that requires auth to access.

### 3e: Present and Confirm

Show proposed additions grouped by section.
Use `ask_question` with `multiSelect: true` to let the user pick which to include.
Group entries into batches of ~4 options to avoid overwhelming the user.

After confirmation, use `Edit` to append entries under the correct section headers in `~/docs/log/doc.md`.
**Never** reorganize or reformat existing entries. Only append.

## Step 4: Interactive Questions

Ask about work that can't be discovered automatically.
Load the question bank from [references/questions.md](references/questions.md).

### Question Flow

1. Read state file for context (mentees, guilds, meetings, interview types).
2. Skip categories already well-covered by automated collection.
3. Present questions one at a time using `ask_question`.
4. **Allow free-text input early** — don't force multiple rounds of "tell me more".
   If the user selects "Yes", the next question should accept free-text directly.
5. For "skip"/"none" answers, move to the next question.
6. Update state file if persistent data changed (new mentee, new guild, etc.).
7. **Resolve people names** mentioned in answers using the same process as Step 3c.
   Use `[[Full Name]]` wikilinks when writing entries from interactive input.

**Data capture for manual entries**: When the user describes an accomplishment, always ask for:
- **Date**: When did this happen? (exact date or approximate week/month)
- **Links**: Any supporting references? (PR, Confluence page, Google Doc, Slack thread, Jira ticket)
- **Quotes**: For Slack-sourced items, ask the user to paste the relevant message text as proof.

If the user doesn't have an exact date, use the closest approximation: `(~2026-03-W2)` for "second week of March" or `(2026-03)` for "sometime in March".

### Mentee Check

For each current mentee in state:

```
ask_question(
  header: "Mentorship",
  question: "Any updates on <name> (<context>)?",
  options: [
    "Yes" -- Describe in Other,
    "No updates" -- Skip,
    "Ended" -- Mark as completed
  ]
)
```

### Recurring Meeting Check

For each meeting in state:

```
ask_question(
  header: "Meetings",
  question: "Anything notable from <name> (<cadence>)?",
  options: [
    "Yes" -- Describe in Other,
    "Nothing notable" -- Skip,
    "No longer attending" -- Remove
  ]
)
```

### Remaining Questions

Ask from [references/questions.md](references/questions.md): bar-raising, consulting,
notable 1:1s, interviews, new mentees, learning, guilds, customer engagement, goals.
End with an open-ended "anything else?" question.

## Step 5: Finalize

### 5a: Update State and People Backlinks

Update `~/docs/log/brag-state.md`:
- Set `last_run` to today's date
- Persist any mentee, guild, meeting, or interview type changes
- Keep markdown format (Obsidian-compatible)

Update each mentioned person's People file by appending a backlink under their `## Referenced In` section:

```
- `log/doc` - Brief context of the brag mention (YYYY-MM-DD)
```

If `## Referenced In` doesn't exist, add it.
If there's already a backlink for the brag doc, update it rather than duplicating.

### 5b: Summary

```
## Brag Update Summary

| Section | New Items |
|---------|-----------|
| Direct Impact | N |
| Mentorship | N |
| ... | ... |

**Document**: ~/docs/log/doc.md
**Period scanned**: START_DATE to END_DATE
**Next run**: Will auto-collect from END_DATE onward
```

## Review Mode (`--review`)

1. Read `~/docs/log/doc.md` in full.
2. Identify gaps — sections with no entries or stale entries (>3 months old).
3. Highlight strengths.
4. Suggest areas to focus on based on career path dimensions.

## Prep Review Mode (`--prep-review`)

1. Read `~/docs/log/doc.md` in full.
2. Organize entries by career path dimensions (not brag doc sections).
3. For each dimension, summarize the strongest evidence.
4. Flag dimensions with weak evidence.
5. Generate a draft summary suitable for a promotion packet or performance review.

**Prose rules for the draft summary:**

- Banned vocabulary: delve, crucial, pivotal, robust, seamless, leverage, tapestry, multifaceted, nuanced, comprehensive, streamline, empower, best-in-class, cutting-edge, "stands as a testament". Replace with the specific metric, tool, or outcome.
- No em dashes (`—` or `---`) or en dashes (`–`). No curly quotes. No mid-sentence `**bold**` or `*italic*`.
- Lead with evidence. "Shipped DATA-4521 by 2026-03-15, cutting P99 from 1.2s to 200ms" not "delivered impressive results".
- No rule-of-three padding. No trailing `-ing` clauses. No motivational transitions. No closing pep talks.
- Smell tests: landing-page, read-aloud, signature. If a sentence could appear on a vendor page, rewrite.
- Signature test matters most. Would you defend every word in a promotion committee meeting?

## Error Handling

| Error | Action |
|-------|--------|
| `gh` CLI not installed or not authenticated | Skip GitHub collection, warn user, continue |
| Slack MCP tools not available | Skip Slack collection, warn user, continue |
| Jira/Confluence MCP tools not available | Skip those sources, warn user, continue |
| Confluence results too large | Parse with script; extract titles and metadata only |
| Brag doc not found | Create from [template](references/template.md) |
| State file corrupted | Back up to `.bak`, recreate from defaults |
| Section not found in doc | Append a new section at the end |
| No new items found | Report and proceed to interactive questions |
| `~/google-drive/` missing | Skip, warn user, continue |
| `~/docs/log` not writable | Report error and exit |
| `~/docs/People/` directory doesn't exist | Create it with `mkdir -p ~/docs/People` when first person is mentioned |
| Background agent timeout | Use partial results from the agent, note incomplete scan |
