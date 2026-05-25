---
name: "daily"
description: "Use when the user narrates what happened during their workday — even if they never say \"daily note\" or \"log\". The key signal is that they are reporting past or current work activity. Also use when the user wants a weekly summary of their personal work. Triggers: \"today I had 3 one-on-ones and merged DATA-1234\", \"eod update: reviewed PRs, booked travel, team seems burnt out\", \"standup: blocked on infra, made progress on benchmarks\", \"kudos to Sarah for jumping in on that production issue\", \"spent the day in meetings\", \"read a great blog post about real-time sync\", \"daily log\", \"daily note\", \"log my day\", \"end of day update\", \"weekly summary\", \"summarize my week\", \"what did I do this week\", \"week in review\", \"last week\", \"prepare my weekly update\". Does NOT handle: structured brag documents or performance review prep (use `/brag`), person-specific accomplishment tracking, feedback about a person's performance, work planning or task breakdowns, team-level reporting."
---

# Daily Log

Announce: "I'm using the /daily skill to update your daily work journal."

You manage a running daily work journal in the user's Obsidian vault.
The purpose is to build a reliable, detailed record of each workday
so the user can look back weeks or months later and reconstruct what they did,
what they achieved, and what mattered —
well enough to write a weekly summary, prepare for a performance review, or remember what happened.

## Vault & Path Structure

**Vault root:** `~/docs/`

**Daily notes live in:** `~/docs/Daily/YYYY/MM/YYYY-MM-DD.md`

Example: `~/docs/Daily/2026/03/2026-03-07.md`

## Step 1: Get Today's Date

**Always run `date +%Y-%m-%d` first.** Store the result as `TODAY`. Never hardcode dates.

If the user says "yesterday" or "last Friday" or refers to a specific date,
compute the correct date using `date -v-1d +%Y-%m-%d` or similar.
The target date determines the file path.

## Step 2: Understand the Update

Read what the user is telling you. Their input might be:
- A single item ("merged JIRA-1234 today")
- A brain dump ("had 3 one-on-ones, worked on the migration, also read that blog post about WASM runtimes")
- A request to log something specific ("add kudos for Alex")
- Vague or incomplete ("did some stuff with the API")

**If the update is vague or missing key context, ask for clarification using AskUserQuestion.**
The bar is: could the user read this entry 3 months from now and understand what happened?
If not, ask. For example:
- "merged a ticket" — which ticket? what was it about?
- "had meetings" — with whom? any decisions or takeaways?
- "worked on the project" — which project? what specifically did you do?

You don't need to interrogate — a sentence or two of context per item is enough.
But push back on entries that would be meaningless in retrospect.

## Step 3: Resolve People Names

When the user mentions someone by first name, nickname, or partial name,
resolve it to their full name using the People directory in the vault.
Use `Glob(pattern="*/", path="~/docs/People")` to get the list of known people.

Match the input against existing directories using this priority order:

| Priority | Rule | Example |
|----------|------|---------|
| 1 | **Exact match** — input matches a directory name exactly | "Nick Nakas" → `Nick Nakas/` |
| 2 | **First-name match** — input matches the first name of exactly one person | "Nick" → `Nick Nakas/` |
| 3 | **Accent-insensitive match** — strip accents before comparing | "Alvaro" → `Álvaro Mongil/`, "Felicite" → `Félicité Lordon/` |
| 4 | **Substring match** — input is a clear substring of exactly one name | "Mongil" → `Álvaro Mongil/` |

- **Unique match at any priority**: use the full name exactly as it appears
  (preserving accents/diacritics) and add their name tag to frontmatter.
- **Multiple matches**: use AskUserQuestion to present candidates and let the user pick.
- **No match**: Bootstrap a new People entry.
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
Brief context from today's interaction.
```

For the relationship tag, use your best guess from context:
`collaborator`, `peer`, `external`, `speaker`, etc.
If the user only gave a first name and you can't infer the full name, ask using AskUserQuestion.

Use full names wrapped in Obsidian wikilinks in the note entries so they are searchable
and linkable in the Obsidian graph.
For example, "discussed with Hugo" becomes "discussed with [[Hugo Arraes Henley]]".

After writing the daily note, update each mentioned person's People file
by appending a backlink under their `## Referenced In` section:

