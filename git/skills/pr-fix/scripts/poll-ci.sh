#!/bin/bash
# Background CI poller — blocks until an actionable state change occurs.
# Run with run_in_background: true to avoid consuming tokens while waiting.
#
# Usage: poll-ci.sh <pr-number> [poll-interval] [max-polls]
#
# Exit states (printed to stdout):
#   ALL_PASSING         All non-gated checks passed and PR is mergeable
#   FAILURES_DETECTED   At least one non-gated check failed (full status JSON follows)
#   CONFLICTS_DETECTED  All checks passed but PR has merge conflicts
#   TIMEOUT             Max polls reached without resolution
#
# Approval-gated checks (require human action, excluded from wait/fail logic):
#   merge gate, peer review, manual approval, codeowner, devflow/mergegate

set -euo pipefail

PR_NUMBER="${1:?Usage: poll-ci.sh <pr-number> [poll-interval] [max-polls]}"
POLL_INTERVAL="${2:-30}"
MAX_POLLS="${3:-40}"

# Case-insensitive patterns for checks that require human approval.
# These are excluded from pending/failure counts — they never auto-complete.
GATED_PATTERN="merge.gate|peer.review|manual.approval|codeowner|devflow/mergegate"

filter_gated() {
  jq --arg pattern "$GATED_PATTERN" '[.[] | select((.name | ascii_downcase | test($pattern)) | not)]'
}

for i in $(seq 1 "$MAX_POLLS"); do
  # gh pr checks exits 8 when checks are pending — capture output regardless
  STATUS=$(gh pr checks "$PR_NUMBER" --json name,state,bucket,link 2>&1) || true

  if ! echo "$STATUS" | jq empty 2>/dev/null; then
    echo "ERROR: gh pr checks returned invalid JSON"
    echo "$STATUS"
    exit 1
  fi

  # Filter out approval-gated checks before counting
  FILTERED=$(echo "$STATUS" | filter_gated)

  FAILED=$(echo "$FILTERED" | jq '[.[] | select(.state == "FAILURE")] | length')
  PENDING=$(echo "$FILTERED" | jq '[.[] | select(.state == "PENDING" or .state == "IN_PROGRESS" or .state == "QUEUED")] | length')
  TOTAL=$(echo "$FILTERED" | jq 'length')
  PASSED=$((TOTAL - FAILED - PENDING))

  echo "poll $i/$MAX_POLLS: passed=$PASSED pending=$PENDING failed=$FAILED total=$TOTAL"

  if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "FAILURES_DETECTED"
    echo "failed=$FAILED pending=$PENDING passed=$PASSED total=$TOTAL"
    echo ""
    echo "Failed checks:"
    echo "$FILTERED" | jq -r '.[] | select(.state == "FAILURE") | "  \(.name) — \(.link)"'
    echo ""
    echo "FULL_STATUS:"
    echo "$FILTERED"
    exit 0
  fi

  if [ "$PENDING" -eq 0 ] && [ "$TOTAL" -gt 0 ]; then
    # All non-gated checks passed — verify PR is still mergeable before declaring green
    MERGEABLE=$(gh pr view "$PR_NUMBER" --json mergeable --jq '.mergeable' 2>/dev/null || echo "UNKNOWN")
    if [ "$MERGEABLE" = "CONFLICTING" ]; then
      echo ""
      echo "CONFLICTS_DETECTED"
      echo "passed=$PASSED total=$TOTAL mergeable=$MERGEABLE"
      exit 0
    fi
    echo ""
    echo "ALL_PASSING"
    echo "passed=$PASSED total=$TOTAL mergeable=$MERGEABLE"
    exit 0
  fi

  sleep "$POLL_INTERVAL"
done

echo ""
echo "TIMEOUT"
echo "Polled $MAX_POLLS times at ${POLL_INTERVAL}s intervals ($((MAX_POLLS * POLL_INTERVAL / 60)) min)"
exit 1
