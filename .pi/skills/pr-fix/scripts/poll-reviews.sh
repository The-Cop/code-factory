#!/bin/bash
# Background review poller — blocks until bot reviewers post new feedback.
# Run with run_in_background: true to avoid consuming tokens while waiting.
#
# Usage: poll-reviews.sh <pr-number> <owner/repo> <known-comment-count> <known-review-count> [bot-pattern] [poll-interval] [max-polls] [log-every]
#
# Parameters:
#   pr-number            PR number to watch
#   owner/repo           Repository in owner/repo format
#   known-comment-count  Root bot review comment count before triggering reviews (baseline)
#   known-review-count   Bot non-COMMENTED review count before triggering (baseline)
#   bot-pattern          Regex for bot login names (default: "bot|app|\[bot\]")
#   poll-interval        Seconds between polls (default: 30)
#   max-polls            Maximum poll attempts (default: 30, ~15 min at 30s)
#   log-every            Emit unchanged progress every N polls (default: 0, quiet)
#
# Exit states (printed to stdout):
#   REVIEWS_READY     New bot review comments detected and :eyes: cleared (JSON file path follows)
#   NO_NEW_REVIEWS    Timeout with no bot activity (reviewer may not be configured)
#   TIMEOUT           Max polls reached while :eyes: still active

set -euo pipefail

PR_NUMBER="${1:?Usage: poll-reviews.sh <pr-number> <owner/repo> <known-comment-count> <known-review-count> [bot-pattern] [poll-interval] [max-polls]}"
REPO="${2:?Usage: poll-reviews.sh <pr-number> <owner/repo> <known-comment-count> <known-review-count> [bot-pattern] [poll-interval] [max-polls]}"
KNOWN_COMMENT_COUNT="${3:?Usage: poll-reviews.sh <pr-number> <owner/repo> <known-comment-count> <known-review-count> [bot-pattern] [poll-interval] [max-polls]}"
KNOWN_REVIEW_COUNT="${4:?Usage: poll-reviews.sh <pr-number> <owner/repo> <known-comment-count> <known-review-count> [bot-pattern] [poll-interval] [max-polls]}"
BOT_PATTERN="${5:-bot|app|\\[bot\\]}"
POLL_INTERVAL="${6:-30}"
MAX_POLLS="${7:-30}"
LOG_EVERY="${8:-0}"

eyes_active=false

if ! [[ "$LOG_EVERY" =~ ^[0-9]+$ ]]; then
  LOG_EVERY=0
fi

should_log() {
  local poll="$1"
  [ "$LOG_EVERY" -gt 0 ] || return 1
  [ "$poll" -eq 1 ] || [ "$poll" -eq "$MAX_POLLS" ] || [ $((poll % LOG_EVERY)) -eq 0 ]
}

write_json_file() {
  local kind="$1"
  local file="/tmp/pr-fix-reviews-${PR_NUMBER}-${kind}.json"
  cat > "$file"
  echo "$file"
}

