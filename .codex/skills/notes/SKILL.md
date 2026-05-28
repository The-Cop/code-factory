---
name: "notes"
description: "Use when the user asks to create, look up, or edit a note in Obsidian — especially people-related notes like 1:1s, meeting notes, career plans, promotion docs, or per-person achievements. Also use for quick person-attribute lookups and updates: \"what's Nick's github\", \"Sarah's email\", \"set birthday to March 15\", \"update role to SE2\", \"who is X\", \"what team is Michelle on\". Triggers: \"note about\", \"log a meeting\", \"record a 1:1\", \"1:1 with Sarah\", \"update career plan for Alex\", \"promotion doc for Sam\", \"track a win for Jamie\", \"add to my notes\", \"write down\", \"log that\", \"record that\", \"find my notes about\", \"look up notes on\", \"meeting notes for\", \"what did I write about\", \"search my notes\", \"search my google docs\", \"find in google drive\", \"check google drive for\", \"X's github\", \"X's email\", \"set X's birthday\", \"update X's role\", \"what team is X on\"."
---

# Notes

Announce: "I'm using the /notes skill to manage your Obsidian notes."

You manage structured notes in the user's Obsidian vault —
1:1 records, meeting notes, career plans, promotion proposals, per-person achievements, and general notes.
All notes use consistent frontmatter, tags, and People wikilinks for Obsidian graph integration.

## Vault & Folder Structure

**Vault root:** `~/docs/`

```
~/docs/
├── 1-1s/
│   └── <Person Name>/
│       └── YYYY-MM-DD.md              # one file per session
├── People/
│   └── <Person Name>/
│       ├── <Person Name>.md                                  # overview: who they are, key traits
│       ├── <Person Name> - Career Plan.md                    # goals, milestones, active growth plan
│       ├── <Person Name> - Achievements.md                   # cumulative log of achievements
│       └── <Person Name> - Promotion Proposal to <Level>.md  # promotion doc (e.g. "to Senior")
├── Meetings/
│   └── YYYY-MM-DD-<slug>.md           # non-1:1 meeting notes
├── Daily/                              # managed by /daily — do not write here
└── Misc/
    └── <freeform>.md
```

## Frontmatter Convention

All notes include:

```yaml
---
date_created: YYYY-MM-DD
date_modified: YYYY-MM-DD
category: 1-1 | meeting | career-growth | promotion | achievements | overview | misc
tags: []
---
```

Meeting and 1:1 notes also include:

```yaml
attendees: [Name1, Name2]
```

Career-growth notes always include the tag `career`.

### Tag Extraction

When composing any note, extract relevant tags from content (topics, themes, locations, events, skills).

- **Reuse existing tags**: Grep `~/docs/**/*.md` for `^tags:` to find tags already in use.
  Prefer existing spelling to avoid duplicates (e.g., use `ops-review` if it exists, not `opsreview`).
- Use lowercase hyphenated slugs for multi-word tags (e.g., `paris-summit`, `technical-leadership`).
- Aim for 2-5 content tags per note beyond mandatory ones.

## Step 1: Get Today's Date

**Always run `date +%Y-%m-%d` first.** Store the result as `TODAY`. Never hardcode dates.

## Step 2: Classify the Request

Use this decision tree:

| Signal | Category | Target Path |
|--------|----------|-------------|
| Person + specific attribute query ("github", "email", "team", "role", "birthday") | `person-attribute` | `People/<Person>/<Person>.md` (frontmatter) |
| Person + "1:1" / "one on one" / "one-on-one" | `1-1` | `1-1s/<Person>/TODAY.md` |
| "meeting" + multiple people or a topic | `meeting` | `Meetings/TODAY-<slug>.md` |
| Career goals / growth plan / development for a person | `career-growth` | `People/<Person>/<Person> - Career Plan.md` |
| "promotion" for a person | `promotion` | `People/<Person>/<Person> - Promotion Proposal to <Level>.md` |
| Achievements logged for a specific person | `achievements` | `People/<Person>/<Person> - Achievements.md` |
| Overview / profile / "who is X" | `overview` | `People/<Person>/<Person>.md` |
| None of the above | `misc` | `Misc/<slug>.md` |
| **Unclear or ambiguous** | — | **Ask using an interactive prompt before creating anything** |

