# RFC Phase Flow: Detailed Agent Dispatch

Reference for each phase's agent dispatch, prompts, and expected outputs.

## REFINE Phase

**Agent:** `productivity:refiner`

**Dispatch prompt template:**

```
subagent(
  agent = "refiner",
  description = "Refine RFC topic: <short topic>",
  task = "
<rfc_topic>
<user's topic>
</rfc_topic>

<context>
RFC type: <problem_statement|design>
</context>

<task>
Refine this RFC topic into a detailed specification. This is for an RFC document, not code.

1. Analyze the topic for ambiguity, missing context, and scope questions.
2. Gather concrete inputs from the user. Ask for each of these (one at a time, preferring multiple choice):
   - Problem statement with specific examples and measured impact
   - Constraints: latency, cost, staffing, deadlines, compliance requirements
   - Existing system details: what exists today, links or descriptions of current architecture
   - Non-goals: what is explicitly out of scope and why
   - Alternatives the user has already considered (even rough ideas)
   - Risks the user already suspects
   - Migration expectations: phased rollout, backwards compatibility, data backfill
   - Open questions the user already knows about
   If the user does not provide these, the RFC will fill gaps with guesses. Guesses read as AI-generated.
3. Propose 2-3 approaches to scoping this RFC. For each approach:
   - What would be included and excluded
   - Target audience and stakeholders
   - Estimated complexity and coverage
   Lead with the recommended approach and explain why.
4. After the user selects an approach, produce a refined specification:
   - Problem statement (2-3 sentences, with quantified impact)
   - Scope boundaries (in/out, with rationale for each exclusion)
   - Target audience and the decision they need to make
   - Constraints and non-goals
   - Known alternatives and suspected risks
   - Key questions that research must answer
   - Success criteria for the RFC document itself
5. Questions to the user should be ONE at a time, preferring multiple choice.

ITERATION MODE (when iterates_on is set in RFC-STATE.md):
You also receive the existing RFC document and the user's improvement request.
Focus refinement on what needs to change, not on re-establishing the entire specification.
Carry forward the original refined specification and update only the parts affected by the iteration.
</task>
"
)
```

**Output:** Refined specification written to RFC-STATE.md body section.

**Phase status transitions:** `not_started` → `in_progress` → `completed`

## RESEARCH Phase

**Agent:** `productivity:researcher`

**Dispatch prompt template:**

```
subagent(
  agent = "researcher",
  description = "Research for RFC: <short-name>",
  task = "
<rfc_specification>
<refined spec from REFINE phase>
</rfc_specification>

<key_questions>
<questions identified during REFINE>
</key_questions>

<task>
Research the following for an RFC document. Do NOT write the RFC. Only gather and organize findings.

Research sources (search ALL of these):
1. **Web**: Prior art, industry best practices, benchmark data, similar systems at other companies
2. **Confluence**: Internal documentation, existing RFCs, architecture decisions, team wikis
3. **Jira**: Related tickets, epics, past work, ongoing initiatives
4. **GitHub**: Related PRs, issues, existing implementations, code patterns

For each finding:
- Capture the source URL (Confluence page URL, Jira ticket URL, GitHub URL, web URL, or file path)
- Format citations as markdown links with short text: [short title](url)
  Examples: [Event Pipeline RFC](https://confluence.example.com/pages/123), [LOGS-4521](https://jira.example.com/browse/LOGS-4521)
  For code paths, use inline code: \`services/user/models/schema.go:45-80\`
- Extract the relevant data point or insight
- Note how it relates to the RFC topic

CRITICAL: Always capture the full URL for each source. The WRITE phase needs URLs to create clickable citations.

Organize findings by:
1. **Domain Context**: What exists today, what has been tried before
2. **Technical Findings**: Relevant technologies, patterns, benchmarks
3. **Organizational Context**: Teams involved, dependencies, constraints
4. **Data Points**: Metrics, benchmarks, cost figures, timelines
5. **Open Questions**: What could not be answered (needs user input or further investigation)

CRITICAL: Every finding must have a source citation. Do not present assumptions as findings.
</task>
"
)
```

**Output:** Write `RESEARCH.md` in the plan directory.

## EXPLORE Phase

**Agent:** `productivity:explorer`

**Skip condition:** The RFC has no source code component (pure process/organizational RFC). Mark as `skipped` in state.

**Dispatch prompt template:**

