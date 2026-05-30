# Interactive Question Bank

Questions for Step 4 of the `/brag` skill.
Grouped by brag document section. Ask in order. Skip sections already well-covered by automated collection.

## Question Design

- Present questions one at a time using `ask_question`.
- Always include an option that allows free-text input (e.g., "Yes — describe in Other").
- Do not force multiple rounds of follow-up — if the user provides details in their first answer, use them directly.
- Skip categories where automated collection already found 3+ entries.

### Data Capture Rules

For every "Yes" answer, always follow up for:

| Field | Required | How to ask |
|-------|----------|-----------|
| **Date** | Always | "When did this happen?" Accept exact dates, weeks, or months. |
| **Links** | When available | "Do you have a link? (PR, Confluence, Google Doc, Jira, Slack thread)" |
| **Quotes** | For ephemeral sources | "Can you paste the key Slack message? Links may not be accessible later." |

**Ephemeral sources** that need quotes: Slack messages, Slack threads, DMs, temporary shared docs.
**Durable sources** that only need links: GitHub PRs, Confluence pages, Jira tickets, published Google Docs.

## Questions

### Documentation & Talks

1. "Did you create any documentation, Confluence pages, or design docs I may have missed?"
   - If yes: ask for title, URL, and brief description of audience/purpose
2. "Did you give any talks, presentations, or demos?"
   - If yes: ask for title, event/audience, and date

### Bar-Raising

3. "Did you do anything to raise the engineering bar?"
   - Examples: process improvements, tooling, standards, templates, review practices, on-call work
   - If yes: ask for description and who benefited

### Consulting

4. "Did you provide expertise or consulting to other teams?"
   - If yes: ask for team name, topic, who was involved, and outcome

### People & Networking

5. "Did you meet anyone new or have notable 1:1s worth logging?"
   - Examples: coffee chats, visiting colleagues, team socials, donut meetings, offsites
   - If yes: ask for who, what you discussed, and any outcomes

### Interviewing

6. "Did you conduct any interviews?"
   - If yes: present interview types from state and ask for type and count
   - If a new type is mentioned, add it to `state.interview_types`

### Mentorship

7. "Are you mentoring anyone new?"
   - If yes: ask for name, start date, and context (program, informal, new-hire mentor)
   - Add to `state.mentees.current`

### Learning

8. "Did you learn anything significant?"
   - Examples: new tool, technique, domain knowledge, course, book, conference talk
   - If yes: ask what you learned and how it applies to your work

### Guilds & Groups

9. "Did you participate in any guild, ERG, or community group activity?"
   - If yes: ask for group name and what you did
   - If new group, add to `state.guilds`

### Customer Engagement

10. "Did you do any embed work, customer discovery, or cross-team pairing?"
    - If yes: ask for team/context, duration, what you did, and what you learned

### Goals

11. "Any progress on your current goals or objectives?"
    - If yes: ask which goal and what progress was made

### Open-Ended

12. "Anything else worth logging that I didn't ask about?"
    - This catches work that doesn't fit neatly into categories

## Google Drive File Classification

When scanning `~/google-drive/`, classify by filename pattern:

| Pattern | Brag Section |
|---------|-------------|
| `[Interview] *.gdoc` or files under `interviews/*/` | Interviewing (count by name) |
| `*.gslides` or `*.pptx` (not `Untitled`) | Docs & Talks |
| Filename contains "RFC" | Docs & Talks |
| Files under `code/` | Direct Impact or Docs & Talks |
| `Notas -` or `Notes -` prefix | Skip — meeting scratch notes |
| `Untitled *` | Skip |
| `*.gsheet`, `*.gdraw` | Skip unless title suggests a significant artifact |
| Promo docs, career docs | Skip — inputs, not outputs |
| Other `.gdoc` with descriptive title | Uncategorized |