Slug = lowercase letters and hyphens, max ~5 words derived from the topic.

## Step 3: Resolve Person Name

When the user mentions someone by first name, nickname, or partial name:

1. Use `Glob(pattern="*/", path="~/docs/People")` to get the list of known people.
2. Match the input against existing directories using this priority order:

| Priority | Rule | Example |
|----------|------|---------|
| 1 | **Exact match** — input matches a directory name exactly | "Nick Nakas" → `Nick Nakas/` |
| 2 | **First-name match** — input matches the first name of exactly one person | "Nick" → `Nick Nakas/` |
| 3 | **Accent-insensitive match** — strip accents before comparing | "Alvaro" → `Álvaro Mongil/`, "Felicite" → `Félicité Lordon/` |
| 4 | **Substring match** — input is a clear substring of exactly one name | "Mongil" → `Álvaro Mongil/` |

3. **Multiple matches at any priority**: use an interactive prompt to present candidates and let the user pick.
4. **No match**: bootstrap a new People entry.
   Create `~/docs/People/<Full Name>/<Full Name>.md` with:

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
Brief context from the current interaction.
```

For the relationship tag, use your best guess: `report`, `collaborator`, `peer`, `skip-level`, `external`, etc.
If only a first name is given and you can't infer the full name from context, ask using an interactive prompt.

Use full names wrapped in Obsidian wikilinks (`[[Full Name]]`) in note content for graph integration.

## Step 4: Determine Operation

Parse the request to determine the operation: **CREATE**, **LOOKUP**, or **EDIT**.

If the category is `person-attribute`, route to the dedicated person-attribute handlers below.
Otherwise, default to CREATE for new content and LOOKUP for questions about existing notes.

### Person-Attribute LOOKUP

For queries like "what's Nick's github?", "Sarah's email", "what team is Michelle on?":

1. Resolve the person name (Step 3).
2. Read the person's overview file (`People/<Person>/<Person>.md`).
3. Check YAML frontmatter first for the requested attribute.
4. If not in frontmatter, search the markdown body for the information.
5. Return the answer concisely.

### Person-Attribute EDIT

For updates like "set Nick's birthday to March 15", "update Michelle's role to SE2":

1. Resolve the person name (Step 3).
2. Read the person's overview file.
3. **Field name consistency** — before creating a new frontmatter field,
   scan existing People files to find if a field for this concept already exists:

```
Grep ~/docs/People/ for the concept (e.g., "birthday", "birth", "dob" for birthday)
```

| Situation | Action |
|-----------|--------|
| Existing field name found across People files | Reuse that exact field name (preserving casing, hyphens, underscores) |
| No existing field for this concept | Choose a concise field name matching existing style: lowercase, no underscores for single words, underscores for multi-word (e.g., `github`, `email`, `role`, `team`, `start_date`) |

4. **Determine where the attribute belongs:**

| Frontmatter (structured, queryable) | Body (narrative, contextual) |
|--------------------------------------|------------------------------|
| `role`, `team`, `github`, `email`, `slack`, `birthday`, `location`, `timezone`, `start_date`, `phone` | Overview descriptions, key traits, notable work, relationships, contextual notes |

5. Apply the update. Update `date_modified` to TODAY.
6. Confirm the change, showing the field name used.

**Date format**: use `YYYY-MM-DD` to match `date_created`/`date_modified` convention.
If the user gives a partial date like "March 15" without a year, store as `MM-DD` (e.g., `03-15`).

### CREATE

1. Run `mkdir -p` on the parent directory.
2. Check if the target file already exists (use Read):

| Category | If file exists | If file doesn't exist |
|----------|---------------|----------------------|
| `1-1` | Append a new `## Session` heading with content | Create fresh with frontmatter |
| `career-growth` / `achievements` | Append with `- TODAY: <content>` bullets | Create fresh with frontmatter |
| `meeting` | Ask whether to append or create new file | Create fresh with frontmatter |
| `promotion` | Ask whether to update or create new file | Create fresh with frontmatter |
| All others | Ask whether to append or create new | Create fresh with frontmatter |