```
- `Daily/YYYY/MM/YYYY-MM-DD` - Brief context of the mention
```

If `## Referenced In` doesn't exist, add it.
If there's already a backlink for today's date, update it rather than duplicating.

## Step 4: Classify Each Item

Map each piece of information to one of these sections:

| Section | What goes here | Examples |
|---|---|---|
| **Work** | Tasks, tickets, projects, code changes, research, reviews | "Merged DATA-4521 (fixed retry logic in ingestion pipeline)", "Researched WASM runtime options for 2h" |
| **Meetings** | 1:1 count, notable meetings, key decisions, takeaways | "4x 1:1s", "Architecture review — decided to go with option B" |
| **Achievements** | Milestones, launches, sign-offs worth celebrating beyond routine. Don't duplicate Work items — only outcomes that stand on their own. | "Shipped v2.3 to production", "Got sign-off on the RFC" |
| **Team Pulse** | Team morale observations, happiness/unhappiness signals | "Team seems energized after the offsite", "Alex frustrated with CI flakiness" |
| **Travel** | Plans made, trips taken, onsite summaries | "Booked flights for NYC onsite Mar 10-12", "Paris onsite recap: ..." |
| **Learning** | Articles, workshops, talks, interesting things seen/read | "Read: 'Scaling WASM beyond the browser' — key insight was..." |
| **Kudos** | Collaboration callouts, great chats, shoutouts | "Great pairing session with Sam on the caching layer — learned a lot about Redis eviction" |
| **Notes** | Anything that doesn't fit above but is worth recording | Topics top of mind, open questions, things to follow up on |

If an item could fit multiple sections, put it where it's most useful for future lookup.
A meeting where you achieved something goes in Achievements.
A 1:1 where you got a team morale signal goes in both Meetings (the count) and Team Pulse (the signal).

## Step 5: Read or Create the Daily Note

1. Compute the file path: `~/docs/Daily/{YYYY}/{MM}/{YYYY-MM-DD}.md`
2. Run `mkdir -p` on the parent directory.
3. Try to Read the file.

**If the file does not exist**, create it with only frontmatter and heading — no section headings yet:

```markdown
---
date: YYYY-MM-DD
weekday: Monday
tags: [daily]
---

# YYYY-MM-DD (Monday)
```

Use the actual date and weekday name.
Sections are added on demand in Step 6 — only when there's actual content for them.

**If the file exists**, read it and proceed to Step 6.

## Step 6: Merge Updates Into the Note

This is the critical step.
You're merging new information into an existing note without losing or duplicating anything.

### Rules

1. **Only include sections that have content.**
   If a section heading doesn't exist yet and you have content for it, add it.
   If you don't have content for a section, don't add the heading.
   When adding a new section to an existing note,
   insert it in the standard order (Work, Meetings, Achievements, Team Pulse, Travel, Learning, Kudos, Notes)
   relative to sections already present.

2. **Use bullet points** (`-`) for all entries. Keep them concise but informative.

3. **Deduplicate intelligently:**
   - If an existing bullet covers the same topic as a new update, merge them —
     keep the more detailed version, or combine details if both add information.
   - "Merged DATA-4521" + "Merged DATA-4521 (fixed retry logic)" → keep the second one.
   - "3x 1:1s" + "had 2 more 1:1s" → "5x 1:1s" (or list them if names are given).
   - When in doubt about whether two items are the same, keep both —
     false dedup is worse than a minor duplicate.

4. **Preserve everything already in the note.**
   You are only adding or enriching, never removing content the user previously logged.

5. **Add context tags** to the frontmatter `tags` list for key topics mentioned
   (projects, people, locations).
   Check existing tags in the vault with Grep to reuse consistent naming.
   Use lowercase hyphenated slugs.

6. **Keep formatting clean.**
   No extra blank lines between bullets, one blank line between sections.

## Step 7: Write the File and Confirm

Write the updated note using the Write or Edit tool. Then confirm to the user:
- What was added (brief summary).
- The file path.
- If anything was merged with existing content, mention it.

