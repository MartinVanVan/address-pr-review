#!/usr/bin/env bash
# Fetches unresolved inline review threads for the PR on the current branch.
#
# Selection rules:
#   - resolved threads are always skipped
#   - threads you (the authenticated GitHub user) already commented in are skipped,
#     because your reply is your decision
#   - UNLESS you reacted 👀 (EYES) to a comment in that thread: that re-opens it for
#     another look and overrides the skip
#
# Only YOUR 👀 counts. Bots (CodeRabbit and friends) use 👀 as an "I'm looking at this"
# acknowledgement, and counting theirs would drag threads back in at random.
#
# Pass --include-mine to get every unresolved thread regardless of the above.
#
# Connection sizes are deliberate: GitHub statically evaluates the query's node budget as
# threads x comments x reactions and rejects anything over 500,000. 100 x 50 x 20 = 100,000.
# Raising any of the three can push the query over the cap, at which point it fails on
# EVERY pull request, not just large ones.
#
# Each thread gains two computed fields:
#   repliedByViewer — you have commented in it
#   flaggedByEyes   — you reacted 👀 to it and want it re-checked
set -euo pipefail

INCLUDE_MINE="${1:-}"

OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)
PR=$(gh pr view --json number -q .number)

QUERY='query($owner: String!, $repo: String!, $pr: Int!) {
  viewer { login }
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
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
              author { login }
              body
              url
              reactions(first: 20, content: EYES) {
                nodes { user { login } }
              }
            }
          }
        }
      }
    }
  }
}'

if [ "$INCLUDE_MINE" = "--include-mine" ]; then
  SELECT='select(true)'
else
  SELECT='select(.flaggedByEyes or (.repliedByViewer | not))'
fi

JQ=".data.viewer.login as \$me
    | [ .data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | . + {
            repliedByViewer: ([.comments.nodes[].author.login] | index(\$me) != null),
            flaggedByEyes:   ([.comments.nodes[].reactions.nodes[].user.login] | index(\$me) != null)
          }
        | $SELECT ]"

gh api graphql -f query="$QUERY" -f owner="$OWNER" -f repo="$REPO" -F pr="$PR" --jq "$JQ"