3. Compose content: frontmatter + bullet-list body.
4. Write or Edit the file.
5. Confirm the absolute path to the user.

### LOOKUP

1. Glob `~/docs/**/*.md` filtered by relevant filename keywords (exclude `Daily/`).
2. If no filename match: Grep vault content for keywords (exclude `Daily/`).
3. Search personal Google Drive for matching filenames:
   `Glob(pattern="**/*.gdoc", path="~/google-drive/")` and filter results by keywords.
   Also check `*.gslides` and `*.gsheet` patterns.
   These are Google Workspace stubs — filenames are searchable but contents are not readable.
   Include matching Google Drive files in results alongside Obsidian notes.
4. Results:
   - **0 matches** (in both Obsidian and Google Drive): inform user, offer to create a new note.
   - **1 match**: Read and display the file (or report the Google Drive filename if it's a stub).
   - **Multiple matches**: use an interactive prompt to let user pick.

### EDIT

1. Run LOOKUP to find the file.
2. Apply the requested changes (preserve all existing content not being changed).
3. Keep frontmatter fields in their existing order; add new fields after the last custom field.
4. Update `date_modified` in frontmatter to TODAY.
5. Confirm the path and changes to the user.

## Step 5: Update People Backlinks

After creating or editing a note that mentions people,
update each mentioned person's People file by appending a backlink under `## Referenced In`:

```
- `<relative-path-from-vault>` - Brief context of the mention
```

If `## Referenced In` doesn't exist, add it.
If there's already a backlink for today's date in the same file, update rather than duplicate.
This creates two-way links: notes mention people, People files link back to notes.

## Formatting Rules

- Bullet lists over prose. Use `-` bullets for all note content where possible.
- Concise. Preserve information density, not narrative or filler.
- Keep frontmatter minimal and correct.
- One blank line between sections, no extra blank lines between bullets.
- No em dashes (`—` or `---`) or en dashes (`–`). Use a period, colon, or `to` in ranges.

## Prose Guardrails

When a note contains narrative prose (career plans, promotion proposals, overview sections, misc long-form notes), follow the rules in `references/prose-guardrails.md`:

- Banned vocabulary (delve, crucial, robust, seamless, leverage, tapestry, multifaceted, etc.).
- Smell tests: landing-page, read-aloud, signature.
- Density rule: rewrite passages with five or more AI-slop words in two paragraphs.
- No rule-of-three padding, no trailing `-ing` clauses, no motivational transitions.

Bullet-only notes (1:1 logs, achievements, daily entries) can skip the guardrails but must still avoid em and en dashes.

## Error Handling

| Error | Action |
|-------|--------|
| `~/docs/` directory doesn't exist | Create it with `mkdir -p` and proceed |
| `~/docs/People/` directory doesn't exist | Create it with `mkdir -p` when first person is mentioned |
| Person name ambiguous (multiple matches) | Use an interactive prompt to clarify |
| Request is completely vague (e.g., "create a note") | Use an interactive prompt to clarify category before doing anything |
| File has unexpected format | Append content at the end rather than inserting into sections |
| Glob/Grep returns too many results | Narrow with additional keywords, then present top 5 matches |
| `~/google-drive/` directory doesn't exist | Skip Google Drive search, continue with Obsidian results only |
| Google Drive file found but not readable | Report the filename to the user — contents are stubs, not readable |