Keep the confirmation short — enough so the user knows it worked.

## Handling Special Cases

### Multiple days at once

If the user provides updates spanning multiple days,
create/update each day's file separately.

### Weekly Summary

If the user asks to summarize their week (or passes "summary" as argument),
follow this workflow instead of the daily capture flow (Steps 2-7).

#### W1: Determine Week Range

Parse arguments to determine the target week:

| Argument | Range |
|----------|-------|
| `summary` (no qualifier) | Most recently completed full week (Mon-Fri). If today is Friday, use current week. |
| `summary this week` | Current Monday through today |
| `summary last week` | Previous Monday through Friday |
| `summary week of YYYY-MM-DD` | Monday through Friday of the week containing that date |

Compute `WEEK_START` (Monday), `WEEK_END` (Friday or today if current week), and ISO week number:

```bash
# Example: get Monday of current week
date -v-monday +%Y-%m-%d
# ISO week number
date +%V
```

Output file path: `~/docs/Daily/YYYY/Week NN.md`
where `NN` is the zero-padded ISO week number (e.g., `Week 10.md`).

#### W2: Collect Data

Gather personal activity from multiple sources.
Run independent queries in parallel where possible.
Skip any source that isn't available — warn the user, continue with the rest.

**W2a: Daily Notes**

Read all daily note files for each weekday in the range:
`~/docs/Daily/{YYYY}/{MM}/{YYYY-MM-DD}.md`

A week can span two months (e.g., Jan 29 in `01/`, Feb 2 in `02/`) — compute each day's path individually.
Extract all sections — these are the richest source of context.

**W2b: Other Obsidian Notes**

Search for notes modified during the target week:

```bash
# 1:1 notes
ls ~/docs/1-1s/*/YYYY-MM-DD.md 2>/dev/null  # for each weekday
# Meeting notes
ls ~/docs/Meetings/YYYY-MM-DD-*.md 2>/dev/null  # for each weekday
```

Skim for highlights — important decisions, notable conversations.

**W2c: GitHub PRs**

Query PRs authored and merged during the week:

```bash
gh search prs --author=@me --created={WEEK_START}..{WEEK_END} \
  --json title,url,state,repository,createdAt,mergedAt,additions,deletions --limit 30
gh search prs --author=@me --merged={WEEK_START}..{WEEK_END} \
  --json title,url,state,repository,createdAt,mergedAt,additions,deletions --limit 30
```

Deduplicate by URL across both queries.

**W2d: Jira Tickets**

```
atlassian_searchJiraIssuesUsingJql(
  jql = "assignee = currentUser() AND updated >= 'WEEK_START' AND updated <= 'WEEK_END' ORDER BY updated DESC",
  limit = 50
)
```

Note which tickets moved to Done/Resolved — those are accomplishments.

**W2e: Confluence Pages**

```
atlassian_searchConfluenceUsingCql(
  cql = "contributor = currentUser() AND lastmodified >= 'WEEK_START' AND lastmodified <= 'WEEK_END' AND type = page",
  limit = 20
)
```

**W2f: Google Drive Documents**

Scan `~/google-drive/` for files created or modified during the target week.
These are Google Workspace stubs — filenames and dates are usable, but contents are not readable.

Use Glob to discover files, then filter by modification date:

```bash
ls -la ~/google-drive/**/*.{gdoc,gslides,gsheet,pptx} 2>/dev/null
```

Classify by filename pattern:

| Pattern | Weekly Summary Section |
|---------|----------------------|
| `[Interview] *.gdoc` | Collaboration (count interviews conducted) |
| `*.gslides` or `*.pptx` (not `Untitled`) | Key Accomplishments (presentations created/updated) |
| Filename contains "RFC" | Key Accomplishments (RFC work) |
| `Notas -` or `Notes -` prefix | Skip — meeting scratch notes |
| `Untitled *` | Skip |
| Other `.gdoc` with descriptive title | Note for user context |

If `~/google-drive/` doesn't exist, skip and warn.

#### W3: Synthesize

Organize by theme, not by day or source.
Cross-reference daily notes with PR/ticket data. A daily note may add context to a PR title.

