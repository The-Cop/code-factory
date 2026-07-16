## ADDED Requirements

### Requirement: Change quiz resolves a review target safely
`/change-quiz` SHALL accept a PR number or URL, a branch or ref, or the current branch as its review target.
It MUST resolve an appropriate base and gather commits and diffs without modifying local Git state, remote state, or pull-request state.

#### Scenario: User provides a pull request
- **WHEN** a user invokes the skill with a PR number or URL
- **THEN** the skill reads the PR metadata, base, commits, and diff without checking out the branch or changing the PR

#### Scenario: User provides no target
- **WHEN** a user invokes the skill in a Git repository without a PR or branch argument
- **THEN** the skill compares the current branch with its resolved base and reports the selected range before analysis

#### Scenario: No meaningful change exists
- **WHEN** the resolved target contains no commits or diff relative to its base
- **THEN** the skill reports that there is nothing to quiz and stops without asking questions

### Requirement: Change report teaches behavioral impact
Before asking quiz questions, the skill SHALL report context, changes grouped by intent, interactions with existing code paths, blast radius, and the key mental-model updates a maintainer needs.
The report MUST prioritize behavior, deviations, failure modes, and interaction effects over filenames or commit trivia.

#### Scenario: Diff changes behavior across unchanged callers
- **WHEN** a changed component alters behavior observed by callers whose files are not in the diff
- **THEN** the report explains those interactions and includes them in the blast-radius analysis

#### Scenario: Diff is large but mechanically repetitive
- **WHEN** many changed lines implement one repeated mechanical transformation
- **THEN** the report groups them by intent and spends attention on the behavioral exceptions rather than narrating every file

### Requirement: Quiz tests recall and prediction
The skill SHALL create five to eight questions that mix factual recall with behavioral prediction.
It MUST classify questions as critical or non-critical before asking them and MUST ask exactly one question per turn.

#### Scenario: Change introduces a failure-mode deviation
- **WHEN** the analyzed change alters an error path, fallback, retry, migration, or edge-case behavior
- **THEN** at least one critical question asks the user to predict the resulting behavior under that condition

#### Scenario: User answers a question
- **WHEN** the user submits an answer
- **THEN** the skill grades that answer before presenting the next question and updates the running score without revealing future answers

### Requirement: Grading is honest and merge readiness is advisory
The skill SHALL require every critical answer to be correct and at least 80 percent overall accuracy for a passing result.
For every miss, it MUST explain the correct model and identify whether the miss indicates a user-understanding gap or unnecessary implementation complexity.
The result MUST remain advisory and MUST NOT perform or authorize a merge.

#### Scenario: User misses a critical question
- **WHEN** the user reaches at least 80 percent overall accuracy but answers any critical question incorrectly
- **THEN** the result is not merge-ready and the report identifies the critical model gap

#### Scenario: User passes all criteria
- **WHEN** every critical answer is correct and overall accuracy is at least 80 percent
- **THEN** the skill reports an advisory merge-ready result with the final score and mental-model summary

### Requirement: Repeated failure changes the recommendation
The skill SHALL allow one fresh retry quiz after a failed round.
After two failed rounds, it MUST recommend a guided tour, simplification, or change split instead of continuing to generate quizzes.

#### Scenario: First quiz round fails
- **WHEN** the user does not meet the pass criteria on the first round
- **THEN** the skill points to the relevant report sections, explains the gaps, and offers one new question set covering the same concepts

#### Scenario: Second quiz round fails
- **WHEN** the user does not meet the pass criteria on the retry round
- **THEN** the skill stops quizzing and recommends `/tour`, simplifying the difficult behavior, or splitting the change

### Requirement: Change quiz remains read-only under pressure
The skill MUST NOT edit code, stage or commit files, push branches, create or update PRs, resolve review threads, approve reviews, mark drafts ready, or merge changes.
Requests for those actions MUST be routed to the appropriate existing skill after the quiz concludes or is explicitly abandoned.

#### Scenario: User asks to fix a discovered issue during the quiz
- **WHEN** quiz analysis reveals a defect and the user asks for an immediate fix
- **THEN** the skill records the finding, ends or pauses the quiz, and routes implementation to the appropriate workflow without editing code itself

#### Scenario: User asks the skill to merge after passing
- **WHEN** the user passes and asks `/change-quiz` to merge the change
- **THEN** the skill explains that its result is advisory and routes the request to the repository's merge or PR workflow

### Requirement: Skill discovery distinguishes adjacent workflows
The skill description SHALL trigger for change comprehension, change explanation, pre-merge quizzes, and requests to verify maintainer understanding.
It MUST exclude ordinary code review, PR creation, review-comment fixes, code tours, and implementation requests unless the user explicitly requests a quiz.

#### Scenario: User asks for a standard PR review
- **WHEN** a user requests correctness or quality findings without asking for comprehension testing
- **THEN** `/change-quiz` does not trigger and the request remains owned by `/review`

#### Scenario: User asks what changed and requests a quiz
- **WHEN** a user asks for a behavioral explanation followed by questions before merging
- **THEN** `/change-quiz` triggers and owns the report-and-quiz interaction

### Requirement: Missing context produces a bounded failure
The skill SHALL report the missing prerequisite and stop safely when it cannot resolve a repository, base, target, or readable diff.

#### Scenario: Invocation occurs outside a Git repository
- **WHEN** the skill cannot identify a Git repository for the requested target
- **THEN** it reports the prerequisite and does not fabricate a change report or quiz

#### Scenario: Remote PR metadata is unavailable
- **WHEN** a PR target requires remote metadata that cannot be retrieved
- **THEN** the skill reports the retrieval failure and offers local branch analysis only when a valid local range can be resolved
