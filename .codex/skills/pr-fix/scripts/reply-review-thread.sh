#!/bin/bash
# Reply to a PR review thread and optionally resolve it.
#
# Usage:
#   reply-review-thread.sh --thread-id ID --first-comment-id ID --repo owner/repo --pr N \
#     --path path --line line --url html_url --author login [--no-resolve] < body.txt
#
# Output: compact JSON with reply_tier and resolved state.

set -euo pipefail

THREAD_ID=""
FIRST_COMMENT_ID=""
REPO=""
PR_NUMBER=""
COMMENT_PATH=""
COMMENT_LINE=""
COMMENT_URL=""
COMMENT_AUTHOR=""
RESOLVE=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --thread-id) THREAD_ID="${2:-}"; shift 2 ;;
    --first-comment-id) FIRST_COMMENT_ID="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --pr) PR_NUMBER="${2:-}"; shift 2 ;;
    --path) COMMENT_PATH="${2:-}"; shift 2 ;;
    --line) COMMENT_LINE="${2:-}"; shift 2 ;;
    --url) COMMENT_URL="${2:-}"; shift 2 ;;
    --author) COMMENT_AUTHOR="${2:-}"; shift 2 ;;
    --no-resolve) RESOLVE=0; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BODY=$(cat)
if [ -z "$BODY" ]; then
  echo "reply body is empty" >&2
  exit 2
fi

reply_tier=""
reply_error=""

if [ -n "$THREAD_ID" ]; then
  # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not the shell.
  if reply_error=$(gh api graphql \
    -f query='mutation($thread: ID!, $body: String!) { addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $thread, body: $body }) { comment { id } } }' \
    -f thread="$THREAD_ID" \
    -f body="$BODY" 2>&1 >/dev/null); then
    reply_tier="graphql"
  fi
fi

if [ -z "$reply_tier" ] && [ -n "$REPO" ] && [ -n "$PR_NUMBER" ] && [ -n "$FIRST_COMMENT_ID" ] && [ "$FIRST_COMMENT_ID" != "0" ] && [ "$FIRST_COMMENT_ID" != "null" ]; then
  if reply_error=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments/$FIRST_COMMENT_ID/replies" \
    -X POST -f body="$BODY" 2>&1 >/dev/null); then
    reply_tier="rest"
  fi
fi

if [ -z "$reply_tier" ] && [ -n "$REPO" ] && [ -n "$PR_NUMBER" ]; then
  fallback_body=$(printf 'Re: [%s:%s](%s) (@%s)\n\n%s' "$COMMENT_PATH" "$COMMENT_LINE" "$COMMENT_URL" "$COMMENT_AUTHOR" "$BODY")
  if reply_error=$(gh pr comment "$PR_NUMBER" --repo "$REPO" --body "$fallback_body" 2>&1 >/dev/null); then
    reply_tier="pr_comment"
  fi
fi

if [ -z "$reply_tier" ]; then
  jq -n --arg error "$reply_error" '{reply_tier: null, resolved: false, error: $error}'
  exit 1
fi

resolved=false
resolve_error=""
if [ "$RESOLVE" -eq 1 ] && [ -n "$THREAD_ID" ]; then
  # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not the shell.
  if resolve_error=$(gh api graphql \
    -f query='mutation($thread: ID!) { resolveReviewThread(input: { threadId: $thread }) { thread { id isResolved } } }' \
    -f thread="$THREAD_ID" 2>&1 >/dev/null); then
    resolved=true
  fi
fi

jq -n \
  --arg reply_tier "$reply_tier" \
  --argjson resolved "$resolved" \
  --arg resolve_error "$resolve_error" \
  '{reply_tier: $reply_tier, resolved: $resolved, resolve_error: $resolve_error}'
