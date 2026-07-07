#!/bin/bash
# Retry a DDCI GitLab job by job id.
#
# Usage:
#   retry_ddci_job.sh [--project owner/repo] [--host https://gitlab.ddbuild.io] [--dry-run] <job-id-or-url>
#
# Accepts a bare GitLab job id, a GitLab job URL, or a Mosaic URL containing
# taskExecutionId=<job-id>.

set -euo pipefail

PROJECT=""
HOST="${GITLAB_HOST:-https://gitlab.ddbuild.io}"
DRY_RUN=0

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --project)
      PROJECT="${2:?--project requires owner/repo}"
      shift 2
      ;;
    --host)
      HOST="${2:?--host requires a URL}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

INPUT="${1:-}"
if [ -z "$INPUT" ]; then
  usage >&2
  exit 2
fi

if [[ "$INPUT" =~ taskExecutionId=([0-9]+) ]]; then
  JOB_ID="${BASH_REMATCH[1]}"
elif [[ "$INPUT" =~ /jobs/([0-9]+) ]]; then
  JOB_ID="${BASH_REMATCH[1]}"
elif [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  JOB_ID="$INPUT"
else
  echo "Could not parse a GitLab job id from: $INPUT" >&2
  exit 2
fi

if [ -z "$PROJECT" ]; then
  PROJECT="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)"
fi
if [ -z "$PROJECT" ]; then
  PROJECT="ddoghq/dd-source"
fi

PROJECT_ENCODED="${PROJECT//\//%2F}"
HOST="${HOST%/}"
URL="$HOST/api/v4/projects/$PROJECT_ENCODED/jobs/$JOB_ID/retry"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "DRY_RUN"
  echo "project=$PROJECT"
  echo "job_id=$JOB_ID"
  echo "url=$URL"
  exit 0
fi

TOKEN=""
if command -v ddtool >/dev/null 2>&1; then
  TOKEN="$(ddtool auth gitlab token 2>/dev/null | tr -d '\n' || true)"
fi
if [ -z "$TOKEN" ] && [ -n "${GITLAB_TOKEN:-}" ]; then
  TOKEN="$GITLAB_TOKEN"
fi
if [ -z "$TOKEN" ]; then
  echo "No GitLab token available. Run 'ddtool auth gitlab token' or set GITLAB_TOKEN." >&2
  exit 1
fi

BODY="$(mktemp)"
cleanup() {
  rm -f "$BODY"
}
trap cleanup EXIT

HTTP_CODE="$(
  curl -sS -o "$BODY" -w '%{http_code}' \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    "$URL"
)"

case "$HTTP_CODE" in
  2*)
    if jq empty "$BODY" >/dev/null 2>&1; then
      jq -r '
        "RETRIED_DDCI_JOB",
        "old_job_id='"$JOB_ID"'",
        "new_job_id=\(.id)",
        "status=\(.status)",
        "web_url=\(.web_url)"
      ' "$BODY"
    else
      echo "RETRIED_DDCI_JOB"
      echo "old_job_id=$JOB_ID"
      cat "$BODY"
    fi
    ;;
  *)
    echo "Failed to retry GitLab job $JOB_ID (HTTP $HTTP_CODE)" >&2
    if [ -s "$BODY" ]; then
      cat "$BODY" >&2
      echo >&2
    fi
    exit 1
    ;;
esac
