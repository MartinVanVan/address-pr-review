#!/usr/bin/env bash
# Replies to a PR review thread, optionally resolving it and/or clearing the 👀 flag.
# Usage: reply-to-thread.sh <thread_id> <body> [--resolve] [--clear-eyes]
#
#   --resolve     mark the thread as resolved
#   --clear-eyes  remove YOUR 👀 (EYES) reactions from the thread's comments, so the
#                 re-check flag is consumed and the thread is not picked up again by
#                 the next run of get-unresolved-threads.sh
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: reply-to-thread.sh <thread_id> <body> [--resolve] [--clear-eyes]" >&2
  exit 64
fi

THREAD_ID="$1"
BODY="$2"
shift 2

RESOLVE=false
CLEAR_EYES=false
for ARG in "$@"; do
  case "$ARG" in
    --resolve)    RESOLVE=true ;;
    --clear-eyes) CLEAR_EYES=true ;;
    *) echo "unknown option: $ARG" >&2; exit 64 ;;
  esac
done

REPLY_QUERY='mutation($threadId: ID!, $body: String!) {
  addPullRequestReviewThreadReply(input: { pullRequestReviewThreadId: $threadId, body: $body }) {
    comment { url }
  }
}'

gh api graphql -f query="$REPLY_QUERY" -f threadId="$THREAD_ID" -f body="$BODY" \
  --jq '.data.addPullRequestReviewThreadReply.comment.url'

if [ "$RESOLVE" = true ]; then
  RESOLVE_QUERY='mutation($threadId: ID!) {
    resolveReviewThread(input: { threadId: $threadId }) {
      thread { isResolved }
    }
  }'
  gh api graphql -f query="$RESOLVE_QUERY" -f threadId="$THREAD_ID" \
    --jq '"resolved: " + (.data.resolveReviewThread.thread.isResolved | tostring)'
fi

if [ "$CLEAR_EYES" = true ]; then
  EYES_QUERY='query($threadId: ID!) {
    viewer { login }
    node(id: $threadId) {
      ... on PullRequestReviewThread {
        comments(first: 100) {
          nodes {
            id
            reactions(first: 100, content: EYES) {
              nodes { user { login } }
            }
          }
        }
      }
    }
  }'

  REMOVE_QUERY='mutation($subjectId: ID!) {
    removeReaction(input: { subjectId: $subjectId, content: EYES }) {
      subject { id }
    }
  }'

  COMMENT_IDS=$(gh api graphql -f query="$EYES_QUERY" -f threadId="$THREAD_ID" \
    --jq '.data.viewer.login as $me
          | [ .data.node.comments.nodes[]
              | select([.reactions.nodes[].user.login] | index($me) != null)
              | .id ][]')

  if [ -z "$COMMENT_IDS" ]; then
    echo "cleared 👀: none found"
  else
    while read -r COMMENT_ID; do
      [ -n "$COMMENT_ID" ] || continue
      gh api graphql -f query="$REMOVE_QUERY" -f subjectId="$COMMENT_ID" \
        --jq '"cleared 👀 on " + .data.removeReaction.subject.id'
    done <<< "$COMMENT_IDS"
  fi
fi
