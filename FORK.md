# cc-pstack

A fork of the [pstack](https://github.com/cursor/plugins/tree/main/pstack) Claude Code tree (`harness/pstack/claude-code`), adapted to one Claude Code setup. The plugin keeps the name `pstack`, so `/pstack:<skill>` and the `pstack:poteto-agent` / `pstack:comment-sicko` agent names work unchanged. Do not enable it together with `pstack@cursor-plugins`.

## What changes from upstream

- **Version control.** Every repo here is a colocated jj repo. Git write commands and git worktrees map to jj (`jj workspace add`, `jj commit`, `jj rebase`, `jj bookmark set` + `jj git push`, `gh pr create --head`). Subagents never get `isolation: "worktree"`.
- **Always-on poteto-mode.** A SessionStart hook (`hooks/poteto-always.sh`) injects `skills/poteto-mode/SKILL.md` into every session, the way Cursor pins a custom mode. Say "poteto-mode off" to drop it for a session. `PSTACK_POTETO=off` in the environment skips it, which the headless jobs set.
- **Models.** The host sets `CLAUDE_CODE_SUBAGENT_MODEL=haiku`, so an `Agent` call without `model` runs on haiku. The mapping never omits `model`, the two agents pin `model: sonnet`, and non-Claude panel seats map to `sonnet` so panels keep two model families. Per-role choices live in `~/.claude/rules/pstack-models.md`.
- **Local equivalents.** Cursor-only steps route to tools that exist here: `web-verify` / `run`, `simplify`, `code-review`, `subscribe_pr_activity`, `loop` / `schedule` / `send_later`, `create_session`, and memmini for past decisions.
- **Host.** bun instead of npm/node, GNU tool syntax on Linux, English for repository text.
- **ponytail.** `ponytail:` comments survive the comment passes, and design-space exploration defaults to one prototype.

The full mapping is [`docs/harness/claude-code.md`](docs/harness/claude-code.md).

## Install

```bash
claude plugin marketplace add ~/projects/cc-pstack
claude plugin install pstack@cc-pstack-local
claude plugin disable pstack@cursor-plugins
```

Claude Code runs a cached copy. After editing this repo, bump `version` in `.claude-plugin/plugin.json` and run `claude plugin update pstack@cc-pstack-local`, then start a new session.

## Upstream sync

The `upstream` bookmark holds the untouched upstream tree. Local changes sit on top as `main`.

```bash
scripts/sync-upstream.sh --check   # list upstream changes since the last import
scripts/sync-upstream.sh           # import them onto `upstream`
jj rebase --ignore-immutable -s 'roots(::main ~ ::upstream)' -d upstream   # main is pushed, so it is immutable
jj git push -b upstream -b main
```
