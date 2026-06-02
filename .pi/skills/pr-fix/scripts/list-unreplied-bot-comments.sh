#!/bin/bash
# List root bot PR review comments that have no threaded replies.
#
# Usage: list-unreplied-bot-comments.sh <pr-number> <owner/repo> [bot-pattern]

set -euo pipefail

PR_NUMBER="${1:?Usage: list-unreplied-bot-comments.sh <pr-number> <owner/repo> [bot-pattern]}"
REPO="${2:?Usage: list-unreplied-bot-comments.sh <pr-number> <owner/repo> [bot-pattern]}"
BOT_PATTERN="${3:-codex}"

gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate \
  | jq -s --arg bp "$BOT_PATTERN" '
      add as $all
      | [
          $all[]
          | select((.user.login // "") | test($bp; "i"))
          | select((.in_reply_to_id // null) == null)
          | select(.path != null) as $root
          | {
              comment_id: $root.id,
              author: $root.user.login,
              path: $root.path,
              line: ($root.line // $root.original_line),
              html_url: $root.html_url,
              commit_id: $root.commit_id,
              body_summary: (($root.body // "") | gsub("\n+"; " ") | .[0:500]),
              reply_count: ([$all[] | select(.in_reply_to_id == $root.id)] | length)
            }
        ]
      | map(select(.reply_count == 0))
    '
