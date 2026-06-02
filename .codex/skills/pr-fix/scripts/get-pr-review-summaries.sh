#!/bin/bash
# Fetch compact non-empty PR review bodies.
#
# Usage: get-pr-review-summaries.sh [-p] [-r reviewer] [pr-number|pr-url]
#   -p            If output exceeds 25KB, print {"output_file": "..."}.
#   -r reviewer  Restrict to one reviewer login.

set -euo pipefail

PATH_ONLY_ON_LARGE=0
REVIEWER=""

usage() {
  echo "Usage: $0 [-p] [-r reviewer] [pr-number|pr-url]" >&2
}

log_error() {
  echo "[get-pr-review-summaries][ERROR] $*" >&2
}

while getopts "pr:" opt; do
  case "$opt" in
    p) PATH_ONLY_ON_LARGE=1 ;;
    r) REVIEWER="$OPTARG" ;;
    *) usage; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if ! command -v gh >/dev/null 2>&1; then
  log_error "GitHub CLI (gh) is not installed."
  echo "[]"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log_error "jq is not installed."
  echo "[]"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  log_error "GitHub CLI is not authenticated. Run: gh auth login"
  echo "[]"
  exit 1
fi

ARG="${1:-}"
OWNER=""
REPO_NAME=""

if [ -z "$ARG" ]; then
  if ! PR_INFO=$(gh pr view --json number,url 2>/dev/null); then
    log_error "No PR found for current branch. Provide a PR number or URL."
    echo "[]"
    exit 0
  fi
  PR_NUMBER=$(echo "$PR_INFO" | jq -r '.number')
  REPO=$(echo "$PR_INFO" | jq -r '.url' | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/.*|\1|')
elif [[ "$ARG" =~ ^https://github.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPO_NAME="${BASH_REMATCH[2]}"
  PR_NUMBER="${BASH_REMATCH[3]}"
  REPO="${OWNER}/${REPO_NAME}"
else
  PR_NUMBER="$ARG"
  if ! REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null); then
    log_error "Failed to determine repository. Provide a full PR URL."
    echo "[]"
    exit 0
  fi
fi

if [ -z "$OWNER" ]; then
  OWNER=$(echo "$REPO" | cut -d'/' -f1)
  REPO_NAME=$(echo "$REPO" | cut -d'/' -f2)
fi

if ! REVIEWS=$(gh api "repos/${OWNER}/${REPO_NAME}/pulls/${PR_NUMBER}/reviews" --paginate 2>/dev/null \
  | jq -s --arg reviewer "$REVIEWER" '
    add
    | [
        .[]
        | select((.body // "") | length > 0)
        | select($reviewer == "" or .user.login == $reviewer)
        | {
            review_id: .id,
            author: .user.login,
            state,
            body,
            submitted_at,
            html_url,
            commit_id
          }
      ]
    | sort_by(.submitted_at, .review_id)
    | reverse
  '); then
  log_error "Failed to fetch PR reviews for ${OWNER}/${REPO_NAME}#${PR_NUMBER}."
  echo "[]"
  exit 1
fi

BYTES=$(printf '%s' "$REVIEWS" | wc -c | tr -d ' ')
if [ "$BYTES" -gt 25600 ]; then
  OUT="/tmp/pr-review-summaries-${OWNER}-${REPO_NAME}-${PR_NUMBER}.json"
  printf '%s\n' "$REVIEWS" > "$OUT"
  if [ "$PATH_ONLY_ON_LARGE" -eq 1 ]; then
    jq -n --arg output_file "$OUT" --argjson bytes "$BYTES" '{output_file: $output_file, bytes: $bytes}'
  else
    echo "Large output written to $OUT" >&2
    printf '%s\n' "$REVIEWS"
  fi
else
  printf '%s\n' "$REVIEWS"
fi
