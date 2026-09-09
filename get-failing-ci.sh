#!/usr/bin/env bash
# Checks CI status for the PR on the current branch.
#
# Exit codes:
#   0 — nothing failing (the message says whether checks are still running)
#   1 — at least one check failed; details and logs printed
#   2 — status could NOT be determined (no PR, auth problem, API error).
#       Never conflate this with success: an aborted check is not a green check.
#
# Uses the REST check-runs endpoint instead of `gh pr checks --json`, which only exists in
# gh >= 2.47 — the Ubuntu package ships 2.46. Pinning to the API keeps this script working
# regardless of the installed CLI version.
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
trap 'fail "unexpected error in get-failing-ci.sh (line $LINENO)"' ERR

command -v jq >/dev/null 2>&1 || fail "jq is required but not installed"

SHA=$(gh pr view --json headRefOid -q .headRefOid 2>/dev/null) \
  || fail "no open PR for the current branch, or gh is not authenticated"
[ -n "$SHA" ] || fail "could not resolve the PR head commit"

# --paginate: the endpoint returns 30 check runs per page by default.
RUNS=$(gh api --paginate -X GET "repos/{owner}/{repo}/commits/$SHA/check-runs" \
        -f per_page=100 \
        --jq '.check_runs[] | {name, conclusion, status, html_url}' 2>/dev/null) \
  || fail "could not fetch check runs for $SHA"

# "failure" and "timed_out" are real breakages. "cancelled" is usually a superseded run and
# "action_required" a manual gate, so neither is reported as a failure.
FAILING=$(printf '%s\n' "$RUNS" | jq -c 'select(.conclusion == "failure" or .conclusion == "timed_out")')
PENDING=$(printf '%s\n' "$RUNS" | jq -r 'select(.conclusion == null) | .name' | grep -c . || true)

if [ -z "$FAILING" ]; then
  if [ "$PENDING" -gt 0 ]; then
    echo "No failing checks, but $PENDING still running — this status is not final."
  else
    echo "All checks passed."
  fi
  exit 0
fi

echo "Failing checks:"
printf '%s\n' "$FAILING" | jq -r '"  - \(.name): \(.html_url)"'
[ "$PENDING" -gt 0 ] && echo "  ($PENDING check(s) still running)"
echo ""

while IFS=$'\t' read -r JOB_NAME LINK; do
  [ -n "$JOB_NAME" ] || continue
  echo "=== $JOB_NAME ==="
  # Only GitHub Actions check runs have a fetchable job log. Other providers (CodeRabbit,
  # external services) point html_url at their own UI, where a trailing number is not a
  # job id — scraping one would fetch an unrelated log.
  if [[ "$LINK" =~ /actions/runs/[0-9]+/job/([0-9]+) ]]; then
    JOB_ID="${BASH_REMATCH[1]}"
    # Extract the log, strip the job/step/timestamp prefix, then print from the
    # failure separator (────) through the summary line (Tests:/Duration:/errors found)
    gh run view --job "$JOB_ID" --log 2>&1 \
      | awk -F'\t' '/────|FAILED|ERROR|errors found/{found=1} found{print $3} /Tests:|Duration:|errors found/{if(found) exit}' \
      | sed -E 's/^[0-9T:.Z+-]+ //' \
      || echo "(could not extract relevant output)"
  else
    echo "(no Actions job log available — see $LINK)"
  fi
  echo ""
done <<< "$(printf '%s\n' "$FAILING" | jq -r '"\(.name)\t\(.html_url)"')"

exit 1
