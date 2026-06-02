# GraphQL Mutations for PR Review Threads

Reference for the `pr-fix` skill. Contains GraphQL mutations for resolving and replying to threads.

**Fetching threads** is handled by `get-pr-comments.sh` (see Step 2 in SKILL.md). The script returns structured JSON with `thread_id` (GraphQL node ID) and `first_comment_id` (REST API ID) ready for the mutations below.

## Resolve a Thread

Marks a review thread as resolved. Requires the GraphQL node `id` from the fetch query.

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {
    threadId: "{threadId}"
  }) {
    thread {
      id
      isResolved
    }
  }
}
'
```

Replace `{threadId}` with the `thread_id` field from the script output.

**Permissions required:** Repository Contents: Read and Write.

## Unresolve a Thread

Reverses a thread resolution (rarely needed, included for completeness).

```bash
gh api graphql -f query='
mutation {
  unresolveReviewThread(input: {
    threadId: "{threadId}"
  }) {
    thread {
      id
      isResolved
    }
  }
}
'
```

## Reply to a Review Thread (Tier 1 — GraphQL, preferred)

Uses the GraphQL `addPullRequestReviewThreadReply` mutation.
This is the preferred method because it can resolve the thread after replying,
while REST can only add a comment reply.

```bash
gh api graphql -f query='
mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: "{threadId}"
    body: "{response text}"
  }) {
    comment {
      id
      body
    }
  }
}
'
```

Replace:
- `{threadId}` — the `thread_id` field from the script output (same ID used for resolve/unresolve)
- `{response text}` — the reply body (supports GitHub-flavored markdown). **Escape double quotes** and newlines in the body since it's embedded in a GraphQL string.

For multi-line bodies, use a HEREDOC to build the query:

```bash
BODY='Line 1
Line 2 with "quotes"'
ESCAPED_BODY=$(echo "$BODY" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
gh api graphql -f query="
mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: \"${THREAD_ID}\"
    body: \"${ESCAPED_BODY}\"
  }) {
    comment { id }
  }
}
"
```

## Reply to a Review Comment (Tier 2 — REST fallback)

Falls back to the REST API when the GraphQL mutation fails (e.g., thread already resolved before reply,
or `thread_id` is missing). Requires `first_comment_id` from the script output.

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments/{databaseId}/replies \
  -X POST \
  -f body='{response text}'
```

Replace:
- `{owner}/{repo}` — the repository (e.g., `DataDog/dd-source`)
- `{number}` — the PR number
- `{databaseId}` — the `first_comment_id` from the script output
- `{response text}` — the reply body (supports GitHub-flavored markdown)

## Reply via PR Comment (Tier 3 — last resort)

When both Tier 1 and Tier 2 fail, post a top-level PR comment referencing the original thread.
This is not threaded but provides traceability.

```bash
gh pr comment {number} --body "$(cat <<'EOF'
Re: [{path}:{line}]({html_url}) (@{author})

{response text}
EOF
)"
```

Replace:
- `{number}` — the PR number
- `{path}` — file path from the thread
- `{line}` — line number from the thread
- `{html_url}` — `comments[0].html_url` (direct link to the original review comment)
- `{author}` — `comments[0].author` (mentions the reviewer for notification)
- `{response text}` — the reply body (same content as would have been posted as a threaded reply)

## Request Re-Review

After all threads are addressed, request re-review from specific reviewers:

```bash
gh pr edit {number} --add-reviewer {reviewer1},{reviewer2}
```

## Batch Processing Pattern

For PRs with many threads, process in batches to avoid API rate limits:

1. Fetch all threads in one GraphQL call (up to 100 threads, 50 comments each).
2. Apply all code changes locally (no API calls).
3. Reply to threads in sequence (REST API, one call per thread).
4. Resolve threads in sequence (GraphQL mutation, one call per thread).
5. Commit and push once.

This minimizes API calls: 1 fetch + N replies + N resolves + 1 push.
