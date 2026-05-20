# Review Output Format

The review is always rendered top-down in this order, regardless of mode.
Omit any section with no content.
Format with semantic line breaks: one sentence per line, break after clause-separating punctuation, target 120 characters per line.

## Single-reviewer template (Claude or Codex alone)

```markdown
## PR Review: <title>

**PR:** <url>
**Author:** <author>
**Base:** <baseRefName> ← <headRefName>
**Changes:** +<additions> -<deletions> across <changedFiles> files
**Reviewer:** Claude | Codex
**Worktree:** <path or "diff-only fallback">

---

### PR Intent

<2-4 sentence statement of the PR's objective, derived from title, body, linked issues, and tests.
End with one of:
- "Stated explicitly in the PR body."
- "Inferred from diff — see Uncertainty below."

If inferred, add an **Uncertainty** block listing the signals used and any alternative interpretations rejected.>

---

### File Coverage Checklist

| # | File | Module | Reviewed |
|---|------|--------|----------|
| 1 | `path/a.go` | api | ✓ |
| 2 | `path/b.go` | api | ✓ |
| 3 | `path/c_test.go` | api | ✓ |

**Coverage:** N of N files reviewed.

Every file in the PR diff must appear in this table.
A file is not reviewed until it appears under a Module section below.

---

### Cross-cutting Observations

Use this section for findings that do not belong to a single module.
Omit subsections with no entries.

#### Interface Changes

| Change | Type | Compatibility | Location |
|--------|------|---------------|----------|
| <what changed> | <API/struct/HTTP endpoint/CLI flag/config key> | Additive or Breaking | `file:line` |

#### Database / Schema Changes

| Change | Location | Migration Required |
|--------|----------|-------------------|
| <table/column/index> | `file` | Yes/No |

#### Other cross-cutting

- Security posture
- Performance/regression risk
- Observability gaps

---

### Module Reviews

One section per logical module.
Modules are inferred (may span directories or split a directory).

#### Module: <module-name>

**Intent (this module):** <one sentence — how this module advances the overall PR intent.>

**Files reviewed:** `path/a.go` (lines 12-48, 102-130), `path/b.go` (lines 1-90)

**Findings**

List every finding the framework's checks produced.
Do not cap, do not collapse, do not select "top issues".
If a defect appears at five locations, write five rows with five locations.

| Level | Severity | Confidence | Location | Issue | Why It Matters | Likely Impact | Best Fix |
|-------|----------|-----------|----------|-------|----------------|---------------|----------|
| Intent | Major | HIGH | `path/a.go:24` | Adds telemetry not mentioned in PR body | Hidden scope creep; reviewers don't know to verify the metric | Wrong dashboards may light up after deploy | Move to a separate PR or document in the body |
| Logic | Critical | HIGH | `path/b.go:55` | Missing nil check before deref | Will panic on first request with a missing header | Production crash on first traffic | Add `if h == nil { return errMissingHeader }` |
| Quality | Minor | LOW | `path/a.go:102` | Magic number `7200` | Reader has to guess what 7200 means | Slows future maintenance | Extract as `sessionTimeoutSeconds = 7200` |

Levels: Intent / Logic / Quality.
Severity: Critical / Major / Minor.
Confidence: HIGH / MEDIUM / LOW.

**Per-check audit**

Every check in the three-level framework must be ticked.
`✓ findings` means the check produced at least one finding row above.
`✓ scanned` means the check was applied and produced nothing.
A module is not reviewed until every check is ticked.

| Level | Check | Status |
|-------|-------|--------|
| Intent | Alignment | ✓ findings / ✓ scanned |
| Intent | Scope creep | ✓ findings / ✓ scanned |
| Intent | Missing pieces | ✓ findings / ✓ scanned |
| Intent | Surprise | ✓ findings / ✓ scanned |
| Intent | Test alignment | ✓ findings / ✓ scanned |
| Logic | Control flow | ✓ findings / ✓ scanned |
| Logic | Nil/null/zero | ✓ findings / ✓ scanned |
| Logic | Error paths | ✓ findings / ✓ scanned |
| Logic | Invariants | ✓ findings / ✓ scanned |
| Logic | Concurrency | ✓ findings / ✓ scanned |
| Logic | Ordering | ✓ findings / ✓ scanned |
| Logic | Edge cases | ✓ findings / ✓ scanned |
| Logic | Backward compatibility | ✓ findings / ✓ scanned |
| Logic | Old/new interactions | ✓ findings / ✓ scanned |
| Logic | Idempotency | ✓ findings / ✓ scanned |
| Quality | Duplication | ✓ findings / ✓ scanned |
| Quality | Magic values | ✓ findings / ✓ scanned |
| Quality | Dead code | ✓ findings / ✓ scanned |
| Quality | Abstractions | ✓ findings / ✓ scanned |
| Quality | Naming | ✓ findings / ✓ scanned |
| Quality | Patterns | ✓ findings / ✓ scanned |
| Quality | Error handling | ✓ findings / ✓ scanned |
| Quality | Security | ✓ findings / ✓ scanned |
| Quality | Performance | ✓ findings / ✓ scanned |
| Quality | Test quality | ✓ findings / ✓ scanned |
| Quality | Test seams | ✓ findings / ✓ scanned |

**Missing or Insufficient Tests**

- <gap + suggested test name + assertion>
- Or: "Coverage is adequate."

**Pre-merge Cleanup**

- <follow-up needed before merge>
- Or: "None."

---

(repeat per module)

---

### Verdict

**<Approve / Request Changes / Comment>**

<1-2 sentence rationale that ties back to PR Intent.>
```

## Dual-reviewer template (Claude + Codex)

When `--claude-codex` is set, run both reviewers and present:

```markdown
## PR Review: <title>          [Reviewers: Claude + Codex]

**PR:** <url> | **Author:** <author> | **Base:** <base> ← <head>
**Changes:** +<adds> -<dels> across <n> files
**Worktree:** <path>

### PR Intent

<Single source of truth — Claude's extraction. If Codex disagrees on intent, note it in the Reconciliation section.>

### File Coverage Checklist

<Single table. Each row marked ✓ when both reviewers have covered it.>

### Reviewer Comparison

| Topic | Claude | Codex |
|-------|--------|-------|
| Verdict | Approve / Request Changes / Comment | Approve / Request Changes / Comment |
| Critical findings | N | M |
| Major findings | N | M |
| Minor findings | N | M |
| Unique to reviewer | <one-line summary of findings only this reviewer caught> | <same> |
| Agreed findings | <one-line summary of findings both reviewers caught> |

### Reconciliation

<1-3 sentences explaining where the reviewers diverge and which interpretation is more likely correct.
Tie back to PR Intent. Omit if both reviewers agree.>

### Verdict

Claude: <verdict> | Codex: <verdict>
<Combined recommendation in 1-2 sentences.>

---

<details><summary>Claude Review (full)</summary>

<full module-by-module review using the single-reviewer template>

</details>

<details><summary>Codex Review (full)</summary>

<verbatim Codex output, unmodified>

</details>
```

## Empty-review case

Applies to both single-reviewer and dual-reviewer templates.
If no findings exist at any level for any module:

```markdown
### Module: <module-name>
**Intent (this module):** ...
**Files reviewed:** ...
**Findings:** None.
**Missing or Insufficient Tests:** Coverage is adequate.
**Pre-merge Cleanup:** None.
```

The Verdict in that case is `Approve` with a rationale noting that all changes align with intent and no issues were found.