```
subagent(
  agent = "explorer",
  description = "Explore codebase for RFC: <short-name>",
  task = "
<rfc_specification>
<refined spec>
</rfc_specification>

<research_findings>
<summary of RESEARCH.md>
</research_findings>

<task>
Explore the codebase to gather technical context for an RFC document. Do NOT write the RFC.

1. Map the relevant code areas:
   - Key files, modules, and packages
   - Interfaces and APIs
   - Data models and schemas
   - Dependencies (internal and external)

2. Identify existing patterns:
   - How similar problems are currently solved
   - Architectural conventions and constraints
   - Testing patterns in use

3. Assess impact:
   - What code would be affected by the RFC's proposal
   - Which teams own the affected areas
   - What integration points exist

Output a structured exploration report with file paths and code references.
CRITICAL: Cite specific file paths and line numbers for all findings.
</task>
"
)
```

**Output:** Write `EXPLORATION.md` in the plan directory.

## PLAN Phase

**Agent:** `productivity:planner`

**Dispatch prompt template:**

```
subagent(
  agent = "planner",
  description = "Plan RFC writing: <short-name>",
  task = "
<rfc_specification>
<refined spec>
</rfc_specification>

<research_findings>
<full RESEARCH.md content>
</research_findings>

<exploration_notes>
<full EXPLORATION.md content, or 'N/A - no code component' if skipped>
</exploration_notes>

<rfc_template>
<the appropriate template content based on rfc_type>
</rfc_template>

<task>
Create a section-by-section writing plan for this RFC. Do NOT write the RFC. Plan how to write it.

For each section in the template:
1. **What to write**: Key points, arguments, data to include
2. **Sources to cite**: Which research findings or code references to use
3. **Quality criteria**: What makes this section complete and convincing
4. **Open questions**: What must be resolved before this section can be written
5. **Estimated depth**: Brief (1-2 paragraphs) or detailed (multiple subsections)

Also include:
- **Section ordering**: Any sections that should be written before others (dependencies)
- **Diagram needs**: Which sections benefit from architecture, flow, or deployment diagrams
- **Data gaps**: Research findings still needed (flag for user)
- **Reviewer guidance**: What reviewers should focus on per section

The plan must be specific enough that a writer can execute it without further research.

ITERATION MODE (when iterates_on is set in RFC-STATE.md):
You also receive the existing RFC document, the previous PLAN.md (if available), and the iteration context.
Create a targeted revision plan: identify which sections need changes, what changes to make, and which sections to preserve as-is.
Do not re-plan sections that are not affected by the iteration.
</task>
"
)
```

**Output:** Write `PLAN.md` in the plan directory.

## CONSISTENCY_CHECK Phase

**Agent:** `productivity:consistency-checker`

**Dispatch prompt template:**

```
subagent(
  agent = "consistency-checker",
  description = "Check RFC plan consistency: <short-name>",
  task = "
<plan>
<full PLAN.md content>
</plan>

<research>
<full RESEARCH.md content>
</research>

<specification>
<refined spec from RFC-STATE.md>
</specification>

<task>
Check this RFC writing plan for internal consistency. Look for:

1. **Contradictions**: Does the plan say different things about the same topic in different sections?
2. **Terminology drift**: Are the same concepts referred to by different names?
3. **Missing references**: Does a section reference findings that don't appear in the research?
4. **Scope mismatch**: Does the plan include sections outside the refined scope, or miss required sections?
5. **Unsupported claims**: Does the plan assume data points not found in research?
6. **Ordering issues**: Are section dependencies satisfied by the proposed writing order?

Fix minor issues directly. Flag blocking issues that require user decision.
</task>
"
)
```

**Output:** Updated PLAN.md (fixes applied), blocking issues noted in RFC-STATE.md.

## REVIEW Phase

**No agent dispatch.** Direct interaction with user.

**Interactive mode:**
1. Present the writing plan section by section
2. Highlight key decisions and trade-offs
3. Show open questions that need resolution
4. Ask for: approval, feedback, or backtrack target

**Autonomous mode:**
1. Log the plan summary
2. Proceed unless blocking open questions exist
3. If blocked: stop and report

**Output:** Write `REVIEW.md` with feedback and decisions.

## WRITE Phase

**Agent:** `general-purpose` (fresh subagent with full context)

**Dispatch prompt template:**

