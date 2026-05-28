---
name: "wrap-up"
description: "Use when user says \"wrap up\", \"close session\", \"end session\", \"wrap things up\", \"close out this task\", \"done for now\", \"that's it for today\", or invokes /wrap-up. Runs end-of-session checklist for shipping, reflection, and publishing. Does NOT handle: starting new work, debugging, or mid-session commits (use `/atcommit`)."
---

# Session Wrap-Up

Announce: "I'm using the /wrap-up skill to run the end-of-session checklist."

Run three phases in order.
Each phase is inline — no separate documents.
Auto-apply without asking; present a consolidated report at the end.

## Step 1: Ship It

Skip this phase if the user's invocation prompt contains `--skip-ship`.

### 1a: Commit Changes

Check for uncommitted changes:

```bash
git status --porcelain
```

| Status | Action |
|-|-|
| Changes exist | Invoke `/atcommit` to organize and commit them |
| No changes | Skip to 1b |

### 1b: Deploy

Check if the project has a deploy mechanism:

```bash
ls push.sh deploy.sh 2>/dev/null
grep -l "^deploy:" Makefile 2>/dev/null
```

| Found | Action |
|-|-|
| `push.sh` exists | Run `./push.sh` |
| `deploy` target in Makefile | Run `make deploy` |
| Neither exists | Skip — do not ask about manual deployment |

### 1c: Task Cleanup

Check for in-progress or stale tasks:

```bash
ls ~/docs/plans/do/*/FEATURE.md 2>/dev/null
ls ~/docs/plans/do/*/PLAN.md 2>/dev/null
```

For each discovered task or plan file:

| State | Action |
|-|-|
| Completed during this session | Mark as done in the state file |
| Stale (not touched in this session) | Flag for user awareness |
| Actively in progress | Leave as-is |

Present a brief summary of task states found.

## Step 2: Remember & Improve

Invoke the `/reflect` skill to extract session learnings,
route them to the appropriate knowledge files,
and analyze the session for self-improvement findings.

```
Skill(skill="reflect")
```

Capture the `/reflect` summary output for inclusion in the Phase 3 report.

## Step 3: Publish It

Skip this phase if the user's invocation prompt contains `--skip-publish`.

Review the full conversation for material that could be published.

### 3a: Content Discovery

Look for these signals:

| Signal | Content Type |
|-|-|
| Novel technical solution or debugging story | Blog post or Reddit thread |
| Community-relevant update or announcement | Announcement post |
| Educational content (how-to, tip, lesson learned) | Tutorial or tip post |
| Project milestone or feature launch | Launch post |

### 3b: Draft Generation

**If publishable material exists:**

For each piece of content:

1. Draft the article for the appropriate platform
2. Save to `~/docs/drafts/`

```bash
mkdir -p ~/docs/drafts
```

**Prose rules for every draft** (Reddit, blog, announcement, tutorial):

- Banned vocabulary: delve, crucial, pivotal, robust, seamless, leverage, tapestry, multifaceted, nuanced, comprehensive, streamline, empower, best-in-class, cutting-edge, "stands as a testament". Replace with the specific metric, tool, or action.
- No em dashes (`—` or `---`) or en dashes (`–`). Use a period, colon, or `to` in ranges.
- Straight quotes only. No curly quotes.
- No rule-of-three padding. No trailing `-ing` clauses. No motivational transitions. No closing pep talks.
- Smell tests on every paragraph: landing-page, read-aloud, signature.
- Density rule: five AI-slop words in two paragraphs means rewrite the passage.

Present suggestions:

```
All wrap-up steps complete. I also found potential content to publish:

1. "Title" — Brief description of the content angle.
   Platform: Reddit
   Draft saved to: ~/docs/drafts/title-slug.md
```

Wait for the user to respond before posting or finalizing.

**If no publishable material:** say "Nothing worth publishing from this session."

**Scheduling:** if multiple publishable items exist,
post the most time-sensitive one first and present a schedule for the rest.
Space posts at least a few hours apart per platform.

## Step 4: Summary

Present a consolidated report:

```markdown
## Session Wrap-Up Complete

### Ship It
- Commits: N atomic commits created (or "no changes")
- Deploy: deployed via push.sh (or "skipped")
- Tasks: N completed, N flagged

### Remember & Improve
(summary from /reflect output)

### Publish
- N drafts saved (or "nothing to publish")
```

## Error Handling

| Error | Action |
|-|-|
| `/atcommit` fails | Report the error, continue to Phase 2 |
| Deploy script fails | Report the error, continue to Phase 2 |
| `/reflect` fails | Report the error, continue to Phase 3 |
| No git repo | Skip Phase 1 entirely |
| `--skip-ship` argument | Skip Phase 1 |
| `--skip-publish` argument | Skip Phase 3 |
| No tasks or plans found | Skip 1c silently |
