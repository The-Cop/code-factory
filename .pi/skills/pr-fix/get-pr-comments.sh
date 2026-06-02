#!/bin/bash

# Usage: ./get-pr-comments.sh [-v] [-a] [-f] [-o] [-p] [-r reviewer] [pr-number|pr-url|comment-url]
#
# Fetches PR review comment threads as structured JSON with resolution status.
# Uses GitHub GraphQL API with pagination for accurate thread data.
#
# Flags:
#   -v    Verbose mode - output diagnostic information to stderr
#   -a    Actionable only - filter to unresolved and not outdated threads
#   -f    Full mode - include diff_hunk fields (default: compact without diff_hunks)
#   -o    Oldest-first chronological order (default: newest first)
#   -p    Path-only large output - when output exceeds 25KB, print a small JSON pointer
#   -r    Reviewer filter - include only threads started by this reviewer login
#
# Input formats:
#   No argument       Auto-detect PR from current branch
#   PR number         e.g., 12345
#   PR URL            e.g., https://github.com/owner/repo/pull/123
#   Comment URL       e.g., https://github.com/owner/repo/pull/123#discussion_r456
#
# Output: JSON array of review threads. Each thread includes:
#   thread_id         GraphQL node ID (for resolveReviewThread mutation)
#   first_comment_id  REST API comment ID (for reply endpoint)
#   resolved          Thread resolution status
#   outdated          Whether code changed since comment was posted
#   path              File path relative to repo root
#   line              End line number in the diff
#   start_line        Start line for multi-line comments (null = single line)
#   comments[]        Array of comment objects with body, author, line, etc.
#
# Auto-fallback for large output:
#   When output exceeds 25KB, writes to /tmp/pr-comments-{owner}-{repo}-{pr}.json
#   and prints a message to stderr. With -p, stdout is a small JSON pointer.

SPECIFIC_COMMENT_ID=""
VERBOSE=0
ACTIONABLE_ONLY=0
FULL_MODE=0
OLDEST_FIRST=0
PATH_ONLY_ON_LARGE=0
REVIEWER=""

log_verbose() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "[get-pr-comments] $*" >&2
  fi
}

log_error() {
  echo "[get-pr-comments][ERROR] $*" >&2
}

# Parse flags
while getopts "vafopr:" opt; do
  case $opt in
    v) VERBOSE=1; log_verbose "Verbose mode enabled" ;;
    a) ACTIONABLE_ONLY=1; log_verbose "Actionable-only mode enabled" ;;
    f) FULL_MODE=1; log_verbose "Full mode enabled (including diff_hunks)" ;;
    o) OLDEST_FIRST=1; log_verbose "Oldest-first mode enabled" ;;
    p) PATH_ONLY_ON_LARGE=1; log_verbose "Path-only mode enabled for large output" ;;
    r) REVIEWER="$OPTARG"; log_verbose "Reviewer filter: $REVIEWER" ;;
    \?) log_error "Invalid option: -$OPTARG"; exit 1 ;;
  esac
done
shift $((OPTIND-1))

# Validate prerequisites
if ! command -v gh &> /dev/null; then
  log_error "GitHub CLI (gh) is not installed. Install from: https://cli.github.com/"
  echo "[]"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  log_error "jq is not installed. Install from: https://stedolan.github.io/jq/"
  echo "[]"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  log_error "GitHub CLI is not authenticated. Run: gh auth login"
  echo "[]"
  exit 1
fi

log_verbose "Prerequisites validated"

# Parse input to determine PR number and repo
OWNER=""
REPO_NAME=""