**Prose rules for the synthesis bullets:**

- Lead with the specific outcome. "Shipped DATA-4521, cut P99 from 1.2s to 200ms" not "made good progress on the migration".
- Banned vocabulary: delve, crucial, pivotal, robust, seamless, leverage, comprehensive, streamline, empower, best-in-class. Use the metric, tool, or action instead.
- No em dashes (`—` or `---`) or en dashes (`–`). Use a period or `to` in ranges.
- No rule-of-three padding. No trailing `-ing` clauses. No motivational transitions. No closing pep talks.
- If a week was quiet, reflect that. Do not pad.

| Category | What to include |
|----------|----------------|
| **Key Accomplishments** | Things completed, shipped, merged, decided. Link to PRs/tickets. |
| **In Progress** | Significant PRs opened, tickets advanced, ongoing projects |
| **Collaboration** | PR reviews given, notable meetings, 1:1 takeaways, decisions made |
| **Learning** | Articles, talks, workshops, new skills from daily Learning sections |
| **Risks & Blockers** | Open blockers, risks flagged in daily notes |

If a week was quiet, reflect that — don't pad.

#### W4: Generate Outputs

Produce two formats in the same file, separated by a horizontal rule.

**Confluence format** (verbose, structured):

```markdown
---
date_created: TODAY
category: weekly-summary
week: N
week_start: WEEK_START
week_end: WEEK_END
tags: [weekly-summary, week-N]
---

# Week N Summary (Mon DD - Fri DD, YYYY)

## Key Accomplishments
- Accomplishment with context and [PR](url) / [TICKET-123](url) links

## In Progress
- Work items still underway with current status

## Collaboration
- PR reviews, notable meetings, decisions

## Learning
- Articles read, talks attended, new skills

## Risks & Blockers
- Open blockers or risks

## Metrics
- GitHub: X PRs merged, Y opened, Z reviews given
- Jira: X tickets completed, Y in progress
```

**Slack format** (concise, max 15 bullets):

```
*Week N Summary (Mon DD - Fri DD)*

*Highlights:*
• Completed/shipped/merged X (TICKET-123)
• Advanced Y — now in review
• Key decision: Z

*Metrics:* X tickets closed | Y PRs merged

*Blockers:* (brief list or "None")
```

#### W5: Save and Present

1. Compute path: `~/docs/Daily/{YYYY}/Week {NN}.md`
2. Run `mkdir -p ~/docs/Daily/{YYYY}`
3. Write the file with both formats (Confluence first, `---` divider, then Slack version)
4. Show the Slack version in chat for easy copy-paste
5. Report the file path and any data gaps (e.g., "Jira skipped — Atlassian MCP not available")

### Referring to past entries

If the user says "what did I do last Tuesday?" or "find my notes about the Paris onsite",
Glob and Grep the `~/docs/Daily/` directory to find relevant entries.

### End-of-week or end-of-month

No special handling needed — each day stands on its own.
The folder hierarchy (`YYYY/MM/`) naturally groups them.

## Error Handling

| Error | Action |
|-------|--------|
| `~/docs/` directory doesn't exist | Create it with `mkdir -p ~/docs/Daily` and proceed |
| `~/docs/People/` directory doesn't exist | Create it with `mkdir -p ~/docs/People` when first person is mentioned |
| Date computation fails | Fall back to `date +%Y-%m-%d` for today |
| Daily note has unexpected format | Append new items at the end rather than inserting into sections |
| People file has unexpected format | Append `## Referenced In` section at the end |
| User input is entirely empty | Ask what they'd like to log using AskUserQuestion |
| `gh` CLI not installed or not authenticated | Skip GitHub collection in weekly summary, warn user, continue |
| Atlassian MCP tools not available | Skip Jira/Confluence collection in weekly summary, warn user, continue |
| `~/google-drive/` directory doesn't exist | Skip Google Drive collection in weekly summary, warn user, continue |
| No daily notes found for the target week | Proceed with GitHub/Jira/Confluence/Google Drive data only; warn user |
| Weekly summary file already exists | Read it, then use `AskUserQuestion` with options "Overwrite" / "Skip" / "Append" so the user picks without typing |
