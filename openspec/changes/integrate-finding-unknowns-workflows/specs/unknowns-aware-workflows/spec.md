## ADDED Requirements

### Requirement: Exploration surfaces consequential blindspots
Read-only exploration SHALL report material unknowns that can change scope, architecture, behavior, or review strategy using landmines, hidden constraints, quality examples, high-impact questions, and a revised request or decision summary.
The workflow MUST state when no significant blindspots are found rather than inventing concerns.

#### Scenario: Unfamiliar code area contains hidden constraints
- **WHEN** a user explores an unfamiliar code area whose conventions or history constrain the requested change
- **THEN** the workflow reports those constraints, the likely landmines, evidence-backed provisional answers, and a revised request before recommending implementation

#### Scenario: Explored area has no consequential unknowns
- **WHEN** repository evidence shows the requested area is straightforward and has no material hidden constraints
- **THEN** the workflow states that no significant blindspots were found and avoids padding the result with low-value trivia

### Requirement: References are analyzed as semantic specifications
Reference-led workflows SHALL summarize behaviors, guarantees, deliberate decisions, incidental details, translation gaps, and license constraints before target implementation begins.
The target repository's conventions MUST define how the semantics are implemented.

#### Scenario: Reference uses a different language or framework
- **WHEN** a user asks for target behavior based on source code from another language or framework
- **THEN** the workflow presents a semantics summary and native target equivalents instead of proposing a line-by-line transliteration

#### Scenario: Reference license is unclear
- **WHEN** the workflow cannot confirm that source text may be copied
- **THEN** it limits the work to behavioral analysis, flags the license uncertainty, and avoids copying implementation text

### Requirement: Brainstorming supports disposable divergent prototypes
`/brainstorm` SHALL provide an explicit prototype mode for one decision at a time.
The mode MUST generate three to five materially different variants, label the belief each variant tests, and summarize the requirement learned from the user's reactions.

#### Scenario: User can recognize but not describe a preference
- **WHEN** a user requests prototype exploration for a layout, approach, name, tone, or similar decision
- **THEN** the workflow produces disposable variants spanning distinct assumptions and asks the user to react before converging

#### Scenario: Variants do not reveal a preference
- **WHEN** the user rejects every proposed variant for similar reasons
- **THEN** the workflow reframes the decision space instead of producing more variants based on the same assumptions

#### Scenario: Prototype could be mistaken for production code
- **WHEN** prototype mode creates executable visual output
- **THEN** the workflow marks it as disposable, uses fake data without production integration, and does not wire it into the application

### Requirement: Clarification questions are ordered by blast radius
Clarification workflows SHALL ask one question at a time and order unresolved questions as architecture-changing, behavior-defining, then polish.
They MUST avoid questions answerable from repository or referenced evidence and MUST stop when remaining uncertainty is cheaper and safe to resolve during implementation.

#### Scenario: Architecture and naming questions are both unresolved
- **WHEN** an architecture choice and a naming preference remain open
- **THEN** the workflow asks the architecture question first, provides concrete options with a recommendation, and defers or proposes the naming choice

#### Scenario: Repository evidence answers an open question
- **WHEN** the requested information can be determined from existing code, documentation, history, or referenced artifacts
- **THEN** the workflow retrieves the evidence and does not ask the user to supply it

### Requirement: Plan reviews lead with decisions
User-facing plan and proposal reviews SHALL present the outcome, chosen approach, riskiest assumption, tweakable decisions, alternatives, and known unknowns before compressed mechanical work.
Internal execution ordering MAY remain dependency-first.

#### Scenario: Plan contains expensive-to-change interface decisions
- **WHEN** a plan introduces an API shape, data model, type interface, or user-visible behavior
- **THEN** the review surfaces that decision, one considered alternative, and the cost of changing it later before listing implementation tasks

#### Scenario: Unknown has a safe default
- **WHEN** ambiguity remains but does not block implementation
- **THEN** the review states the default response and the observable signal that would trigger a pivot

### Requirement: Implementation deviations update canonical artifacts
Implementation workflows SHALL distinguish reversible deviations from behavior-changing, irreversible, or scope-expanding decisions.
Reversible deviations MUST update affected canonical design, specification, or task artifacts with rationale and validation evidence.
Behavior-changing, irreversible, or scope-expanding deviations MUST stop at a safe checkpoint for user direction.

#### Scenario: Planned file path is obsolete but behavior is unchanged
- **WHEN** implementation discovers an obsolete path and an existing equivalent path preserves the intended behavior
- **THEN** the workflow records the reversible deviation, updates affected tasks, validates the equivalent path, and continues

#### Scenario: Implementation requires new user-visible behavior
- **WHEN** a pending task can only proceed by expanding or changing intended behavior
- **THEN** the workflow updates no completion marker, stops at a safe checkpoint, and requests user approval before changing canonical artifacts or code

### Requirement: Feature completion reports implementation reality
`/do` completion reporting SHALL summarize recorded deviations, discovered edge cases, unresolved review questions, and the most consequential learning from its existing canonical state.
It MUST NOT create a redundant standalone implementation-notes file.

#### Scenario: Feature completed with plan amendments
- **WHEN** a `/do` run reaches completion after one or more recorded deviations or discoveries
- **THEN** the final report includes their counts, the highest-impact item, remaining review needs, and the canonical artifact locations

### Requirement: Complex PRs package reviewer context proportionally
`/pr` SHALL augment medium and complex PR descriptions with available demonstrations, the problem and chosen bet, expert-review questions, known deviations, and explicit non-goals.
It MUST retain the concise path for simple PRs and MUST NOT fabricate unavailable evidence.

#### Scenario: User-facing complex PR has demonstration evidence
- **WHEN** a complex PR changes user-facing behavior and screenshots or recordings are available
- **THEN** the PR description leads with that evidence and identifies the expert questions and deviations reviewers must examine

#### Scenario: Supporting evidence is unavailable
- **WHEN** a PR has no demonstration or implementation-deviation artifact
- **THEN** the description omits or marks that material unavailable instead of inventing it

#### Scenario: PR is simple
- **WHEN** a PR meets the existing simple-tier criteria
- **THEN** the workflow preserves its brief summary and does not add heavyweight pitch sections