```
subagent(
  agent = "general-purpose",
  description = "Write RFC: <short-name>",
  task = "
<writing_plan>
<full PLAN.md content>
</writing_plan>

<research_findings>
<full RESEARCH.md content>
</research_findings>

<exploration_notes>
<full EXPLORATION.md content or 'N/A'>
</exploration_notes>

<rfc_template>
<the appropriate template content>
</rfc_template>

<writing_guidelines>
<content from references/writing-guidelines.md>
</writing_guidelines>

<review_decisions>
<full REVIEW.md content>
</review_decisions>

<output_path>
<path to output RFC file>
</output_path>

<task>
Write the RFC document following the plan exactly. Write to the output_path.

You are the tech lead writing for senior engineers, SRE/oncall, and product leadership. They need to make a go/no-go decision based on this document.

Tone: crisp, technical, specific. No hype. No generic filler.
Style: short sentences. Active voice. Prefer nouns and verbs over adjectives. If data is missing, write an explicit assumption or flag it as an Open Question. Do not invent facts.

MULTI-PASS EDITORIAL PROCESS:

Pass 1 (Draft):
1. Follow the template structure. Do not add or remove sections unless the plan specifies it.
2. Write each section per the plan's instructions (key points, sources, quality criteria).
3. CITE SOURCES: Every technical claim must reference a research finding, code path, or user decision.
   Use markdown links with short text: [short title](url). For code paths, use inline code.
   NEVER use verbose parenthetical citations like (Source: Confluence, "Page Title" page 123456).
   Examples: [Event Pipeline RFC](https://confluence.example.com/pages/123), `services/user/schema.go:45`
4. Open questions that could not be resolved go in the 'Open Questions' section. Do not guess answers.
5. Include sharp edges: what will break first, what is annoying about this design, what we are punting.
6. Include cost and capacity estimates with stated assumptions.
7. Include operational impact: what changes for oncall, what alerts/dashboards/runbooks are needed.
8. Write "How we know it worked" with measurable acceptance criteria.

Pass 2 (Tighten):
After the full draft, do a tightening pass:
1. Remove banned words: "robust", "seamless", "leveraging", "best-in-class", "comprehensive", "streamline", "cutting-edge", "innovative", "empower". Replace each with a specific, measurable claim.
2. Remove motivational transitions: "This brings us to...", "It is worth noting...", "Importantly, ..."
3. Remove thesis restatements. State each point once.
4. Check terminology consistency: every concept uses the same term throughout.
5. Replace vague qualifiers ("significant", "minimal", "substantial") with numbers or explicit assumptions.
6. Verify each paragraph is under 5 sentences. Split longer ones.
7. Apply typographic rules:
   - No numbered headings. Use `## Overview`, not `## 1. Overview`. Numbers in headings are only acceptable for ordered sequences (steps, migration phases).
   - No em dashes. Use colons, semicolons, or split sentences.
   - Straight quotes only.
   - No bold or italic formatting inside sentences.

Pass 3 (Red Team):
After tightening, do a critic pass:
1. List the 3 strongest objections a reviewer would raise.
2. For each objection, either strengthen the relevant section or add the objection and response to the document.
3. Check: would a staff engineer find every section convincing? Flag and fix weak spots.
4. Check coherence: do sections reference each other consistently?
5. Check completeness: are all plan items covered?
6. Check citations: does every claim have a source?
7. Verify the document reads like it was written by an engineer who built the system, not by someone summarizing it from the outside.

ITERATION MODE (when iterates_on is set in RFC-STATE.md):
If this is an iteration on an existing RFC, you also receive:

<existing_rfc>
<content of the RFC being improved>
</existing_rfc>

<iteration_context>
<improvement request and feedback from user>
</iteration_context>

Additional rules for iteration:
1. Read the existing RFC first. Identify which sections need changes based on the iteration context.
2. Preserve unchanged sections verbatim. Do not rewrite sections that are not targeted for improvement.
3. For targeted sections, apply the same multi-pass editorial process (Draft, Tighten, Red Team).
4. If feedback contradicts research findings, flag the contradiction as an Open Question rather than silently overriding the research.
5. Update citations if new research was gathered in this iteration.

Write the final document to the output path.
</task>
"
)
```

**Post-write review (interactive mode):**
1. Read the generated RFC
2. Present a section-by-section summary to the user
3. Ask for feedback on each section
4. Dispatch follow-up edits as needed

**Output:** RFC at `~/docs/rfcs/<short-name>-<date>.md`

## DONE Phase

**No agent dispatch.**

1. Update RFC-STATE.md: `current_phase: DONE`, all phases `completed`
2. Read the final RFC and present summary:
   - Document location and word count
   - Key decisions made
   - Sources referenced (count and types)
   - Open questions remaining
   - Suggested next steps:
     - For problem statements: "Share for review, then proceed to design phase if approved"
     - For design docs: "Share for review, address feedback, then publish"
3. Suggest reviewers based on stakeholders identified during REFINE
