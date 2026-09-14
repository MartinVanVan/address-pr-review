#!/usr/bin/env bash
# Replies to a PR review thread, optionally resolving it and/or clearing the 👀 flag.
#
# Usage: reply-to-thread.sh <thread_id> <body> [--resolve] [--clear-eyes]
#
#   --resolve        mark the thread as resolved. REFUSED on CodeRabbit threads — see
#                    below. Use --force-resolve to override.
#   --clear-eyes     remove YOUR 👀 (EYES) reactions from the thread's comments, so the
#                    re-check flag is consumed and the thread is not picked up again by
#                    the next run of get-unresolved-threads.sh
#   --force-resolve  allow --resolve on a CodeRabbit thread anyway
#
# CodeRabbit needs no @-mention: a plain reply in its thread is enough to make it re-check
# and post its verdict ("Confirmed as addressed by ..."). Adding a ping on top only makes it
# analyse the same thread twice.
#
# Why CodeRabbit threads are not resolved here: CodeRabbit resolves its own threads once it
# has verified the fix (observed on every venabo PR checked — resolvedBy is
# "coderabbitai[bot]"). Resolving it ourselves pre-empts that verification and throws away
# the one independent check that the fix actually answers the comment.
set -euo pipefail

# CodeRabbit appears as "coderabbitai" in author.login and "coderabbitai[bot]" in
# resolvedBy.login — match both.
CODERABBIT_RE='^coderabbitai(\[bot\])?$'
if [ $# -lt 2 ]; then
  echo "usage: reply-to-thread.sh <thread_id> <body> [--resolve] [--clear-eyes]" >&2
  exit 64
fi

THREAD_ID="$1"
BODY="$2"
shift 2

RESOLVE=false
FORCE_RESOLVE=false
CLEAR_EYES=false
for ARG in "$@"; do
  case "$ARG" in
    --resolve)        RESOLVE=true ;;
    --force-resolve)  RESOLVE=true; FORCE_RESOLVE=true ;;
    --clear-eyes)     CLEAR_EYES=true ;;
    *) echo "unknown option: $ARG" >&2; exit 64 ;;
  esac
done

# Read the thread once, before writing anything: the resolve guard has to fire BEFORE the
# reply is posted, not after.
INFO_QUERY='query($threadId: ID!) {
  viewer { login }
  node(id: $threadId) {
    ... on PullRequestReviewThread {
      comments(first: 50) {
        nodes {
          id
          author { login }
          reactions(first: 20, content: EYES) { nodes { user { login } } }
        }
      }
    }
  }
}'
INFO=$(gh api graphql -f query="$INFO_QUERY" -f threadId="$THREAD_ID")

THREAD_AUTHOR=$(printf '%s' "$INFO" | jq -r '.data.node.comments.nodes[0].author.login // ""')

if [ "$RESOLVE" = true ] && [[ "$THREAD_AUTHOR" =~ $CODERABBIT_RE ]] && [ "$FORCE_RESOLVE" != true ]; then
  cat >&2 <<MSG
refusing to resolve a CodeRabbit thread ($THREAD_AUTHOR).
CodeRabbit resolves its own threads once it has verified the fix; resolving it here
discards that check. Just reply and leave it open, or pass --force-resolve.
MSG
  exit 65
fi

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
  REMOVE_QUERY='mutation($subjectId: ID!) {
    removeReaction(input: { subjectId: $subjectId, content: EYES }) {
      subject { id }
    }
  }'

  COMMENT_IDS=$(printf '%s' "$INFO" \
    | jq -r '.data.viewer.login as $me
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