bot_root_comments_json() {
  gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate 2>/dev/null \
    | jq -s --arg bp "$BOT_PATTERN" '
      add
      | [
          .[]
          | select((.user.login // "") | test($bp; "i"))
          | select((.in_reply_to_id // null) == null)
          | select(.path != null)
          | {
              comment_id: .id,
              author: .user.login,
              path,
              line: (.line // .original_line),
              body,
              html_url,
              commit_id,
              created_at
            }
        ]
      | sort_by(.created_at, .comment_id)
    ' 2>/dev/null
}

bot_submitted_reviews_json() {
  gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --paginate 2>/dev/null \
    | jq -s --arg bp "$BOT_PATTERN" '
      add
      | [
          .[]
          | select((.user.login // "") | test($bp; "i"))
          | select(.state != "COMMENTED")
          | {
              review_id: .id,
              author: .user.login,
              state,
              body,
              html_url,
              commit_id,
              submitted_at
            }
        ]
      | sort_by(.submitted_at, .review_id)
    ' 2>/dev/null
}

for i in $(seq 1 "$MAX_POLLS"); do
  # Check for :eyes: emoji in PR comments (signals reviewer is investigating)
  EYES_IN_COMMENTS=$(gh api "repos/$REPO/issues/$PR_NUMBER/comments" --paginate 2>/dev/null \
    | jq -r --arg bp "$BOT_PATTERN" '[.[] | select(.user.login | test($bp; "i")) | select(.body | test(":eyes:|👀"))] | length' 2>/dev/null) || EYES_IN_COMMENTS="0"

  # Check for :eyes: in PR body (some reviewers add it there too)
  EYES_IN_BODY=$(gh pr view "$PR_NUMBER" --repo "$REPO" --json body --jq '.body // "" | test(":eyes:|👀")' 2>/dev/null) || EYES_IN_BODY="false"

  if [ "$EYES_IN_COMMENTS" -gt 0 ] || [ "$EYES_IN_BODY" = "true" ]; then
    eyes_active=true
    if should_log "$i"; then
      echo "poll $i/$MAX_POLLS: reviewer investigating (:eyes: detected)"
    fi
    sleep "$POLL_INTERVAL"
    continue
  fi

  # :eyes: cleared (or was never present) — check for new comments/reviews
  if [ "$eyes_active" = true ]; then
    echo "poll $i/$MAX_POLLS: :eyes: cleared, checking for new feedback"
  fi

  # Count current actionable root comments from the selected bot reviewers.
  COMMENTS_JSON=$(bot_root_comments_json) || COMMENTS_JSON="[]"
  CURRENT_COMMENTS=$(echo "$COMMENTS_JSON" | jq 'length')

  if [ "$CURRENT_COMMENTS" -gt "$KNOWN_COMMENT_COUNT" ]; then
    NEW_COMMENTS=$(echo "$COMMENTS_JSON" | jq --argjson known "$KNOWN_COMMENT_COUNT" '.[$known:]')
    COMMENTS_FILE=$(echo "$NEW_COMMENTS" | write_json_file "comments")
    echo ""
    echo "REVIEWS_READY"
    echo "previous_comments=$KNOWN_COMMENT_COUNT current_comments=$CURRENT_COMMENTS"
    echo "NEW_COMMENTS_FILE: $COMMENTS_FILE"
    exit 0
  fi

  # Count current non-COMMENTED review submissions from the selected bot reviewers.
  REVIEWS_JSON=$(bot_submitted_reviews_json) || REVIEWS_JSON="[]"
  CURRENT_REVIEWS=$(echo "$REVIEWS_JSON" | jq 'length')

  if [ "$CURRENT_REVIEWS" -gt "$KNOWN_REVIEW_COUNT" ]; then
    NEW_REVIEWS=$(echo "$REVIEWS_JSON" | jq --argjson known "$KNOWN_REVIEW_COUNT" '.[$known:]')
    REVIEWS_FILE=$(echo "$NEW_REVIEWS" | write_json_file "reviews")
    echo ""
    echo "REVIEWS_READY"
    echo "previous_reviews=$KNOWN_REVIEW_COUNT current_reviews=$CURRENT_REVIEWS"
    echo "NEW_REVIEWS_FILE: $REVIEWS_FILE"
    exit 0
  fi

  # If :eyes: was seen and cleared but no new comments appeared, the reviewer
  # found nothing actionable — report as ready (clean review)
  if [ "$eyes_active" = true ]; then
    echo ""
    echo "REVIEWS_READY"
    echo "eyes_cleared=true new_comments=0 new_reviews=0"
    echo "Reviewer investigated and posted no actionable feedback."
    exit 0
  fi

  if should_log "$i"; then
    echo "poll $i/$MAX_POLLS: no new activity (bot_root_comments=$CURRENT_COMMENTS bot_reviews=$CURRENT_REVIEWS)"
  fi
  sleep "$POLL_INTERVAL"
done

echo ""
if [ "$eyes_active" = true ]; then
  echo "TIMEOUT"
  echo "Reviewer :eyes: was active but never completed within $((MAX_POLLS * POLL_INTERVAL / 60)) min"
else
  echo "NO_NEW_REVIEWS"
  echo "No bot activity detected after $((MAX_POLLS * POLL_INTERVAL / 60)) min — reviewer may not be configured"
fi
exit 1