if [ -z "$1" ]; then
  log_verbose "No argument provided, detecting PR from current branch"

  if ! git rev-parse --is-inside-work-tree &> /dev/null; then
    log_error "Not in a git repository. Provide a PR number or URL."
    echo "[]"
    exit 0
  fi

  CURRENT_BRANCH=$(git branch --show-current)
  log_verbose "Current branch: $CURRENT_BRANCH"

  if ! PR_INFO=$(gh pr view --json number,url 2>&1); then
    log_error "No PR found for branch '$CURRENT_BRANCH'. Provide a PR number or URL."
    echo "[]"
    exit 0
  fi
  PR_NUMBER=$(echo "$PR_INFO" | jq -r '.number')
  REPO=$(echo "$PR_INFO" | jq -r '.url' | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/.*|\1|')
  log_verbose "Detected PR #$PR_NUMBER in $REPO"
elif [[ "$1" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+)#discussion_r([0-9]+)$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO_NAME="${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
  SPECIFIC_COMMENT_ID="${BASH_REMATCH[4]}"
  REPO="${OWNER}/${REPO_NAME}"
  log_verbose "Comment URL: PR #$PR_NUMBER, comment #$SPECIFIC_COMMENT_ID in $REPO"
elif [[ "$1" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO_NAME="${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
  REPO="${OWNER}/${REPO_NAME}"
  log_verbose "PR URL: PR #$PR_NUMBER in $REPO"
else
  PR_NUMBER="$1"
  log_verbose "PR number: #$PR_NUMBER"

  if ! REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1); then
    log_error "Failed to determine repository. Provide a full PR URL."
    echo "[]"
    exit 0
  fi
  log_verbose "Repository: $REPO"
fi

# Extract owner/repo if not already set from URL
if [ -z "$OWNER" ]; then
  OWNER=$(echo "$REPO" | cut -d'/' -f1)
  REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
fi

log_verbose "Fetching review threads for PR #$PR_NUMBER in $OWNER/$REPO_NAME"

# Verify PR exists
if ! gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO_NAME" --json number &> /dev/null; then
  log_error "Cannot access PR #$PR_NUMBER in $OWNER/$REPO_NAME"
  echo "[]"
  exit 0
fi

log_verbose "PR accessible, querying review threads via GraphQL"

# Fetch review threads with pagination
# Key difference from get-pr-feedback: includes thread-level `id` for resolveReviewThread mutation
# shellcheck disable=SC2016 # jq program and GraphQL cursor use literal $ names.
if ! COMMENTS_JSON=$(gh api graphql --paginate -f query="
query(\$cursor: String) {
  repository(owner: \"${OWNER}\", name: \"${REPO_NAME}\") {
    pullRequest(number: ${PR_NUMBER}) {
      reviewThreads(first: 100, after: \$cursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          comments(first: 50) {
            nodes {
              id
              databaseId
              author { login }
              body
              path
              line
              originalLine
              startLine
              originalStartLine
              diffHunk
              outdated
              createdAt
              updatedAt
              commit { oid }
              replyTo { databaseId }
              url
            }
          }
        }
      }
    }
  }
}" --jq '
  .data.repository.pullRequest.reviewThreads.nodes[] as $thread |
  {
    thread_id: $thread.id,
    first_comment_id: ($thread.comments.nodes[0].databaseId // 0),
    resolved: $thread.isResolved,
    outdated: $thread.isOutdated,
    path: $thread.path,
    line: $thread.line,
    start_line: $thread.startLine,
    comments: [
      $thread.comments.nodes[] | {
        comment_id: .databaseId,
        author: .author.login,
        body: .body,
        path: .path,
        line: .line,
        original_line: .originalLine,
        start_line: .startLine,
        original_start_line: .originalStartLine,
        diff_hunk: .diffHunk,
        outdated: .outdated,
        created_at: .createdAt,
        updated_at: .updatedAt,
        commit_id: .commit.oid,
        in_reply_to_id: .replyTo.databaseId,
        html_url: .url
      }
    ]
  }
' 2>&1); then
  log_error "GraphQL query failed: $COMMENTS_JSON"
  echo "[]"
  exit 1
fi

# Combine paginated results into array
THREADS_JSON=$(echo "$COMMENTS_JSON" | jq -s '.')

TOTAL_THREADS=$(echo "$THREADS_JSON" | jq 'length')
TOTAL_COMMENTS=$(echo "$THREADS_JSON" | jq '[.[].comments | length] | add // 0')
log_verbose "Retrieved $TOTAL_THREADS threads with $TOTAL_COMMENTS comments"

# Filter by specific comment ID if provided
if [ -n "$SPECIFIC_COMMENT_ID" ]; then
  log_verbose "Filtering to thread containing comment #$SPECIFIC_COMMENT_ID"
  THREADS_JSON=$(echo "$THREADS_JSON" | jq --arg cid "$SPECIFIC_COMMENT_ID" \
    'map(select(.comments[] | .comment_id == ($cid | tonumber)))')
  FILTERED=$(echo "$THREADS_JSON" | jq 'length')
  log_verbose "Matched $FILTERED threads"
  if [ "$FILTERED" -eq 0 ]; then
    log_error "Comment #$SPECIFIC_COMMENT_ID not found in PR #$PR_NUMBER"
  fi
fi

# Filter by reviewer if requested. Thread authorship follows the first review comment.
if [ -n "$REVIEWER" ]; then
  THREADS_JSON=$(echo "$THREADS_JSON" | jq --arg reviewer "$REVIEWER" \
    '[.[] | select((.comments[0].author // "") == $reviewer)]')
  REVIEWER_THREADS=$(echo "$THREADS_JSON" | jq 'length')
  log_verbose "Filtered to $REVIEWER_THREADS threads from reviewer $REVIEWER"
fi

# Sort threads
if [ "$OLDEST_FIRST" -eq 1 ]; then
  THREADS_JSON=$(echo "$THREADS_JSON" | jq 'sort_by(.comments[0].created_at)')
else
  THREADS_JSON=$(echo "$THREADS_JSON" | jq 'sort_by(.comments[0].created_at) | reverse')
fi

# Filter to actionable threads (unresolved + not outdated)
if [ "$ACTIONABLE_ONLY" -eq 1 ]; then
  THREADS_JSON=$(echo "$THREADS_JSON" | jq '[.[] | select(.resolved == false and .outdated == false)]')
  ACTIONABLE=$(echo "$THREADS_JSON" | jq 'length')
  log_verbose "Filtered to $ACTIONABLE actionable threads"
fi

# Remove diff_hunk fields in compact mode (default)
if [ "$FULL_MODE" -eq 0 ]; then
  THREADS_JSON=$(echo "$THREADS_JSON" | jq '[.[] | .comments = [.comments[] | del(.diff_hunk)]]')
fi

# Handle large output — auto-write to temp file when >25KB
OUTPUT_SIZE=$(echo "$THREADS_JSON" | wc -c | tr -d ' ')
OUTPUT_THREADS=$(echo "$THREADS_JSON" | jq 'length')
OUTPUT_COMMENTS=$(echo "$THREADS_JSON" | jq '[.[].comments | length] | add // 0')

if [ "$OUTPUT_SIZE" -gt 25000 ]; then
  TEMP_FILE="/tmp/pr-comments-${OWNER}-${REPO_NAME}-${PR_NUMBER}.json"
  echo "$THREADS_JSON" > "$TEMP_FILE"
  log_verbose "Output $OUTPUT_SIZE bytes exceeds 25KB, wrote to: $TEMP_FILE"
  echo "[get-pr-comments] Large output detected — wrote to temp file for Claude to read: $TEMP_FILE" >&2
  if [ "$PATH_ONLY_ON_LARGE" -eq 1 ]; then
    jq -n \
      --arg output_file "$TEMP_FILE" \
      --argjson bytes "$OUTPUT_SIZE" \
      --argjson threads "$OUTPUT_THREADS" \
      --argjson comments "$OUTPUT_COMMENTS" \
      '{output_file: $output_file, bytes: $bytes, thread_count: $threads, comment_count: $comments}'
    exit 0
  fi
fi

echo "$THREADS_JSON"
