# Address PR Review

An agent skill that **reads pull request comments and CI failures and fixes them** — then
stops and asks you before publishing anything.

Works in Claude Code, Codex, Cursor...

> This is a fork of [mnapoli/skill-address-pr-review](https://github.com/mnapoli/skill-address-pr-review).
> Nothing is pushed or replied to without explicit confirmation, threads you already
> replied to yourself are skipped, and a 👀 reaction pulls a skipped thread back in.
> See [Differences from upstream](#differences-from-upstream).

```mermaid
flowchart LR
    A[Open PR] --> B[GitHub code review]
    B --> C[`/address-pr-review`]
    C --> E{You confirm}
    E --> B
    B --> D[Merge PR]
```

Open a PR and invoke `/address-pr-review` in Claude Code (or `$address-pr-review` in Codex):

- Fixes CI failures
- Reads inline pull request comments — ignores resolved ones, and ones you already replied to
- Re-checks a thread you replied to when you react 👀 to it
- Makes code changes
- Reports what it changed and the exact replies it proposes — and waits for your go-ahead
- Replies in the language the thread is written in (a German thread gets a German reply)
- Pushes and replies to each thread **only after you confirm**

![](./screenshot.png)

## Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) installed and authenticated
- Claude Code, Codex, Cursor, or [any agent system that can run shell commands and make code changes](https://agentskills.io/home#where-can-i-use-agent-skills)

## Installation

### In Claude Code

Clone into your Claude Code skills directory:

```bash
git clone git@github.com:MartinVanVan/address-pr-review.git ~/.claude/skills/address-pr-review
```

### In other systems

Most other agent systems read from a ".agents/skills" directory:

```bash
git clone git@github.com:MartinVanVan/address-pr-review.git ~/.agents/skills/address-pr-review
```

## Usage

From a branch with an open PR:

```
/address-pr-review
```

The agent fetches unresolved threads and CI failures and fixes the issues. It may commit
locally, but it will **not** push, reply, or resolve anything until you say so. When it
stops, you get:

- what it changed per thread / CI failure, and what it deliberately left alone
- which threads were 👀 re-checks, and what it concluded on the second look
- **the intended reply for every thread, verbatim** — the text as it would be posted, not a summary of it
- whether it would resolve the thread and clear the 👀
- the commits it would push, and to which branch

One block per thread, like this:

```text
### src/Invoice.php:212 — coderabbitai                [👀 re-check]
Comment:  Null check is unreachable after the early return   https://github.com/…#discussion_r123
Action:   dropped the dead branch, src/Invoice.php:212-218
Reply:
  > Fixed as suggested.
Resolve:  yes          Clear 👀: yes
```

Approve all of it, part of it, or none of it. Edit a reply and it sends your wording
instead — the agent posts the approved text as-is, it does not re-word it.

Replies, resolutions and pushes go out **as your own GitHub account** — `gh`'s
authenticated user. There is no bot identity, so a reply is indistinguishable from one you
typed yourself. That is also why the skill asks first.

## Reply language

Replies match the language the thread is conducted in — a German thread gets a German
reply, an English one an English reply. The language is taken from your own comment in the
thread if you left one, otherwise from the most recent human reviewer, otherwise from the
original comment. Bot comments are the weakest signal, so an English CodeRabbit comment
does not drag a German discussion into English.

Code identifiers, file paths, translation keys, quoted code and log output are left
untranslated.

## The 👀 re-check flag

Because the skill skips threads you have replied to, it needs a way for you to say *"look
at this one again"*. That signal is a 👀 reaction:

1. React 👀 to any comment in the thread — on GitHub, in the PR diff.
2. Re-run `/address-pr-review`. The thread comes back with `flaggedByEyes: true` and the
   agent treats it as a re-check: it reads your earlier reply as context and works out what
   changed or was missed, rather than answering from scratch.
3. Once the thread is dealt with, the agent passes `--clear-eyes`, which removes your
   reaction. The flag is **one-shot** — without this the thread would be reprocessed on
   every subsequent run.

Only **your** 👀 counts. Bots (CodeRabbit among them) use 👀 as an "I'm looking at this"
acknowledgement, and counting theirs would drag threads back in at random.

Resolved threads stay out of scope regardless — 👀 re-opens a skipped thread, not a closed one.

## Differences from upstream

| | Upstream | This fork |
|---|---|---|
| Push & reply | Automatic, at the end of the run | Requires explicit confirmation in chat |
| Thread selection | All unresolved threads | Unresolved threads you have **not** commented in |
| Re-check signal | — | 👀 reaction re-opens a skipped thread, consumed via `--clear-eyes` |
| Reply language | Unspecified | Matches the thread's language |
| `context: fork` | Enabled | Removed — a forked run can't stop to ask you mid-flight |
| Pre-approved tools | All helper scripts | Only the two read-only ones; `reply-to-thread.sh` still prompts |

To get the full unresolved list, including threads you replied to and did not flag:

```bash
bash ./get-unresolved-threads.sh --include-mine
```

## Tips

1. Run Claude Code's [code review in GitHub Actions](https://code.claude.com/docs/en/github-actions) for automatic reviews on every push
2. Run [Codex code review](https://developers.openai.com/codex/integrations/github/) as well
3. Review Claude and Codex's comments and "mark as resolved" those that don't make sense — or just reply to them yourself, this fork skips those too
4. Review the code yourself: open comments inline the PR diff
5. Launch `/address-pr-review` locally so that all comments are addressed
6. Read the proposed changes and replies, then confirm
7. Not happy with how a thread was handled? React 👀 to it and run the skill again
8. Repeat until the PR is ready to merge

## Limitations

- CI failure extraction is designed for GitHub Actions — other CI systems may not work
- Threads and comments are fetched with a hard cap of 100 each, without pagination
